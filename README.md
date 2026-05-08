# LLM Production Deployment

Production stack for deploying local LLMs using **vLLM**, **KServe**, and **Knative** on a single-node k3s cluster.

## Architecture

```
Client ──► Traefik (port 80)
               │
               ▼
         Kourier (Envoy)
               │
               ▼
         Queue-Proxy (sidecar)
               │
               ▼
         vLLM (kserve-container)
```

| Component | Purpose |
|-----------|---------|
| **vLLM** | High-throughput LLM inference engine with PagedAttention |
| **KServe** | Kubernetes-native model serving via InferenceService CRD |
| **Knative** | Serverless autoscaling, revision management, traffic routing |
| **Kourier** | Lightweight Knative ingress gateway (Envoy-based) |
| **Traefik** | Cluster ingress controller (k3s default), routes *.llm.local to Kourier |

## Prerequisites

- k3s cluster v1.25+
- KServe installed
- Knative Serving + Kourier installed
- 8GB+ free RAM per model

## Quick Start

```bash
# Deploy both models
make deploy
```

## Models Available

| InferenceService | Model | Params | Best For |
|:---|---:|:---|:---|
| `vllm-llm` | microsoft/DialoGPT-small | 117M | Lightweight conversation |
| `vllm-phi2` | microsoft/phi-2 | 2.7B | Text generation, reasoning, code |

## Usage

```bash
curl http://192.168.4.35/v1/chat/completions \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{"model": "microsoft/phi-2", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 50}'
```

All endpoints are **OpenAI-compatible**:
- `POST /v1/chat/completions`
- `POST /v1/completions`
- `GET /v1/models`
- `GET /health`

## Project Structure

```
model-deployment/
├── Makefile
├── k8s/
│   ├── namespaces/namespace.yaml
│   ├── configmaps/
│   │   ├── configmaps.yaml
│   │   └── phi2-chat-template.yaml
│   ├── secrets/secrets.yaml
│   ├── rbac/rbac.yaml
│   ├── storage/storage.yaml
│   ├── kserve/
│   │   ├── vllm-inference-service.yaml      # DialoGPT-small
│   │   └── vllm-phi2-inference-service.yaml  # Phi-2
│   ├── ingress/
│   │   └── traefik-ingress.yaml
│   ├── knative/
│   │   └── vllm-service.yaml
│   ├── vllm/
│   ├── cache/
│   └── monitoring/
└── docs/
    ├── deployment-guide.md
    └── api-reference.md
```

## DNS Setup

Add to `/etc/hosts` on each machine that needs access:

```
192.168.4.35  vllm-llm-predictor.llm-system.llm.local
192.168.4.35  vllm-phi2-predictor.llm-system.llm.local
```

Then use cleaner URLs:

```bash
curl http://vllm-phi2-predictor.llm-system.llm.local/v1/chat/completions ...
```

## Troubleshooting

```bash
# Pod status
kubectl get pods -n llm-system
kubectl describe pod <pod> -n llm-system

# Logs
make logs-kserve

# Delete everything
make clean-all
```
