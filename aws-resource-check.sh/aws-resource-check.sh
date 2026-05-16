#!/bin/bash

REGION="ap-south-1"

echo "================ EC2 Instances ================"
aws ec2 describe-instances \
--region $REGION \
--query "Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,PrivateIpAddress,Tags[?Key=='Name']|[0].Value]" \
--output table

echo "================ ECS Clusters ================"
aws ecs list-clusters --region $REGION --output table

echo "================ EKS Clusters ================"
aws eks list-clusters --region $REGION --output table

echo "================ Lambda Functions ================"
aws lambda list-functions \
--region $REGION \
--query "Functions[*].[FunctionName,Runtime,LastModified]" \
--output table

echo "================ RDS Databases ================"
aws rds describe-db-instances \
--region $REGION \
--query "DBInstances[*].[DBInstanceIdentifier,Engine,DBInstanceStatus]" \
--output table

echo "================ S3 Buckets ================"
aws s3 ls

echo "================ Auto Scaling Groups ================"
aws autoscaling describe-auto-scaling-groups \
--region $REGION \
--query "AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity,MinSize,MaxSize]" \
--output table

echo "================ Load Balancers ================"
aws elbv2 describe-load-balancers \
--region $REGION \
--query "LoadBalancers[*].[LoadBalancerName,Type,State.Code,DNSName]" \
--output table

echo "================ EBS Volumes ================"
aws ec2 describe-volumes \
--region $REGION \
--query "Volumes[*].[VolumeId,State,Size]" \
--output table

echo "================ Elastic IPs ================"
aws ec2 describe-addresses \
--region $REGION \
--query "Addresses[*].[PublicIp,AllocationId]" \
--output table

echo "================ NAT Gateways ================"
aws ec2 describe-nat-gateways \
--region $REGION \
--query "NatGateways[*].[NatGatewayId,State,VpcId]" \
--output table
