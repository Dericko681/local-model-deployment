# Getting Started

This guide helps you go from zero to running LLMs on your Kubernetes cluster.

> **Intended audience**: Engineers new to Kubernetes, KServe, or LLM serving. Concepts are explained in simple terms.

---

## Prerequisites

| Requirement | Minimum Version | Why |
|---|---|---|
| Kubernetes cluster | 1.28+ | Required by KServe and Knative |
| Helm CLI | 3.x | For Helm-based deployment |
| kubectl | 1.28+ | For direct resource management |
| Traefik | (k3s built-in) | Entrypoint for HTTP traffic |
| KServe CRDs | Latest | InferenceService custom resources |
| Knative Serving | Latest | Autoscaling and revision management |

If you are using **k3s** (a lightweight Kubernetes distribution), Traefik is included by default.

### Cluster Resources

Each model pod requires significant CPU and memory:

| Model | CPU Request | Memory Request | CPU Limit | Memory Limit |
|---|---|---|---|---|
| Phi-2 (2.7B) | 4 cores | 8 GB | 8 cores | 16 GB |
| DialoGPT (117M) | 4 cores | 8 GB | 8 cores | 16 GB |

A single-node cluster with at least **8 CPU cores and 32 GB RAM** is recommended.

---

## Install Dependencies

### 1. Install KServe

```bash
# Set KServe version
export KSERVE_VERSION=v0.14.0

# Install KServe CRDs and controller
kubectl apply -f https://github.com/kserve/kserve/releases/download/${KSERVE_VERSION}/kserve.yaml
```

### 2. Install Knative Serving

```bash
# Install Knative Serving CRDs
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.16.0/serving-crds.yaml

# Install Knative Serving core
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.16.0/serving-core.yaml

# Install Kourier (Knative gateway)
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v1.16.0/kourier.yaml

# Configure Knative to use Kourier
kubectl patch configmap/config-network \
  -n knative-serving \
  --type merge \
  -p '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
```

### 3. Configure Knative Domain (Optional but Recommended)

```bash
kubectl patch configmap config-domain \
  -n knative-serving \
  --type merge \
  -p '{"data":{"llm.local":""}}'
```

This sets the default domain suffix to `llm.local` (used in hostnames).

---

## Deploy

You can deploy in two ways:

### Option A: Helm (Recommended)

```bash
cd charts/model-deployment
helm dependency update
helm upgrade --install model-deployment . \
  --namespace llm-system \
  --create-namespace
```

> The `--skip-schema-validation` flag is used to bypass Helm's built-in schema checks since raw CRDs (KServe, Traefik) are included.

### Option B: kubectl

```bash
make deploy
```

This applies all resource files from the `k8s/` directory in the correct order.

---

## Verify

```bash
# Check InferenceServices
kubectl get inferenceservice -n llm-system

# Check pods (wait for Running status)
kubectl get pods -n llm-system -w

# Check Knative services
kubectl get ksvc -n llm-system
```

Expected output:

```
NAME            URL                                               READY
vllm-phi2       http://vllm-phi2-predictor.llm-system.llm.local   True
vllm-dialogpt   http://vllm-dialogpt-predictor.llm-system.llm.local   True
```

---

## Test the Models

```bash
# Test Phi-2
curl -s \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{"model": "microsoft/phi-2", "messages": [{"role": "user", "content": "Say hello"}], "max_tokens": 50}' \
  http://<NODE-IP>/v1/chat/completions

# Test DialoGPT
curl -s \
  -H "Host: vllm-dialogpt-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{"model": "microsoft/DialoGPT-small", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 50}' \
  http://<NODE-IP>/v1/chat/completions
```

Replace `<NODE-IP>` with your cluster's node IP (e.g., `192.168.4.35`).

### DNS Setup (Optional)

Add these entries to your `/etc/hosts` for friendlier access:

```
<NODE-IP>  vllm-phi2-predictor.llm-system.llm.local
<NODE-IP>  vllm-dialogpt-predictor.llm-system.llm.local
```

---

## Next Steps

- [Understand the architecture](architecture.md) — How requests flow through the system
- [Learn about the technologies](technologies.md) — What each component does and why
- [Explore the configuration](configuration.md) — Customize your deployment
