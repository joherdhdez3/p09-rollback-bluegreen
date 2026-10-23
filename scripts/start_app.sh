#!/bin/bash
set -euo pipefail

APP_VERSION="${APP_VERSION:-${DEPLOY_APP_VERSION}}"
export APP_VERSION

cd /opt/mi-app

AWS_REGION="${AWS_REGION:-${DEPLOY_AWS_REGION}}"
export AWS_REGION

detect_instance_ip() {
  local token=""
  local instance_ip=""

  if command -v curl >/dev/null 2>&1; then
    token="$(curl -fsS --connect-timeout 1 --max-time 2 \
      -X PUT \
      -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' \
      'http://169.254.169.254/latest/api/token' || true)"

    if [[ -n "$token" ]]; then
      instance_ip="$(curl -fsS --connect-timeout 1 --max-time 2 \
        -H "X-aws-ec2-metadata-token: $token" \
        'http://169.254.169.254/latest/meta-data/local-ipv4' || true)"
    fi
  fi

  if [[ -z "$instance_ip" ]]; then
    instance_ip="$(hostname -I | awk '{print $1}')"
  fi

  printf '%s' "$instance_ip"
}

INSTANCE_IP="${INSTANCE_IP:-$(detect_instance_ip)}"
export INSTANCE_IP

ECR_REGISTRY="${ECR_REGISTRY:-${DEPLOY_ECR_REGISTRY}}"
if [[ -z "${ECR_REGISTRY}" ]]; then
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
fi
export ECR_REGISTRY

aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin \
  "$ECR_REGISTRY"

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
export COMPOSE_FILE

docker compose -f "$COMPOSE_FILE" pull
docker compose -f "$COMPOSE_FILE" down --remove-orphans
docker compose -f "$COMPOSE_FILE" up -d
docker image prune -f