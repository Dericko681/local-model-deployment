# Getting Started

This guide helps you go from zero to running LLMs on your Kubernetes cluster.

---

## Prerequisites

| Requirement | Minimum Version | Why |
|---|---|---|
| Kubernetes cluster | 1.28+ | Required by KServe and Knative |
| Helm CLI | 3.x | For Helm-based deployment |
| kubectl | 1.28+ | For direct resource management |
| cert-manager | Latest | TLS certificates for KServe webhooks |

### Cluster Resources

Each model pod requires significant CPU and memory:

| Model Size | CPU Request | Memory Request | CPU Limit | Memory Limit |
|---|---|---|---|---|
| 2-3B params (e.g., Phi-2) | 4 cores | 8 GB | 8 cores | 16 GB |
| 100M params (e.g., DialoGPT) | 4 cores | 8 GB | 8 cores | 16 GB |

A single-node cluster with at least **8 CPU cores and 16 GB RAM** is recommended.

---

## Install Dependencies

### 1. Install cert-manager (required by KServe)

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.0/cert-manager.yaml
kubectl wait --for=condition=Available deployment -n cert-manager cert-manager cert-manager-cainjector cert-manager-webhook --timeout=120s
```

### 2. Install KServe

KServe CRDs exceed the 262KB annotation limit — `--server-side --force-conflicts` is required:

```bash
kubectl create namespace kserve
kubectl apply --server-side --force-conflicts \
  -f https://github.com/kserve/kserve/releases/download/v0.18.0/kserve.yaml
```

### 3. Install Knative Serving

```bash
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.21.2/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.21.2/serving-core.yaml
kubectl apply -f https://github.com/knative-extensions/net-kourier/releases/download/knative-v1.21.0/kourier.yaml

kubectl patch configmap/config-network -n knative-serving \
  --type merge -p '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
```

### 4. Configure Knative Domain

```bash
kubectl patch configmap config-domain -n knative-serving \
  --type merge -p '{"data":{"llm.local":""}}'
```

### 5. Enable PVC Support (Required)

The chart mounts a PVC for model cache. Knative disables PVC by default:

```bash
kubectl patch configmap config-features -n knative-serving \
  --type merge -p '{"data":{"kubernetes.podspec-persistent-volume-claim":"enabled"}}'
kubectl patch configmap config-features -n knative-serving \
  --type merge -p '{"data":{"kubernetes.podspec-persistent-volume-write":"enabled"}}'
```

### 6. (Optional) Prometheus Operator CRDs

For ServiceMonitor and PrometheusRule:

```bash
kubectl apply -f https://github.com/prometheus-operator/prometheus-operator/releases/latest/download/bundle.yaml
```

---

## Deploy

```bash
helm dependency update charts/model-deployment
helm upgrade --install model-deployment charts/model-deployment \
  --namespace llm-system --create-namespace
```

---

## Verify

```bash
kubectl get inferenceservice -n llm-system
kubectl get pods -n llm-system
```

---

## Test

```bash
kubectl exec -n llm-system deploy/<predictor-deployment> -c kserve-container \
  -- curl -s http://localhost:8080/v1/models
```

---

## Next Steps

- [Understand the architecture](architecture.md) — How requests flow through the system
- [Learn about the technologies](technologies.md) — What each component does and why
- [Explore configuration options](configuration.md)

