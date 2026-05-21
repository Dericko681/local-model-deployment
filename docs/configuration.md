# Configuration

All configuration lives in the Helm chart's `values.yaml` file at `charts/model-deployment/values.yaml`.

---

## File Structure

```yaml
# Top-level chart configuration
certManager:              # cert-manager integration
inferenceServiceDefaults: # Global defaults for all InferenceServices
servingRuntimes:          # vLLM runtime definitions
inferenceServices:        # Model deployments

serving:                  # bjw-s app-template subchart values
  global:                 # Chart-level settings
  rbac:                   # ClusterRole/ClusterRoleBinding
  configMaps:             # ConfigMaps
  persistence:            # PersistentVolumeClaim
  networkpolicies:        # NetworkPolicy (optional)
  serviceMonitor:         # ServiceMonitor (optional, requires CRDs)
  rawResources:           # PDB, PriorityClass, PrometheusRule (optional)
```

---

## Cert-Manager

| Parameter | Description | Default |
|---|---|---|
| `certManager.enabled` | Enable cert-manager integration | `true` |
| `certManager.useExistingIssuer` | Use existing issuer (skip bootstrap) | `true` |
| `certManager.certificateClass.default` | Default Knative certificate class | `cert-manager.certificate.networking.knative.dev` |
| `certManager.issuers.externalDomain` | External domain issuer ref | See values.yaml |
| `certManager.issuers.clusterLocalDomain` | Cluster-local domain issuer ref | See values.yaml |
| `certManager.issuers.systemInternal` | System internal issuer ref | See values.yaml |
| `certManager.bootstrapLocalCA.enabled` | Bootstrap local CA issuer | `false` |
| `certManager.trustBundle.enabled` | Deploy CA trust bundle ConfigMaps | `true` |
| `certManager.certificate.enabled` | Create ingress TLS Certificate | `false` |

### Encryption Zones

Three encryption zones are configured in `config-certmanager` ConfigMap:

| Zone | Purpose | Issuer Type |
|---|---|---|
| `issuerRef` | External domain certificates | ClusterIssuer |
| `clusterLocalIssuerRef` | Cluster-local domain certificates | ClusterIssuer |
| `systemInternalIssuerRef` | Knative internal TLS | ClusterIssuer |

---

## Inference Service Defaults

Global defaults applied to all models unless overridden per-model:

| Parameter | Description | Default |
|---|---|---|
| `inferenceServiceDefaults.visibility` | Knative visibility | `cluster-local` |
| `inferenceServiceDefaults.deploymentMode` | KServe deployment mode | `Serverless` |
| `inferenceServiceDefaults.observability.enabled` | Enable observability | `true` |
| `inferenceServiceDefaults.observability.prometheus.enabled` | Prometheus scraping | `true` |
| `inferenceServiceDefaults.observability.opentelemetry.enabled` | OTel tracing | `false` |
| `inferenceServiceDefaults.observability.metricAggregation.enabled` | Metric aggregation | `false` |
| `inferenceServiceDefaults.observability.autoscaling.class` | Autoscaler class | `""` |

---

## Serving Runtimes

Define the vLLM container configuration:

```yaml
servingRuntimes:
  vllm-cpu:
    enabled: true
    spec:
      multiModel: false
      protocolVersions: ["v1"]
      supportedModelFormats:
        - name: huggingface
          autoSelect: true
      containers:
        kserve-container:
          image:
            repository: substratusai/vllm
            tag: main-cpu
          env:
            HF_HOME: /hf-cache
          resources: {}
          startupProbe:
            httpGet:
              path: /health
              port: 8080
```

---

## Inference Services

Define model deployments:

```yaml
inferenceServices:
  phi2:
    enabled: true
    name: vllm-phi2
    visibility: cluster-local
    deploymentMode: Serverless
    certificate:
      class: ""                    # "" = use default from certManager.certificateClass
    observability:
      enabled: true
      prometheus:
        enabled: true
    spec:
      predictor:
        minReplicas: 1
        maxReplicas: 3
        model:
          modelFormat:
            name: huggingface
          runtime: vllm-cpu
          storageUri: hf://microsoft/phi-2
```

---

## bjw-s Network Policies

Configured under `serving.networkpolicies`:

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

---

## bjw-s ServiceMonitor

Requires Prometheus Operator CRDs:

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
          path: /metrics
```

---

## bjw-s Raw Resources

### PodDisruptionBudget

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

### PriorityClasses

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
```

### PrometheusRule (requires Prometheus Operator CRDs)

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
              rules:
                - alert: ModelInferenceServiceDown
                  expr: '...'
```

---

## Customization Examples

### Change model resources

```yaml
inferenceServices:
  phi2:
    spec:
      predictor:
        model:
          resources:
            requests:
              cpu: "6"
              memory: 12Gi
```

### Add a new model

Add a ServingRuntime and InferenceService entry:

```yaml
servingRuntimes:
  my-model-runtime:
    enabled: true
    spec:
      containers:
        kserve-container:
          image:
            repository: my-org/my-vllm
            tag: latest

inferenceServices:
  my-model:
    enabled: true
    name: my-model
    spec:
      predictor:
        model:
          modelFormat:
            name: huggingface
          runtime: my-model-runtime
          storageUri: hf://my-org/my-model
```

---

## Related

- [Getting Started](getting-started.md) — Quick start guide
- [Deployment](deployment.md) — How to deploy
- [API Reference](api-reference.md) — Endpoints and testing
