graph TB
    subgraph K8s["Kubernetes Cluster"]

        subgraph Infra["Cluster Infrastructure"]
            NS["Namespace"]
            SA["ServiceAccount + RBAC"]
            SEC["Secrets"]
            CONF["ConfigMaps"]
            PVC["PVC (model cache)"]
        end

        subgraph IngressCtrl["Ingress Controller"]
            Ingress["e.g. Traefik, Istio, NGINX<br/>port 80 / 443"]
            IngressRule["Rule: Host(*.domain) → Knative Gateway"]
        end

        subgraph KServe["KServe"]
            IS1["InferenceService: vllm-llm<br/>(DialoGPT-small)"]
            IS2["InferenceService: vllm-phi2<br/>(Phi-2)"]

            subgraph Knative["Knative Serving"]
                KSvc1["Knative Service: vllm-llm-predictor"]
                KSvc2["Knative Service: vllm-phi2-predictor"]
                Rev1["Revision 00004"]
                Rev2["Revision 00002"]
                Autoscaler["Autoscaler"]

                subgraph Pod1["Predictor Pod — DialoGPT-small"]
                    QP1["Queue-Proxy sidecar"]
                    VLLM1["vLLM<br/>model: microsoft/DialoGPT-small<br/>max-model-len: 1024<br/>port 8080"]
                end

                subgraph Pod2["Predictor Pod — Phi-2"]
                    QP2["Queue-Proxy sidecar"]
                    VLLM2["vLLM<br/>model: microsoft/phi-2<br/>max-model-len: 2048<br/>port 8080"]
                end
            end

            subgraph KnativeGW["Knative Gateway"]
                GW["e.g. Kourier, Istio, Contour"]
            end
        end

    end

    Client["Client"] --> Ingress
    Ingress --> IngressRule
    IngressRule --> GW
    GW -->|"vllm-llm-predictor.llm.local"| QP1
    GW -->|"vllm-phi2-predictor.llm.local"| QP2
    QP1 --> VLLM1
    QP2 --> VLLM2

    IS1 --> KSvc1 --> Rev1 --> Pod1
    IS2 --> KSvc2 --> Rev2 --> Pod2
    QP1 -.-> Autoscaler
    QP2 -.-> Autoscaler
    VLLM1 -.-> PVC
    VLLM2 -.-> PVC

    classDef k8sbg fill:#f8fafc,stroke:#334155,stroke-width:2px,color:#0f172a
    classDef infra fill:#eef2ff,stroke:#4f46e5,color:#0f172a
    classDef ingress fill:#f0fdf4,stroke:#16a34a,color:#0f172a
    classDef kserve fill:#fff7ed,stroke:#ea580c,color:#0f172a
    classDef knative fill:#fffbeb,stroke:#d97706,color:#0f172a
    classDef gw fill:#fdf2f8,stroke:#db2777,color:#0f172a
    classDef pod fill:#f5f3ff,stroke:#7c3aed,color:#0f172a

    class K8s k8sbg
    class NS,SA,SEC,CONF,PVC infra
    class Ingress,IngressRule ingress
    class IS1,IS2,KServe kserve
    class KSvc1,KSvc2,Rev1,Rev2,Autoscaler knative
    class GW gw
    class QP1,VLLM1,QP2,VLLM2 pod
