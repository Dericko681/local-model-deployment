# Quick Start

From a **fresh machine** to running LLMs in ~10 minutes.

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
# cert-manager (required by KServe v0.18)
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

---

## Deploy Chart

```bash
helm repo add local-model-deployment https://dericko681.github.io/local-model-deployment
helm repo update
helm upgrade --install model-deployment local-model-deployment/model-deployment \
  --namespace llm-system --create-namespace --skip-schema-validation
```

---

## Wait & Test

```bash
# Wait for the model to be ready
kubectl wait --for=condition=Ready ksvc/vllm-dialogpt-predictor -n llm-system --timeout=600s

# Check status
kubectl get inferenceservice -n llm-system
kubectl get pods -n llm-system

# Test via Kourier NodePort
NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
KOURIER_PORT=$(kubectl get svc kourier -n kourier-system -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

curl -s http://$NODE_IP:$KOURIER_PORT/v1/chat/completions \
  -H "Host: vllm-dialogpt-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{"model": "microsoft/DialoGPT-small", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 30}'
```

Expected response:

```json
{
    "id": "chatcmpl-...",
    "object": "chat.completion",
    "choices": [{"message": {"role": "assistant", "content": "Hello to all ."}}]
}
```

---

## Notes

- KServe v0.18 requires cert-manager for webhook certificates.
- `--server-side --force-conflicts` is required for KServe CRDs (known issue: kserve/kserve#3487).
- The chart includes a Traefik IngressRoute. For k3d with Traefik disabled, the Traefik CRDs are installed separately. Direct Kourier NodePort access is the reliable test path.
- **Phi-2 (2.7B)** requests 8GB memory; may fail on constrained nodes. DialoGPT (117M) is lighter.

---

[Full docs →](getting-started.md)
