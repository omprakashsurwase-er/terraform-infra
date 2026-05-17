################################################################################
# LOAD BALANCER & INGRESS CONFIGURATION
################################################################################
#
# This configures external access to applications running in GKE.
#
# ARCHITECTURE:
#   Internet → Cloud Load Balancer (SSL termination)
#     ↓
#   Ingress Controller (in GKE)
#     ↓
#   Application Services (HTTP backend)
#

################################################################################
# STATIC IP ADDRESS - For the load balancer
################################################################################

# Reserve a static global IP address
# This IP will remain the same even after infrastructure updates
resource "google_compute_global_address" "load_balancer" {
  name         = "${local.name_prefix}-lb-ip"
  address_type = "EXTERNAL"
  project      = var.project_id
  labels       = local.common_labels
}

################################################################################
# MANAGED SSL CERTIFICATE - HTTPS security
################################################################################

# Create a managed SSL certificate for HTTPS
# Google automatically handles renewal (no manual work needed)
resource "google_compute_managed_ssl_certificate" "app_cert" {
  name    = "${local.name_prefix}-cert"
  project = var.project_id
  
  managed {
    domains = [var.domain_name]  # e.g., api.example.com
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# BACKEND SERVICE - Defines how traffic is routed to GKE
################################################################################

# Backend service for HTTP backend (GKE services)
resource "google_compute_backend_service" "gke_backend" {
  name            = "${local.name_prefix}-backend"
  protocol        = "HTTP2"  # Use HTTP/2 for better performance
  session_affinity = "NONE"
  
  # Health check configuration
  health_checks = [google_compute_health_check.app_health.id]
  
  # Connection draining timeout
  connection_draining_timeout_sec = 300
  
  # Circuit breaker settings (prevent cascading failures)
  circuit_breakers {
    max_connections         = 100
    max_pending_requests     = 100
    max_requests            = 100
    max_requests_per_connection = 2
  }
  
  # Session affinity for stateful connections
  session_affinity = "CLIENT_IP"
  affinity_cookie_ttl_sec = 3600
  
  project = var.project_id
}

################################################################################
# HEALTH CHECK - Verify backends are healthy
################################################################################

# Health check for application endpoints
resource "google_compute_health_check" "app_health" {
  name    = "${local.name_prefix}-health-check"
  project = var.project_id
  
  # HTTP health check endpoint
  http_health_check {
    port               = 8080     # Application port
    request_path       = "/health"  # Health check endpoint
    check_interval_sec = 10       # Check every 10 seconds
    timeout_sec        = 5        # Timeout after 5 seconds
    healthy_threshold  = 2        # 2 successful checks to mark healthy
    unhealthy_threshold = 3       # 3 failed checks to mark unhealthy
  }
}

################################################################################
# URL MAP - Routing rules (route traffic to different backends)
################################################################################

resource "google_compute_url_map" "app_lb" {
  name            = "${local.name_prefix}-url-map"
  default_service = google_compute_backend_service.gke_backend.id
  project         = var.project_id
  
  # Path routing: route different paths to different backends
  path_matcher {
    name            = "api-routes"
    default_service = google_compute_backend_service.gke_backend.id
    
    # Route /api/* to API backend
    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.gke_backend.id
    }
    
    # Route /health to health check backend
    path_rule {
      paths   = ["/health", "/healthz"]
      service = google_compute_backend_service.gke_backend.id
    }
  }
}

################################################################################
# HTTPS PROXY - Terminates SSL/TLS connections
################################################################################

# HTTPS proxy with SSL certificate
resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "${local.name_prefix}-https-proxy"
  url_map          = google_compute_url_map.app_lb.id
  ssl_certificates = [google_compute_managed_ssl_certificate.app_cert.id]
  project          = var.project_id
}

################################################################################
# HTTP REDIRECT - Force HTTP to HTTPS
################################################################################

