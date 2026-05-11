# Configuration

All configuration lives in the Helm chart's `values.yaml` file at `charts/model-deployment/values.yaml`. This page explains every configuration option.

---

## File Structure

The `values.yaml` is organized into sections under a single `serving:` key, which maps to the `bjw-s/app-template` dependency:

```yaml
serving:                    # ← Passed to app-template subchart
  global:                   # Chart-level settings
  serviceAccount:           # Kubernetes ServiceAccount
  configMaps:               # ConfigMaps
  secrets:                  # Secrets
  rbac:                     # Role & RoleBinding
  persistence:              # PersistentVolumeClaim
  rawResources:             # Custom CRDs (InferenceServices, IngressRoute)
  models:                   # Model definitions (custom values)
  vllm:                     # vLLM engine settings (custom values)
  ingressConfig:            # Ingress settings (custom values)
  knative:                  # Knative settings (custom values)
```

> The `models`, `vllm`, `ingressConfig`, and `knative` sections are **custom values**. They are referenced by template expressions (`{{ .Values.vllm.image.repository }}`) inside the rawResources YAML.

---

## Global Settings

```yaml
serving:
  global:
    nameOverride: model-deployment
    createDefaultServiceAccount: false
```

| Field | Default | Description |
|---|---|---|
| `nameOverride` | `model-deployment` | Override the release name used in resource labels |
| `createDefaultServiceAccount` | `false` | We create our own ServiceAccount, so disable the default |

---

## ServiceAccount

```yaml
  serviceAccount:
    main:
      enabled: true
      forceRename: llm-serviceaccount
```

Creates a service account named `llm-serviceaccount`. Pods use this identity to interact with the Kubernetes API.

| Field | Description |
|---|---|
| `enabled` | Whether to create the resource |
| `forceRename` | Override the auto-generated name |

---

## ConfigMaps

```yaml
  configMaps:
    llm-config:
      enabled: true
      forceRename: llm-config
      data:
        MODEL_NAME: microsoft/phi-2
        TENSOR_PARALLEL_SIZE: "1"
        GPU_MEMORY_UTILIZATION: "0.85"
        MAX_NUM_BATCHED_TOKENS: "8192"
        MAX_NUM_SEQS: "256"
    phi2-chat-template:
      enabled: true
      forceRename: phi2-chat-template
      data:
        chat_template.jinja: |
          {% for message in messages %}
          ...
          {% endfor %}
```

### llm-config

General configuration for the LLM deployment. These are available as environment variables.

| Key | Value | Purpose |
|---|---|---|
| `MODEL_NAME` | `microsoft/phi-2` | Default model identifier |
| `TENSOR_PARALLEL_SIZE` | `1` | Number of GPUs for tensor parallelism (1 = no parallelism, CPU mode) |
| `GPU_MEMORY_UTILIZATION` | `0.85` | Fraction of GPU memory to use (not used on CPU) |
| `MAX_NUM_BATCHED_TOKENS` | `8192` | Maximum tokens across all batched requests |
| `MAX_NUM_SEQS` | `256` | Maximum number of concurrent sequences |

### phi2-chat-template

Custom Jinja2 chat template for Phi-2 (which does not have a built-in one). Mounted at `/chat-template/chat_template.jinja` in the phi-2 predictor pod.

---

## Secrets

```yaml
  secrets:
    llm-secrets:
      enabled: true
      forceRename: llm-secrets
      type: Opaque
      stringData:
        REDIS_PASSWORD: llm_cache_password
        HUGGINGFACE_TOKEN: ""
```

| Key | Default | Purpose |
|---|---|---|
| `REDIS_PASSWORD` | `llm_cache_password` | Password for Redis cache (if deployed) |
| `HUGGINGFACE_TOKEN` | (empty) | HuggingFace authentication token for gated models |

> Fill in `HUGGINGFACE_TOKEN` if you need to access gated models (like Llama, Mistral, etc.).

---

## RBAC

```yaml
  rbac:
    roles:
      llm-role:
        enabled: true
        type: Role
        forceRename: llm-role
        rules:
          - apiGroups: [""]
            resources: ["endpoints", "pods", "services"]
            verbs: ["get", "list", "watch"]
    bindings:
      llm-binding:
        enabled: true
        type: RoleBinding
        forceRename: llm-binding
        subjects:
          - kind: ServiceAccount
            name: llm-serviceaccount
            namespace: llm-system
        roleRef:
          identifier: llm-role
```

The Role grants `get`, `list`, and `watch` permissions on `endpoints`, `pods`, and `services`. This is the minimum set of permissions the model pods need.

| Permission | Why Needed |
|---|---|
| `get`/`list`/`watch` endpoints | For service discovery and communication |
| `get`/`list`/`watch` pods | For monitoring and status checks |
| `get`/`list`/`watch` services | For networking and routing |

---

## Persistence

```yaml
  persistence:
    model-cache:
      enabled: true
      type: persistentVolumeClaim
      forceRename: model-cache
      size: 10Gi
      accessMode: ReadWriteOnce
      retain: true
      storageClass: ""
```

| Field | Value | Description |
|---|---|---|
| `size` | `10Gi` | 10 GB of storage for model weights |
| `accessMode` | `ReadWriteOnce` | Only one pod can write at a time |
| `retain` | `true` | Keep the PVC when the Helm release is deleted |
| `storageClass` | `""` | Use the cluster's default storage class |

The PVC stores downloaded HuggingFace model weights so they do not need to be re-downloaded every time a pod restarts.

---

## Raw Resources (CRDs)

These are custom Kubernetes resources that are passed through the Helm chart as raw YAML.

### Phi-2 InferenceService

