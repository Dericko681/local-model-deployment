# Quick Start

From a **fresh Linux machine** to running LLMs in about 10 minutes.

## 1. Install k3s

```bash
curl -sfL https://get.k3s.io | sh -
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

## 2. Install Helm

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## 3. Install KServe + Knative

```bash
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.14.0/kserve.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.16.0/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.16.0/serving-core.yaml
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v1.16.0/kourier.yaml

kubectl patch configmap/config-network -n knative-serving \
  --type merge -p '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

kubectl patch configmap config-domain -n knative-serving \
  --type merge -p '{"data":{"llm.local":""}}'
```

## 4. Install the chart

```bash
helm repo add local-model-deployment https://dericko681.github.io/local-model-deployment
helm repo update
helm upgrade --install model-deployment local-model-deployment/model-deployment \
  --namespace llm-system --create-namespace --skip-schema-validation
```

## 5. Wait for pods

```bash
kubectl wait --for=condition=ready pod -n llm-system -l app=vllm-phi2 --timeout=300s
kubectl wait --for=condition=ready pod -n llm-system -l app=vllm-dialogpt --timeout=300s
```

## 6. Test

```bash
NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

curl -s http://$NODE_IP/v1/chat/completions \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{"model": "microsoft/phi-2", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 50}'
```

---

[Full docs →](getting-started.md)
