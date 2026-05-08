# Demo Guide

## Overview

This demo walks through a production-grade LLM deployment stack using **KServe**, **Knative**, and **vLLM** on a single-node k3s cluster. Two models are served simultaneously: Microsoft Phi-2 (2.7B) and Microsoft DialoGPT-small (117M).

---

## 1. Architecture (5 min)

Show the architecture diagram: `docs/architecture.mmd`

**Key talking points:**

- **KServe** is the orchestration layer — we define `InferenceService` CRDs, and it handles the rest
- **Knative** provides serverless serving — revision management, autoscaling, traffic splitting
- **Kourier** is Knative's ingress gateway — routes traffic to the correct revision
- **vLLM** is the inference engine running inside each pod — loads model weights, exposes OpenAI-compatible API
- **Traefik** is the cluster ingress controller — maps `*.llm.local` to Kourier
- **Queue-Proxy** is a Knative sidecar — handles concurrency, health probes, and autoscaling metrics

**Request flow:**
```
Client → Traefik (port 80) → Kourier (Envoy) → Queue-Proxy → vLLM → Model inference → Response
```

**Two models, two pods:**
```
InferenceService: vllm-llm  → Knative Service → Pod: [queue-proxy | vLLM (DialoGPT-small)]
InferenceService: vllm-phi2 → Knative Service → Pod: [queue-proxy | vLLM (Phi-2)]
```

---

## 2. Cluster Walkthrough (5 min)

### Check the namespace

```bash
kubectl get ns llm-system
kubectl get all -n llm-system
```

Show the pods, services, revisions. Point out:
- Two running pods (one per model)
- Old revisions that have scaled to zero
- The ExternalName services that map to Kourier

### Check revisions

```bash
kubectl get revisions -n llm-system
```

Explain: each time we change the InferenceService (model, args, resources), Knative creates a new immutable revision. Old revisions stay around for rollback.

### Check Knative services

```bash
kubectl get ksvc -n llm-system
```

Show the URLs: `http://vllm-phi2-predictor.llm-system.llm.local`

### Check InferenceServices

```bash
kubectl get inferenceservice -n llm-system
```

---

## 3. Making Requests (5 min)

### Test Phi-2 (text generation)

```bash
curl http://192.168.4.35/v1/chat/completions \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "microsoft/phi-2",
    "messages": [{"role": "user", "content": "Write a haiku about Kubernetes"}],
    "max_tokens": 100
  }'
```

**Expected:** Phi-2 generates a creative haiku. Good for demonstrating general text generation.

### Test DialoGPT-small (conversation)

```bash
curl http://192.168.4.35/v1/chat/completions \
  -H "Host: vllm-llm-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "microsoft/DialoGPT-small",
    "messages": [{"role": "user", "content": "Hello, how are you?"}],
    "max_tokens": 50
  }'
```

**Expected:** DialoGPT continues the conversation. Note the difference — smaller model, simpler responses.

### Show the health endpoint

```bash
curl -s http://192.168.4.35/health \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local"
```

### List available models

```bash
curl -s http://192.168.4.35/v1/models \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local" | python3 -m json.tool
```

---

## 4. Under the Hood (5 min)

### Show vLLM logs

```bash
kubectl logs -n llm-system \
  -l serving.knative.dev/service=vllm-phi2-predictor \
  -c kserve-container --tail=20
```

Show: model loading, health checks, request logging.

### Show queue-proxy logs

```bash
kubectl logs -n llm-system \
  -l serving.knative.dev/service=vllm-phi2-predictor \
  -c queue-proxy --tail=20
```

### Show the pod details

```bash
kubectl describe pod -n llm-system \
  -l serving.knative.dev/service=vllm-phi2-predictor
```

Point out:
- Two containers: `kserve-container` (vLLM) and `queue-proxy`
- The `http1` port naming (avoids HTTP/2 issues)
- Resource limits (CPU, memory)
- Volume mounts: model cache PVC, chat template ConfigMap

### Show model cache

```bash
kubectl exec -n llm-system \
  -l serving.knative.dev/service=vllm-phi2-predictor \
  -c kserve-container -- ls -la /hf-cache/
```

---

## 5. Revisions & Rollout (3 min)

### Trigger a new revision

Change an argument (e.g., temperature) and apply:

```bash
# Edit the InferenceService
kubectl edit inferenceservice vllm-phi2 -n llm-system
# Change --max-model-len or add --temperature
# Save and exit
```

### Watch the rollout

```bash
kubectl get revisions -n llm-system -w
kubectl get pods -n llm-system -w
```

Show: new revision is created, new pod spins up, old pod scales down.

---

## 6. Scaling (optional, 2 min)

### Show autoscaler metrics

```bash
kubectl get pod -n llm-system \
  -l serving.knative.dev/service=vllm-phi2-predictor \
  -o jsonpath='{.items[0].metadata.annotations}' | python3 -m json.tool
```

Look for `autoscaling.knative.dev/target` annotation.

### Manual scaling test

Send multiple concurrent requests with `hey` or `ab`:

```bash
# Install hey
# hey -n 50 -c 10 -m POST \
#   -H "Host: vllm-phi2-predictor.llm-system.llm.local" \
#   -H "Content-Type: application/json" \
#   -d '{"model": "microsoft/phi-2", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 10}' \
#   http://192.168.4.35/v1/chat/completions
```

---

## 7. Cleanup (1 min)

```bash
make clean
```

Or individually:

```bash
kubectl delete inferenceservice vllm-llm vllm-phi2 -n llm-system
kubectl delete -f k8s/ingress/traefik-ingress.yaml
```

---

## Troubleshooting Tips

| Problem | Check |
|---------|-------|
| Pod crash-looping | `kubectl logs -n llm-system <pod> -c kserve-container` |
| 502 Bad Gateway | Check queue-proxy logs for HTTP/2 errors (`h2c` vs `http1`) |
| Model not loading | Check PVC exists: `kubectl get pvc -n llm-system` |
| Cannot reach endpoint | Check Traefik IngressRoute: `kubectl get ingressroute -n kourier-system` |
| Revision not ready | `kubectl describe revision -n llm-system <revision>` |
| Out of memory | Check pod resource limits, model size, `--max-model-len` |

---

## Key Files

| File | Purpose |
|------|---------|
| `k8s/kserve/vllm-inference-service.yaml` | DialoGPT-small InferenceService |
| `k8s/kserve/vllm-phi2-inference-service.yaml` | Phi-2 InferenceService |
| `k8s/ingress/traefik-ingress.yaml` | Traefik routing to Kourier |
| `k8s/configmaps/phi2-chat-template.yaml` | Chat template Jinja2 for Phi-2 |
| `k8s/storage/storage.yaml` | PVC for model cache |
| `Makefile` | Deploy, test, cleanup commands |
