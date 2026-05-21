# model-deployment

A Helm chart for deploying large language models (LLMs) on KServe with vLLM, Knative, cert-manager, and Prometheus monitoring. Built on [bjw-s/app-template](https://github.com/bjw-s/helm-charts) for auxiliary resources.

## Prerequisites

- Kubernetes 1.28+
- Helm 3.12+
- [KServe](https://kserve.github.io) v0.13+ with Knative Serving
- [cert-manager](https://cert-manager.io) v1.14+ (optional)
- [Prometheus Operator](https://prometheus-operator.dev) (optional, for ServiceMonitor/PrometheusRule)

## Quick Start

```bash
# Add Helm repo and update dependencies
helm repo add bjw-s https://bjw-s.github.io/helm-charts
helm dependency update charts/model-deployment

# Install
helm install my-models charts/model-deployment --namespace model-ns --create-namespace
```

### Enable all features (requires Prometheus Operator CRDs)

```bash
# Install Prometheus Operator CRDs (if not already installed)
kubectl apply -f https://github.com/prometheus-operator/prometheus-operator/releases/latest/download/bundle.yaml

# Install with full observability
helm install my-models charts/model-deployment --namespace model-ns --create-namespace \
  --set serving.networkpolicies.main.enabled=true \
  --set serving.serviceMonitor.main.enabled=true \
  --set 'serving.rawResources.prometheus-alerts.enabled=true' \
  --set 'serving.rawResources.model-pdb.enabled=true' \
  --set 'serving.rawResources.high-priority.enabled=true' \
  --set 'serving.rawResources.medium-priority.enabled=true' \
  --set 'serving.rawResources.low-priority.enabled=true'
```

## Architecture

This chart uses:
- **KServe ServingRuntime + InferenceService** for LLM model serving
- **bjw-s/app-template** for auxiliary resources (ConfigMap, PVC, RBAC, NetworkPolicy, ServiceMonitor)
- **cert-manager** for automatic TLS certificate management
- **Knative** for serverless scaling
- **Prometheus** for metrics and alerting (via ServiceMonitor + PrometheusRule)

## Configuration

### Global Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `imagePullSecrets` | Global image pull secrets | `[]` |
| `nodeSelector` | Global node selector | `{}` |
| `tolerations` | Global tolerations | `[]` |
| `affinity` | Global affinity rules | `{}` |
| `extraLabels` | Extra labels on custom template resources | `{}` |
| `extraAnnotations` | Extra annotations on custom template resources | `{}` |

### Cert-Manager

| Parameter | Description | Default |
|-----------|-------------|---------|
| `certManager.enabled` | Enable cert-manager integration | `true` |
| `certManager.useExistingIssuer` | Use existing issuer (skip bootstrap) | `true` |
| `certManager.certificateClass.default` | Default certificate class | `cert-manager.certificate.networking.knative.dev` |
| `certManager.issuers.externalDomain` | External domain issuer ref | `{}` |
| `certManager.issuers.clusterLocalDomain` | Cluster-local domain issuer ref | `{}` |
| `certManager.issuers.systemInternal` | System internal issuer ref | `{}` |
| `certManager.bootstrapLocalCA.enabled` | Bootstrap local CA issuer | `false` |
| `certManager.trustBundle.enabled` | Deploy CA trust bundle ConfigMaps | `true` |
| `certManager.certificate.enabled` | Create ingress TLS Certificate | `false` |

### Serving Runtimes

Define vLLM serving runtimes under `servingRuntimes`:

```yaml
servingRuntimes:
  vllm:
    enabled: true
    spec:
      protocolVersions: ["v2"]
      supportedModelFormats:
        - name: vLLM
      containers:
        kserve-container:
          image:
            repository: docker.io/vllm/vllm-openai
            tag: latest
          resources:
            limits:
              cpu: "4"
              memory: 16Gi
              nvidia.com/gpu: "1"
```

### Inference Services

Define model deployments under `inferenceServices`:

```yaml
inferenceServices:
  phi2:
    enabled: true
    name: phi2
    visibility: cluster-local
    deploymentMode: Serverless
    spec:
      predictor:
        minReplicas: 0
        maxReplicas: 3
        model:
          modelFormat:
            name: vLLM
          runtime: vllm
          storageUri: s3://models/phi2
```

### Observability

Enable Prometheus scraping, OTel sidecar injection, and autoscaling per model:

```yaml
inferenceServiceDefaults:
  observability:
    enabled: true
    prometheus:
      enabled: true
      path: /metrics
      port: "8080"
      scheme: http
    opentelemetry:
      enabled: false
      sidecarInject: ""
    metricAggregation:
      enabled: false
    autoscaling:
      class: ""
      metrics: []
```

### Network Policy

Configured via bjw-s `serving.networkpolicies`:

```yaml
serving:
  networkpolicies:
    main:
      enabled: true
      podSelector: {}
      policyTypes:
        - Ingress
        - Egress
      rules:
        ingress:
          - from:
              - namespaceSelector:
                  matchLabels:
                    kubernetes.io/metadata.name: knative-serving
        egress:
          - to:
              - namespaceSelector: {}
            ports:
              - protocol: TCP
                port: 443
```

### ServiceMonitor

Requires Prometheus Operator CRDs. Configured via bjw-s `serving.serviceMonitor`:

```yaml
serving:
  serviceMonitor:
    main:
      enabled: true
      selector:
        matchLabels:
          serving.kserve.io/inferenceservice: vllm-phi2
      endpoints:
        - port: http1
          interval: 30s
          scrapeTimeout: 10s
          path: /metrics
          scheme: http
```

### PrometheusRule

Requires Prometheus Operator CRDs. Configured via bjw-s `serving.rawResources`:

```yaml
serving:
  rawResources:
    prometheus-alerts:
      enabled: true
      apiVersion: monitoring.coreos.com/v1
      kind: PrometheusRule
      spec:
        spec:
          groups:
            - name: model-inference
              interval: 30s
              rules:
                - alert: ModelInferenceServiceDown
                  expr: 'kserve_inference_service_status_ready{namespace="{{ .Release.Namespace }}"} == 0'
                  for: 5m
                  labels:
                    severity: critical
                  annotations:
                    summary: "Inference Service is down"
```

### Pod Disruption Budget

Configured via bjw-s `serving.rawResources`:

```yaml
serving:
  rawResources:
    model-pdb:
      enabled: true
      apiVersion: policy/v1
      kind: PodDisruptionBudget
      spec:
        spec:
          minAvailable: 1
          selector:
            matchLabels:
              app.kubernetes.io/component: predictor
```

### Priority Classes

Configured via bjw-s `serving.rawResources`:

```yaml
serving:
  rawResources:
    high-priority:
      enabled: true
      apiVersion: scheduling.k8s.io/v1
      kind: PriorityClass
      spec:
        value: 1000000
        globalDefault: false
        description: "High priority for critical inference services"
    medium-priority:
      enabled: true
      apiVersion: scheduling.k8s.io/v1
      kind: PriorityClass
      spec:
        value: 100000
        globalDefault: true
        description: "Medium priority for standard inference services"
```

## Development

```bash
# Lint chart
helm lint charts/model-deployment

# Render templates
helm template test charts/model-deployment --namespace model-ns

# Dry-run install
helm install test charts/model-deployment --namespace model-ns --create-namespace --dry-run
```
