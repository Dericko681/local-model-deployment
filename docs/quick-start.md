# Quick Start

From a **fresh machine** to running LLMs quickly.

Pick one cluster option, then run the common steps.

---

## Cluster Setup

### Option A: k3s (bare metal)

```bash
curl -sfL https://get.k3s.io | sh -
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

### Option B: k3d (Docker)

```bash
k3d cluster create md-test --servers 1 --agents 1 \
  --image rancher/k3s:v1.33.11-k3s1 \
  -p "30080-30090:30080-30090@server:0" \
  --k3s-arg "--disable=traefik@server:0" \
  --wait
```

---

## Install Dependencies

```bash
# cert-manager (required by KServe)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.0/cert-manager.yaml
kubectl wait --for=condition=Available deployment -n cert-manager cert-manager cert-manager-cainjector cert-manager-webhook --timeout=120s

# Knative Serving
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.21.2/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.21.2/serving-core.yaml
kubectl apply -f https://github.com/knative-extensions/net-kourier/releases/download/knative-v1.21.0/kourier.yaml

kubectl patch configmap/config-network -n knative-serving \
  --type merge -p '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
kubectl patch configmap config-domain -n knative-serving \
  --type merge -p '{"data":{"llm.local":""}}'

# Enable PVC support (chart mounts a PVC for model cache)
kubectl patch configmap config-features -n knative-serving \
  --type merge -p '{"data":{"kubernetes.podspec-persistent-volume-claim":"enabled"}}'
kubectl patch configmap config-features -n knative-serving \
  --type merge -p '{"data":{"kubernetes.podspec-persistent-volume-write":"enabled"}}'

# KServe (server-side apply required — CRDs exceed 262KB annotation limit)
kubectl create namespace kserve
kubectl apply --server-side --force-conflicts \
  -f https://github.com/kserve/kserve/releases/download/v0.18.0/kserve.yaml
```

### Optional: Prometheus Operator CRDs (for ServiceMonitor/PrometheusRule)

```bash
kubectl apply -f https://github.com/prometheus-operator/prometheus-operator/releases/latest/download/bundle.yaml
```

---

## Deploy Chart

```bash
# Build Helm dependencies
helm dependency update charts/model-deployment

# Deploy
helm upgrade --install model-deployment charts/model-deployment \
  --namespace llm-system --create-namespace

# With all optional features enabled:
helm upgrade --install model-deployment charts/model-deployment \
  --namespace llm-system --create-namespace \
  --set serving.networkpolicies.main.enabled=true \
  --set serving.serviceMonitor.main.enabled=true \
  --set 'serving.rawResources.prometheus-alerts.enabled=true' \
  --set 'serving.rawResources.model-pdb.enabled=true' \
  --set 'serving.rawResources.high-priority.enabled=true' \
  --set 'serving.rawResources.medium-priority.enabled=true' \
  --set 'serving.rawResources.low-priority.enabled=true'
```

---

## Wait & Test

```bash
# Watch pods start
kubectl get pods -n llm-system -w

# Check status
kubectl get inferenceservice -n llm-system
kubectl get pods -n llm-system

# Test via Kourier
kubectl exec -n <namespace> deploy/<predictor-deployment> -c kserve-container \
  -- curl -s http://localhost:8080/v1/models
```

---

## Notes

- KServe requires cert-manager for webhook certificates.
- `--server-side --force-conflicts` is required for KServe CRDs.
- ServiceMonitor and PrometheusRule require the Prometheus Operator CRDs.
- The chart deploys models configured in `inferenceServices` in `values.yaml`.

---

[Full docs →](getting-started.md)
