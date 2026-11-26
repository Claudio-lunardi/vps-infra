#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Uma mudança nos YAMLs também recarrega configurações copiadas no startup.
# O hash evita reiniciar o jogo ao reaplicar exatamente os mesmos manifests.
config_hash=$(sha256sum ./*.yaml | sha256sum | cut -d ' ' -f 1)
manifest_dir=$(mktemp -d)
trap 'rm -rf -- "$manifest_dir"' EXIT
cp -- ./*.yaml "$manifest_dir/"
kubectl patch --local -f deployment.yaml --type=merge \
  -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"vps-infra/config-sha256\":\"$config_hash\"}}}}}" \
  -o yaml > "$manifest_dir/deployment.yaml"

kubectl apply -f "$manifest_dir/"
kubectl -n laboratorio rollout status deployment/minecraft --timeout=20m
kubectl -n laboratorio get pods,services,pvc
