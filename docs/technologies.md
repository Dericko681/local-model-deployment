# Technologies

This page explains each technology in the stack: what it is, why it is used, and how it fits into the system.

---

## vLLM

**What it is**: A high-performance inference engine for Large Language Models.

**Official site**: [https://github.com/vllm-project/vllm](https://github.com/vllm-project/vllm)

### Why vLLM?

Traditional LLM inference has a major memory problem. During text generation, the model needs to remember all previously generated tokens (the "KV cache"). This cache grows with each token and wastes a lot of memory.

vLLM solves this with **PagedAttention** — a memory management technique borrowed from operating systems. Just as virtual memory breaks programs into pages, PagedAttention breaks the KV cache into blocks that can be stored non-contiguously. This:

- **Reduces memory waste** by 60-80%
- **Enables larger batch sizes** (more concurrent users)
- **Increases throughput** (tokens per second)

### How we use it

The vLLM engine runs as the `kserve-container` in the predictor pod, configured via the `ServingRuntime` CRD.

### Image

We use `substratusai/vllm:main-cpu` — a community build optimized for CPU inference. The official vLLM image (`vllm/vllm-openai`) is GPU-only.

---

## KServe

**What it is**: A Kubernetes custom resource definition (CRD) and controller for serving machine learning models.

**Official site**: [https://kserve.github.io](https://kserve.github.io)

### Why KServe?

Deploying an LLM manually requires creating multiple Kubernetes resources. KServe simplifies this with two resources:

- **ServingRuntime** — Defines the runtime container (vLLM image, args, probes)
- **InferenceService** — Defines the model deployment (which runtime, which model, autoscaling)

When you create an InferenceService, KServe:
1. Creates a **Knative Service** (which creates a Revision, which creates a Deployment)
2. Sets up the **predictor pod** with the model container
3. Configures **autoscaling** via Knative
4. Manages **rolling updates** when the model configuration changes
5. Provides **health checking** and readiness gates

### InferenceService spec

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: vllm-phi2
spec:
  predictor:
    model:
      modelFormat:
        name: huggingface
      runtime: vllm-cpu
      storageUri: hf://microsoft/phi-2
```

The model is loaded from HuggingFace via `storageUri`. The runtime references the `ServingRuntime` by name.

---

## Knative Serving

**What it is**: A serverless platform built on Kubernetes that provides autoscaling, revision management, and traffic routing.

**Official site**: [https://knative.dev](https://knative.dev)

### Why Knative?

LLM serving has a unique traffic pattern. Knative provides:

- **Scale to zero** — When there are no requests, pods scale to zero
- **Scale from zero** — The activator buffers requests while a new pod starts
- **Revision tracking** — Every configuration change creates a new revision for rollback
- **Traffic splitting** — Canary deployments between revisions

### Key Concepts

| Concept | What it means |
|---|---|
| **Service** | Top-level resource managing a model deployment |
| **Revision** | An immutable configuration snapshot (created on every change) |
| **Configuration** | Desired state for the revision |
| **Route** | Traffic routing rules (which revision gets how much traffic) |
| **Activator** | Shared component that buffers requests when scaling from zero |

### Autoscaling

```yaml
annotations:
  autoscaling.knative.dev/minScale: "1"
  autoscaling.knative.dev/maxScale: "3"
  autoscaling.knative.dev/target: "1"
```

The autoscaler works on **concurrency** (not CPU or memory).

---

## Kourier (Knative Gateway)

**What it is**: A lightweight Knative ingress gateway based on Envoy.

**Official site**: [https://github.com/knative/net-kourier](https://github.com/knative/net-kourier)

### Why Kourier?

Kourier handles Knative-specific routing:

- Maps hostnames to the correct Knative Service
- Routes to the currently active revision
- Supports traffic splitting between revisions
- Integrates with Knative's autoscaling system

Kourier runs as a Deployment in the `kourier-system` namespace.

---

## cert-manager

**What it is**: A Kubernetes add-on that automates TLS certificate management.

**Official site**: [https://cert-manager.io](https://cert-manager.io)

### Why cert-manager?

Required by KServe for webhook certificates. Also used by the chart to:

- Configure Knative's cert-manager integration (`config-certmanager` ConfigMap)
- Distribute CA trust bundles (`knative-ca-bundle` ConfigMaps)
- Optionally bootstrap a local CA issuer for internal TLS

The chart creates:

| Resource | Purpose |
|---|---|
| `config-certmanager` in `knative-serving` | Tells Knative which issuers to use for TLS |
| `knative-ca-bundle` in multiple namespaces | Distributes the CA certificate for cluster-local TLS |
| `ClusterIssuer` (optional) | Bootstraps a self-signed + CA issuer chain |
| `Certificate` (optional) | Creates an ingress TLS certificate |

---

## bjw-s/app-template

**What it is**: A general-purpose Helm chart for defining Kubernetes applications declaratively.

**Official site**: [https://github.com/bjw-s/helm-charts](https://github.com/bjw-s/helm-charts)

### Why app-template?

Instead of writing separate Helm templates for every resource, app-template lets you define everything in a single `values.yaml` file under the `serving:` key.

```mermaid
flowchart LR
    subgraph values["values.yaml (serving:)"] 
        CM["configMaps"]
        RBAC["rbac"]
        PVC["persistence"]
        NP["networkpolicies"]
        SM["serviceMonitor"]
        RAW["rawResources"]
    end

    subgraph app-template["app-template subchart"]
        T["bjw-s/common template engine"]
    end

    subgraph k8s["Kubernetes Resources"]
        KCM["ConfigMap"]
        KR["ClusterRole/ClusterRoleBinding"]
        KPVC["PVC"]
        KNP["NetworkPolicy"]
        KSM["ServiceMonitor"]
        KPDB["PodDisruptionBudget"]
        KPC["PriorityClass"]
    end

    CM --> T
    RBAC --> T
    PVC --> T
    NP --> T
    SM --> T
    RAW --> T
    T --> KCM
    T --> KR
    T --> KPVC
    T --> KNP
    T --> KSM
    T --> KPDB
    T --> KPC
```

### How rawResources work

The `rawResources` feature embeds arbitrary Kubernetes resources inside the chart. A note about the `spec` field:

The `_rawResource.tpl` template reads the `spec` field from the raw resource entry but renders its contents directly. Values need a double `spec:` wrapper — the outer one for the template to read, the inner one to become the actual Kubernetes `spec:` field.

```yaml
rawResources:
  my-resource:
    spec:         # ← outer: consumed by bjw-s template
      spec:       # ← inner: becomes the actual Kubernetes spec
        key: value
```

---

## Prometheus (Optional)

**What it is**: An open-source monitoring and alerting system.

**Official site**: [https://prometheus.io](https://prometheus.io)

### Why Prometheus?

Prometheus scrapes metrics from the vLLM engine (`/metrics` endpoint). The chart optionally creates:

- **ServiceMonitor** — Tells Prometheus which services to scrape
- **PrometheusRule** — Alerting rules for inference health

Requires the Prometheus Operator CRDs to be installed.

---

## Next Steps

- [See the architecture](architecture.md) in action
- [Deploy the system](deployment.md)
- [Configure the deployment](configuration.md)
