terraform {
  backend "s3" {
    bucket         = "terraform-state-dev-123omprakashsurwase"
    key            = "dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-lock"
  }
}
