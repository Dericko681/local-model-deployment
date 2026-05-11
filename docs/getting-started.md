# Getting Started

This guide helps you go from zero to running LLMs on your Kubernetes cluster.

> **Intended audience**: Engineers new to Kubernetes, KServe, or LLM serving. Concepts are explained in simple terms.

---

## Prerequisites

| Requirement | Minimum Version | Why |
|---|---|---|
| Kubernetes cluster | 1.33+ | Required by KServe v0.18 and Knative v1.21 |
| Helm CLI | 3.x | For Helm-based deployment |
| kubectl | 1.33+ | For direct resource management |
| cert-manager | Latest | TLS certificates for KServe webhooks |

### Cluster Resources

Each model pod requires significant CPU and memory:

| Model | CPU Request | Memory Request | CPU Limit | Memory Limit |
|---|---|---|---|---|
| Phi-2 (2.7B) | 4 cores | 8 GB | 8 cores | 16 GB |
| DialoGPT (117M) | 4 cores | 8 GB | 8 cores | 16 GB |

A single-node cluster with at least **8 CPU cores and 32 GB RAM** is recommended.

---

## Install Dependencies

### 0. Install cert-manager (required by KServe v0.18)

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.0/cert-manager.yaml
kubectl wait --for=condition=Available deployment -n cert-manager cert-manager cert-manager-cainjector cert-manager-webhook --timeout=120s
```

### 1. Install KServe

KServe CRDs exceed the 262KB annotation limit — `--server-side --force-conflicts` is required:

```bash
kubectl create namespace kserve
kubectl apply --server-side --force-conflicts \
  -f https://github.com/kserve/kserve/releases/download/v0.18.0/kserve.yaml
```

### 2. Install Knative Serving

```bash
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.21.2/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.21.2/serving-core.yaml
kubectl apply -f https://github.com/knative-extensions/net-kourier/releases/download/knative-v1.21.0/kourier.yaml

kubectl patch configmap/config-network -n knative-serving \
  --type merge -p '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
```

### 3. Configure Knative Domain

```bash
kubectl patch configmap config-domain -n knative-serving \
  --type merge -p '{"data":{"llm.local":""}}'
```

### 4. Enable PVC Support (Required)

The chart mounts a PVC for model cache. Knative disables PVC by default:

```bash
kubectl patch configmap config-features -n knative-serving \
  --type merge -p '{"data":{"kubernetes.podspec-persistent-volume-claim":"enabled"}}'
kubectl patch configmap config-features -n knative-serving \
  --type merge -p '{"data":{"kubernetes.podspec-persistent-volume-write":"enabled"}}'
```

---

## Deploy

```bash
helm repo add local-model-deployment https://dericko681.github.io/local-model-deployment
helm repo update
helm upgrade --install model-deployment local-model-deployment/model-deployment \
  --namespace llm-system --create-namespace --skip-schema-validation
```

---

## Verify

```bash
kubectl wait --for=condition=Ready ksvc/vllm-dialogpt-predictor -n llm-system --timeout=300s
kubectl get inferenceservice -n llm-system
kubectl get pods -n llm-system
```

---

## Test

```bash
NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
KOURIER_PORT=$(kubectl get svc kourier -n kourier-system -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

curl -s http://$NODE_IP:$KOURIER_PORT/v1/chat/completions \
  -H "Host: vllm-dialogpt-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{"model": "microsoft/DialoGPT-small", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 30}'
```

---

## Next Steps

- [Understand the architecture](architecture.md) — How requests flow through the system
- [Learn about the technologies](technologies.md) — What each component does and why
- [See the quick-start for a full from-scratch setup](quick-start.md)
