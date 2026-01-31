#!/bin/bash
#
# provision-ec2.sh - Provision AWS EC2 infrastructure for OpenClaw
#
# Usage: ./provision-ec2.sh [--key-name NAME] [--instance-type TYPE]
#
# Prerequisites:
#   - AWS CLI configured (aws configure)
#   - Key pair exists in AWS and locally (~/.ssh/cldy.pem)
#
# What this does:
#   1. Creates security group (if not exists)
#   2. Launches EC2 instance
#   3. Allocates Elastic IP (FIRST - lesson learned!)
#   4. Associates Elastic IP with instance
#   5. Outputs connection info
#

set -e

# Configuration (override with env vars or flags)
AWS_REGION="${AWS_REGION:-us-east-2}"
KEY_NAME="${KEY_NAME:-cldy}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
SECURITY_GROUP_NAME="openclaw-sg"
INSTANCE_NAME="openclaw-server"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --key-name) KEY_NAME="$2"; shift 2 ;;
    --instance-type) INSTANCE_TYPE="$2"; shift 2 ;;
    --region) AWS_REGION="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [--key-name NAME] [--instance-type TYPE] [--region REGION]"
      exit 0
      ;;
    *) error "Unknown option: $1" ;;
  esac
done

log "Provisioning OpenClaw EC2 in ${AWS_REGION}"

# Get latest Ubuntu 24.04 AMI
log "Finding latest Ubuntu 24.04 AMI..."
AMI_ID=$(aws ec2 describe-images \
  --region "$AWS_REGION" \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
            "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

if [[ -z "$AMI_ID" || "$AMI_ID" == "None" ]]; then
  error "Could not find Ubuntu 24.04 AMI"
fi
log "Using AMI: $AMI_ID"

# Get default VPC
VPC_ID=$(aws ec2 describe-vpcs \
  --region "$AWS_REGION" \
  --filters "Name=is-default,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text)
log "Using VPC: $VPC_ID"

# Create or get security group
log "Setting up security group..."
SG_ID=$(aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || echo "None")

if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
  log "Creating security group: $SECURITY_GROUP_NAME"
  SG_ID=$(aws ec2 create-security-group \
    --region "$AWS_REGION" \
    --group-name "$SECURITY_GROUP_NAME" \
    --description "OpenClaw server security group" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)

  # Add rules
  log "Adding firewall rules..."
  aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$SG_ID" \
    --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null  # SSH
  aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$SG_ID" \
    --protocol tcp --port 18789 --cidr 0.0.0.0/0 >/dev/null  # OpenClaw gateway
else
  log "Using existing security group: $SG_ID"
fi

# LESSON LEARNED: Allocate Elastic IP FIRST before instance
log "Allocating Elastic IP (doing this FIRST - learned the hard way)..."
ALLOCATION_ID=$(aws ec2 allocate-address \
  --region "$AWS_REGION" \
  --domain vpc \
  --query 'AllocationId' \
  --output text)

ELASTIC_IP=$(aws ec2 describe-addresses \
  --region "$AWS_REGION" \
  --allocation-ids "$ALLOCATION_ID" \
  --query 'Addresses[0].PublicIp' \
  --output text)

log "Elastic IP allocated: $ELASTIC_IP"

# Launch instance
log "Launching EC2 instance ($INSTANCE_TYPE)..."
INSTANCE_ID=$(aws ec2 run-instances \
  --region "$AWS_REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

log "Instance launched: $INSTANCE_ID"

# Wait for instance to be running
log "Waiting for instance to be running..."
aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$INSTANCE_ID"

# Associate Elastic IP
log "Associating Elastic IP with instance..."
aws ec2 associate-address \
  --region "$AWS_REGION" \
  --instance-id "$INSTANCE_ID" \
  --allocation-id "$ALLOCATION_ID" >/dev/null

# Wait for SSH to be ready
log "Waiting for SSH to be ready (this may take a minute)..."
sleep 30

for i in {1..10}; do
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/${KEY_NAME}.pem ubuntu@${ELASTIC_IP} "echo 'SSH ready'" 2>/dev/null; then
    break
  fi
  log "Waiting for SSH... (attempt $i/10)"
  sleep 10
done

# Output results
echo ""
echo "============================================"
echo -e "${GREEN}EC2 PROVISIONED SUCCESSFULLY${NC}"
echo "============================================"
echo ""
echo "Instance ID:  $INSTANCE_ID"
echo "Elastic IP:   $ELASTIC_IP"
echo "SSH Command:  ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@${ELASTIC_IP}"
echo ""
echo "Add to ~/.ssh/config:"
echo ""
echo "Host openclaw-ec2"
echo "    HostName $ELASTIC_IP"
echo "    User ubuntu"
echo "    IdentityFile ~/.ssh/${KEY_NAME}.pem"
echo ""
echo "Next step - deploy OpenClaw:"
echo "  ssh ubuntu@${ELASTIC_IP} 'bash -s' < scripts/deploy-openclaw-remote.sh"
echo ""

# Save state for later scripts
echo "$ELASTIC_IP" > /tmp/openclaw-elastic-ip.txt
echo "$INSTANCE_ID" > /tmp/openclaw-instance-id.txt
