# Glossary

Terms and definitions for engineers new to Kubernetes, LLMs, and this project.

---

## A

**Activator** — A Knative component that buffers requests while a pod is scaling from zero. Holds the request until the new pod is ready.

**Autoscaling** — Automatically adjusting the number of running pods based on traffic. Knative scales based on concurrent requests (not CPU/memory).

---

## B

**bjw-s/app-template** — A community Helm chart used as a dependency. It provides a declarative way to define ConfigMaps, Secrets, RBAC, PVCs, and custom raw resources.

---

## C

**Chat template** — A Jinja2 template that formats OpenAI-style chat messages into the format a specific model expects. Phi-2 requires a custom chat template; DialoGPT has a built-in one.

**ConfigMap** — A Kubernetes resource for storing non-sensitive configuration data as key-value pairs.

**CRD (Custom Resource Definition)** — An extension to the Kubernetes API. KServe and Traefik both add CRDs (InferenceService and IngressRoute) that are not part of standard Kubernetes.

---

## D

**Deployment** — A Kubernetes resource that manages a set of identical pods. Knative creates a Deployment for each Revision.

**DialoGPT-small** — A 117M-parameter conversational model by Microsoft. Used as the smaller, faster model in this project.

**dtype (Data Type)** — The numerical precision used for model weights. `float32` means 32-bit floating point. Higher precision = more accurate but slower.

---

## E

**EntryPoints** — Traefik's term for network ports it listens on. `web` = port 80, `websecure` = port 443.

**Envoy** — A high-performance proxy used by Kourier to route traffic.

---

## F

**float32** — 32-bit floating point format. The precision used for model inference in this project (CPU mode).

---

## G

---

## H

**Helm** — A package manager for Kubernetes. Charts are packages of pre-configured Kubernetes resources.

**Host header** — An HTTP header that specifies the hostname being requested. Used by Traefik to route requests to the correct model.

**HuggingFace** — A platform hosting thousands of pre-trained ML models, including Phi-2 and DialoGPT-small.

---

## I

**Inference** — The process of running a trained model on new input data to generate predictions or text.

**InferenceService** — A KServe custom resource that defines how to deploy and serve a machine learning model.

**Ingress** — A Kubernetes resource that manages external access to services, typically HTTP/HTTPS traffic.

**IngressRoute** — Traefik's alternative to the standard Kubernetes Ingress resource. Supports more advanced routing features.

---

## J

**Jinja2** — A templating engine for Python. Used to define the chat template for Phi-2.

---

## K

**k3s** — A lightweight Kubernetes distribution for resource-constrained environments (Raspberry Pi, edge devices). Includes Traefik by default.

**Knative** — A serverless platform for Kubernetes that provides autoscaling, revision management, and traffic routing.

**Kourier** — A lightweight Knative ingress gateway based on Envoy. Routes traffic to the correct Knative revision.

**KServe** — A Kubernetes custom resource for serving machine learning models. Defines the InferenceService CRD.

**kserve-container** — The main container in the predictor pod that runs the vLLM engine. Must be named exactly `kserve-container`.

**Kubernetes** — An open-source platform for automating deployment, scaling, and management of containerized applications.

**KV Cache** — Key-Value cache that stores intermediate attention computations during text generation. Avoids recomputing for previously generated tokens.

---

## L

**Liveness probe** — A Kubernetes health check that restarts the container if it fails. Long delay (1800s) to give the model time to load.

**LLM (Large Language Model)** — An AI model trained on vast amounts of text to understand and generate human-like language.

---

## M

**max-model-len** — Maximum number of tokens the model can process in a single request.

**minScale / maxScale** — Knative autoscaling limits. `minScale: 1` keeps at least one pod running. `maxScale: 3` limits to three pods.

---

## N

**Namespace** — A Kubernetes construct for grouping related resources. All model resources live in `llm-system`.

**Node** — A single machine (physical or virtual) in a Kubernetes cluster.

---

## O

**OpenAI-compatible API** — An API format that matches OpenAI's API structure, allowing use of OpenAI SDKs and tools with non-OpenAI models.

---

## P

**PagedAttention** — vLLM's memory management technique that splits the KV cache into fixed-size blocks (pages), reducing memory waste by 60-80%.

**Parameters** — The learned weights of a neural network. More parameters generally means more capable models. Phi-2 has 2.7B, DialoGPT has 117M.

**PersistentVolumeClaim (PVC)** — A request for storage in Kubernetes. Our `model-cache` PVC stores downloaded model weights.

**Phi-2** — A 2.7B parameter language model by Microsoft. The larger, more capable model in this project.

**Pod** — The smallest deployable unit in Kubernetes. A group of one or more containers.

**Predictor** — The section of an InferenceService that defines the model container.

**Probes** — Kubernetes health checks (startup, readiness, liveness) that determine if a pod is healthy and ready to serve traffic.

---

## Q

**Queue-proxy** — A Knative sidecar container injected into each predictor pod. Handles concurrency limiting, metrics collection, and request buffering.

---

## R

**Readiness probe** — A Kubernetes health check that determines if a pod should receive traffic.

**Redis** — An in-memory data store that can be used as a KV cache for LLM inference (optional).

**Revision** — An immutable snapshot of a Knative Service's configuration. Created every time the model configuration changes. Enables rollbacks.

**Role / RoleBinding** — Kubernetes RBAC resources. A Role defines permissions. A RoleBinding assigns them to a ServiceAccount.

---

## S

**Secret** — A Kubernetes resource for storing sensitive data (passwords, tokens).

**Service** — A Kubernetes resource that provides a stable network endpoint for one or more pods.

**ServiceAccount** — A Kubernetes identity for pods. Our pods use `llm-serviceaccount`.

**Sidecar** — An additional container in a pod that provides supporting functionality. The queue-proxy is a sidecar.

**Startup probe** — A Kubernetes health check that runs during container startup. Allows the model time to load before other probes begin.

---

## T

**Temperature** — A sampling parameter that controls randomness in text generation. Lower values (0.1) = more deterministic. Higher values (1.0) = more creative.

**Tokenizer** — Converts text into numbers (tokens) that the model can process, and converts model output numbers back into text.

**Token** — A unit of text that a model processes. A token can be a word, part of a word, or a punctuation mark (~0.75 words per token on average).

**Traefik** — An HTTP reverse proxy and load balancer. Default ingress controller in k3s.

---

## V

**vLLM** — A high-performance LLM inference engine that uses PagedAttention for efficient memory management.

**Volume / VolumeMount** — A volume is a storage resource in a pod. A volumeMount attaches it to a container at a specific path.

---

## W-Z

---