# HTTP to HTTPS redirect
resource "google_compute_url_map" "http_to_https_redirect" {
  name    = "${local.name_prefix}-http-redirect"
  project = var.project_id
  
  default_url_redirect {
    redirect_response_code = "301"  # Permanent redirect
    https_redirect         = true
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "${local.name_prefix}-http-proxy"
  url_map = google_compute_url_map.http_to_https_redirect.id
  project = var.project_id
}

################################################################################
# FORWARDING RULES - Routing traffic to proxies
################################################################################

# HTTPS forwarding rule
resource "google_compute_global_forwarding_rule" "https_forwarding" {
  name                  = "${local.name_prefix}-https-fw"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  target                = google_compute_target_https_proxy.https_proxy.id
  address               = google_compute_global_address.load_balancer.id
  project               = var.project_id
}

# HTTP forwarding rule (for redirect)
resource "google_compute_global_forwarding_rule" "http_forwarding" {
  name                  = "${local.name_prefix}-http-fw"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_proxy.id
  address               = google_compute_global_address.load_balancer.id
  project               = var.project_id
}

################################################################################
# DNS RECORD - Map domain to load balancer IP
################################################################################

# Create DNS A record pointing to load balancer
# Note: This assumes you manage DNS through Cloud DNS
# If using external DNS provider, manually add this record

resource "google_dns_managed_zone" "app_domain" {
  name        = "${replace(var.domain_name, ".", "-")}-zone"
  dns_name    = "${var.domain_name}."
  project     = var.project_id
  description = "DNS zone for ${var.domain_name}"
  
  # This assumes you have Cloud DNS enabled
  # If using external DNS, remove this resource
}

resource "google_dns_record_set" "app_a_record" {
  name         = google_dns_managed_zone.app_domain.dns_name
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.app_domain.name
  project      = var.project_id
  
  rrdatas = [google_compute_global_address.load_balancer.address]
}

################################################################################
# INGRESS CONTROLLER (IN-CLUSTER)
################################################################################

# Deploy NGINX Ingress Controller using Helm
resource "helm_release" "nginx_ingress" {
  name            = "nginx-ingress"
  repository      = "https://kubernetes.github.io/ingress-nginx"
  chart           = "ingress-nginx"
  namespace       = "ingress-nginx"
  create_namespace = true
  
  values = [jsonencode({
    controller = {
      service = {
        type = "LoadBalancer"
        externalIPs = [google_compute_global_address.load_balancer.address]
      }
      
      # Resource limits for ingress controller
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }
      
      # Enable pod priority
      priorityClassName = "high-priority"
    }
    
    # Enable metrics for Prometheus monitoring
    prometheus = {
      create = true
    }
  })]
  
  depends_on = [
    google_container_cluster.primary
  ]
}

################################################################################
# KUBERNETES INGRESS RESOURCE
################################################################################

# Define Kubernetes Ingress to expose application
resource "kubernetes_ingress_v1" "app_ingress" {
  metadata {
    name      = "${local.name_prefix}-ingress"
    namespace = var.application_namespace
    
    annotations = {
      "kubernetes.io/ingress.class"       = "nginx"
      "cert-manager.io/cluster-issuer"   = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/rate-limit" = "100"
    }
  }
  
  spec {
    # TLS configuration
    tls {
      hosts = [var.domain_name]
      secret_name = "${local.name_prefix}-tls-secret"
    }
    
    # HTTP rules
    rule {
      host = var.domain_name
      
      http {
        path {
          path = "/"
          path_type = "Prefix"
          
          backend {
            service {
              name = "${var.application_name}-service"
              port {
                number = 80
              }
            }
          }
        }
        
        # Health check endpoint (no authentication)
        path {
          path = "/health"
          path_type = "Prefix"
          
          backend {
            service {
              name = "${var.application_name}-service"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
  
  depends_on = [
    helm_release.nginx_ingress,
    kubernetes_namespace.app_namespace
  ]
}

################################################################################
# KUBERNETES SERVICE - Expose application pods
################################################################################

resource "kubernetes_service" "app_service" {
  metadata {
    name      = "${var.application_name}-service"
    namespace = var.application_namespace
  }
  
  spec {
    selector = {
      app = var.application_name
    }
    
    port {
      port        = 80
      target_port = 8080  # Application port inside pod
      protocol    = "TCP"
    }
    
    type = "ClusterIP"  # Internal service (exposed via Ingress)
  }
  
  depends_on = [
    kubernetes_namespace.app_namespace
  ]
}

################################################################################
# KUBERNETES NAMESPACE - Isolate application resources
################################################################################

resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = var.application_namespace
    
    labels = {
      "app.kubernetes.io/name"       = var.application_name
      "app.kubernetes.io/environment" = var.environment
    }
  }
  
  depends_on = [
    google_container_cluster.primary
  ]
}

################################################################################
# OUTPUTS
################################################################################

output "load_balancer_ip" {
  description = "Static IP address of the load balancer"
  value       = google_compute_global_address.load_balancer.address
}

output "load_balancer_url" {
  description = "Application URL via load balancer"
  value       = "https://${var.domain_name}"
}

output "dns_nameservers" {
  description = "Cloud DNS nameservers (add to domain registrar)"
  value       = google_dns_managed_zone.app_domain.name_servers
}
