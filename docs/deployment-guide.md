# Deployment Guide

## Overview

This cluster runs on a single-node k3s installation at `192.168.4.35`. LLM models are served via KServe InferenceServices, which create Knative Services with autoscaling and revision management.

## Stack

- **Kubernetes**: k3s v1.35.4
- **Ingress**: Traefik v3.6.13 (k3s default)
- **Knative Serving**: v1.16.0 with Kourier networking
- **KServe**: Latest (serving.kserve.io/v1beta1)
- **Inference Engine**: vLLM (`substratusai/vllm:main-cpu`)

## Deploy

```bash
# 1. Base infra (namespace, configmaps, secrets, RBAC, storage)
kubectl apply -f k8s/namespaces/
kubectl apply -f k8s/configmaps/
kubectl apply -f k8s/secrets/
kubectl apply -f k8s/rbac/
kubectl apply -f k8s/storage/

# 2. Configure Knative domain
kubectl patch configmap config-domain -n knative-serving \
  --type merge -p '{"data":{"llm.local":""}}'

# 3. Deploy InferenceServices
kubectl apply -f k8s/kserve/vllm-inference-service.yaml       # DialoGPT-small
kubectl apply -f k8s/kserve/vllm-phi2-inference-service.yaml  # Phi-2

# 4. Deploy Traefik ingress
kubectl apply -f k8s/ingress/traefik-ingress.yaml

# Or use make:
make deploy
```

## Request Flow

```
Client ──► Traefik (port 80)
              │ Host: *.llm.local
              ▼
         Kourier (Envoy, kourier-system)
              │ Host match → queue-proxy:8013
              ▼
         Queue-Proxy (Knative sidecar)
              │ HTTP/1.1 → kserve-container:8080
              ▼
         vLLM (model inference)
```

## Models

| Service | Model | max-model-len |
|---------|-------|:---|
| `vllm-llm` | microsoft/DialoGPT-small | 1024 |
| `vllm-phi2` | microsoft/phi-2 | 2048 |

## Switching Models

```bash
# Edit model name and args in the InferenceService YAML
vim k8s/kserve/vllm-phi2-inference-service.yaml
kubectl apply -f k8s/kserve/vllm-phi2-inference-service.yaml

# Watch new revision roll out
kubectl get revisions -n llm-system -w
```

## Troubleshooting

### Check revision rollout
```bash
kubectl get revisions -n llm-system
kubectl get pods -n llm-system
```

### View vLLM logs
```bash
kubectl logs -n llm-system -l serving.knative.dev/service=vllm-phi2-predictor -c kserve-container
```

### View queue-proxy logs
```bash
kubectl logs -n llm-system -l serving.knative.dev/service=vllm-phi2-predictor -c queue-proxy
```

### Test from inside cluster
```bash
kubectl exec -n llm-system deploy/your-pod -c kserve-container -- \
  curl -s http://localhost:8080/v1/models
```

### Clean up
```bash
kubectl delete -f k8s/kserve/
kubectl delete -f k8s/ingress/
kubectl delete -f k8s/storage/
kubectl delete -f k8s/secrets/
kubectl delete -f k8s/rbac/
kubectl delete -f k8s/configmaps/
kubectl delete -f k8s/namespaces/
```