```yaml
  rawResources:
    phi2:
      enabled: true
      forceRename: vllm-phi2
      apiVersion: serving.kserve.io/v1beta1
      kind: InferenceService
      labels:
        app: vllm-phi2
      annotations:
        autoscaling.knative.dev/minScale: "1"
        autoscaling.knative.dev/maxScale: "3"
        autoscaling.knative.dev/target: "1"
```

#### Autoscaling Annotations

| Annotation | Value | Meaning |
|---|---|---|
| `autoscaling.knative.dev/minScale` | `1` | Minimum number of pods |
| `autoscaling.knative.dev/maxScale` | `3` | Maximum number of pods |
| `autoscaling.knative.dev/target` | `1` | Target concurrent requests per pod |

#### Predictor Container

```yaml
      spec:
        spec:
          predictor:
            serviceAccountName: llm-serviceaccount
            containers:
              - name: kserve-container
                image: "{{ .Values.vllm.image.repository }}:{{ .Values.vllm.image.tag }}"
                args:
                  - --model={{ .Values.models.phi2.model }}
                  - --max-model-len={{ .Values.models.phi2.maxModelLen }}
                  - --chat-template=/chat-template/chat_template.jinja
```

The `{{ .Values... }}` expressions are **Helm template directives** that reference the custom values sections at the bottom of `values.yaml`. They get replaced with actual values when the chart is rendered.

### DialoGPT InferenceService

Same structure but:

```yaml
    dialogpt:
      forceRename: vllm-dialogpt
      # ...
      args:
        - --model={{ .Values.models.dialogpt.model }}
        - --max-model-len={{ .Values.models.dialogpt.maxModelLen }}
        # No --chat-template (model has built-in)
```

### Traefik IngressRoute

```yaml
    traefik-ingress:
      enabled: true
      forceRename: llm-ingress
      apiVersion: traefik.io/v1alpha1
      kind: IngressRoute
      spec:
        spec:
          entryPoints:
            - web
          routes:
            - match: Host(`vllm-phi2-predictor.llm-system.{{ .Values.ingressConfig.domain }}`)
              services:
                - name: "{{ .Values.knative.gateway.service }}"
                  namespace: "{{ .Values.knative.gateway.namespace }}"
                  port: 80
```

---

## Custom Values

These sections are **not used by app-template directly**. They exist so the template expressions in rawResources can reference them.

### Models

```yaml
  models:
    phi2:
      inferenceService: vllm-phi2
      model: microsoft/phi-2
      maxModelLen: 2048
      resources:
        requests:
          cpu: "4"
          memory: 8Gi
        limits:
          cpu: "8"
          memory: 16Gi
    dialogpt:
      inferenceService: vllm-dialogpt
      model: microsoft/DialoGPT-small
      maxModelLen: 1024
      resources:
        requests:
          cpu: "4"
          memory: 8Gi
        limits:
          cpu: "8"
          memory: 16Gi
```

| Field | Description |
|---|---|
| `inferenceService` | Name of the InferenceService for reference |
| `model` | HuggingFace model ID |
| `maxModelLen` | Maximum sequence length in tokens |
| `resources.requests` | Minimum guaranteed resources |
| `resources.limits` | Maximum allowed resources |

### vLLM

```yaml
  vllm:
    image:
      repository: substratusai/vllm
      tag: main-cpu
      pullPolicy: IfNotPresent
    args:
      host: 0.0.0.0
      port: 8080
      portName: http1
      device: cpu
      dtype: float32
    env:
      HF_HOME: /hf-cache
      HF_HUB_DOWNLOAD_TIMEOUT: "600"
      VLLM_CPU_KVCACHE_SPACE: "4"
```

| Field | Default | Description |
|---|---|---|
| `image.repository` | `substratusai/vllm` | Container image repository |
| `image.tag` | `main-cpu` | Image tag (CPU-optimized build) |
| `args.host` | `0.0.0.0` | Listen on all interfaces |
| `args.port` | `8080` | Container port |
| `args.device` | `cpu` | Run on CPU |
| `args.dtype` | `float32` | 32-bit float precision |
| `env.HF_HOME` | `/hf-cache` | HuggingFace cache directory |
| `env.VLLM_CPU_KVCACHE_SPACE` | `4` | GB of CPU memory for KV cache |

### Ingress

```yaml
  ingressConfig:
    controller: traefik
    domain: llm.local
```

| Field | Default | Description |
|---|---|---|
| `controller` | `traefik` | Ingress controller type |
| `domain` | `llm.local` | Domain suffix for Knative services |

### Knative

```yaml
  knative:
    gateway:
      service: kourier
      namespace: kourier-system
      port: 80
```

| Field | Default | Description |
|---|---|---|
| `service` | `kourier` | Knative gateway service name |
| `namespace` | `kourier-system` | Namespace where Kourier runs |
| `port` | `80` | Port to route traffic to |

---

## Customization Examples

### Change the Phi-2 resource allocation

```yaml
  models:
    phi2:
      resources:
        requests:
          cpu: "6"
          memory: 12Gi
        limits:
          cpu: "12"
          memory: 24Gi
```

After changing, redeploy:

```bash
helm upgrade --install model-deployment charts/model-deployment \
  --namespace llm-system --skip-schema-validation
```

### Add a new model

1. Add the model definition under `models:`
2. Add the InferenceService under `rawResources`
3. Add a route in the IngressRoute

### Change the domain

```yaml
  ingressConfig:
    domain: mycompany.local
```

Also update the Knative domain ConfigMap:

```bash
kubectl patch configmap config-domain -n knative-serving \
  --type merge -p '{"data":{"mycompany.local":""}}'
```

---

## Related

- [Getting Started](getting-started.md) — Quick start guide
- [Deployment](deployment.md) — How to deploy
- [API Reference](api-reference.md) — Endpoints and testing
