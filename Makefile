.PHONY: help deploy deploy-kserve deploy-domain deploy-phi2 \
        deploy-tls deploy-monitoring \
        helm-deploy helm-destroy \
        test test-phi2 test-dialogpt test-phi2-tls test-dialogpt-tls \
        logs-phi2 logs-dialogpt \
        clean clean-all clean-tls status

help:
	@echo "LLM Production Deployment - vLLM + KServe + Knative"
	@echo ""
	@echo "=== Deploy (kubectl) ==="
	@echo "  deploy            - Deploy full stack (both models)"
	@echo "  deploy-kserve     - Deploy DialoGPT-small InferenceService"
	@echo "  deploy-phi2       - Deploy Phi-2 InferenceService"
	@echo "  deploy-domain     - Configure Knative domain (llm.local)"
	@echo "  deploy-tls        - Deploy TLS (ClusterIssuer + Certificate + HTTPS IngressRoute)"
	@echo ""
	@echo "=== Deploy (Helm) ==="
	@echo "  helm-dep-update   - Update Helm dependencies (bjw-s app-template)"
	@echo "  helm-template     - Render template for validation (dry-run)"
	@echo "  helm-deploy       - Deploy via Helm chart"
	@echo "  helm-destroy      - Uninstall Helm release"
	@echo ""
	@echo "=== Test ==="
	@echo "  test              - Test both models via HTTP"
	@echo "  test-phi2         - Test Phi-2 via HTTP"
	@echo "  test-dialogpt     - Test DialoGPT-small via HTTP"
	@echo "  test-phi2-tls     - Test Phi-2 via HTTPS"
	@echo "  test-dialogpt-tls - Test DialoGPT-small via HTTPS"
	@echo ""
	@echo "=== Logs ==="
	@echo "  logs-phi2         - Show Phi-2 vLLM logs"
	@echo "  logs-dialogpt     - Show DialoGPT-small vLLM logs"
	@echo ""
	@echo "=== Status ==="
	@echo "  status            - Show deployment status"
	@echo ""
	@echo "=== Cleanup ==="
	@echo "  clean             - Remove KServe + Knative resources"
	@echo "  clean-all         - Remove everything"

base:
	@echo "Deploying base infrastructure..."
	kubectl apply -f k8s/namespaces/namespace.yaml
	kubectl apply -f k8s/configmaps/configmaps.yaml
	kubectl apply -f k8s/configmaps/phi2-chat-template.yaml
	kubectl apply -f k8s/secrets/secrets.yaml
	kubectl apply -f k8s/rbac/rbac.yaml
	kubectl apply -f k8s/storage/storage.yaml

deploy-domain:
	@echo "Configuring Knative domain (llm.local)..."
	-kubectl patch configmap config-domain -n knative-serving \
		--type merge -p '{"data":{"llm.local":""}}' 2>/dev/null || \
		echo "Knative config-domain not found. Is Knative installed?"

deploy: base deploy-domain deploy-tls
	@echo "Deploying both InferenceServices..."
	kubectl apply -f k8s/kserve/vllm-inference-service.yaml
	kubectl apply -f k8s/kserve/vllm-phi2-inference-service.yaml
	@echo "Waiting for revisions to be ready..."
	@sleep 5
	@echo ""
	@echo "=== DNS Setup ==="
	@echo "Add to /etc/hosts:"
	@echo "  192.168.4.35  vllm-dialogpt-predictor.llm-system.llm.local"
	@echo "  192.168.4.35  vllm-phi2-predictor.llm-system.llm.local"
	@echo ""
	@echo "=== Test ==="
	@echo "  make test"

# ── Deploy via Helm chart ──
helm-dep-update:
	@echo "Updating Helm chart dependencies (bjw-s app-template)..."
	helm dependency update charts/model-deployment

helm-template:
	helm template model-deployment charts/model-deployment \
		--namespace llm-system --skip-schema-validation

helm-deploy: helm-dep-update
	@echo "Deploying via Helm chart..."
	helm upgrade --install model-deployment charts/model-deployment \
		--namespace llm-system --create-namespace --skip-schema-validation
	@echo "Deploying TLS (kubectl)..."
	$(MAKE) deploy-tls
	@echo "Configuring Knative domain..."
	-kubectl patch configmap config-domain -n knative-serving \
		--type merge -p '{"data":{"llm.local":""}}' 2>/dev/null || \
		echo "Knative config-domain not found."
	@echo ""
	@echo "=== DNS Setup ==="
	@echo "Add to /etc/hosts:"
	@echo "  <node-ip>  vllm-dialogpt-predictor.llm-system.llm.local"
	@echo "  <node-ip>  vllm-phi2-predictor.llm-system.llm.local"

helm-destroy:
	@echo "Removing Helm release..."
	helm uninstall model-deployment --namespace llm-system

deploy-kserve: base deploy-domain
	@echo "Deploying DialoGPT-small..."
	kubectl apply -f k8s/kserve/vllm-inference-service.yaml

deploy-phi2: base deploy-domain
	@echo "Deploying Phi-2..."
	kubectl apply -f k8s/kserve/vllm-phi2-inference-service.yaml

deploy-tls:
	@echo "Deploying TLS (ClusterIssuer + Certificate + IngressRoute)..."
	kubectl apply -f k8s/tls/cluster-issuer.yaml
	kubectl apply -f k8s/tls/certificate.yaml
	kubectl apply -f k8s/ingress/traefik-ingress-tls.yaml
	kubectl apply -f k8s/ingress/traefik-ingress.yaml
	@echo "Waiting for certificate to be ready..."
	@sleep 5
	-kubectl wait --for=condition=Ready certificate llm-tls-cert -n kourier-system --timeout=60s 2>/dev/null || \
		echo "Certificate may still be provisioning. Check: kubectl get certificate -n kourier-system"
	@echo ""
	@echo "=== Test TLS ==="
	@echo "  make test-phi2-tls"
	@echo "  make test-dialogpt-tls"

deploy-monitoring:
	@echo "Deploying Prometheus monitoring..."
	kubectl apply -f k8s/monitoring/prometheus.yaml

HOST=192.168.4.35

test: test-phi2 test-dialogpt

test-phi2:
	@echo "=== Testing Phi-2 ==="
	@curl -s -o /dev/null -w "Health: HTTP %{http_code}\n" \
		http://$(HOST)/health \
		-H "Host: vllm-phi2-predictor.llm-system.llm.local" || \
		echo "Failed. Check: kubectl get revisions -n llm-system"
	@echo ""
	@curl -s \
		-H "Host: vllm-phi2-predictor.llm-system.llm.local" \
		-H "Content-Type: application/json" \
		-d '{"model": "microsoft/phi-2", "messages": [{"role": "user", "content": "Say hello in one word"}], "max_tokens": 10}' \
		http://$(HOST)/v1/chat/completions | python3 -m json.tool

test-dialogpt:
	@echo ""
	@echo "=== Testing DialoGPT-small ==="
	@curl -s -o /dev/null -w "Health: HTTP %{http_code}\n" \
		http://$(HOST)/health \
		-H "Host: vllm-dialogpt-predictor.llm-system.llm.local" || \
		echo "Failed. Check: kubectl get revisions -n llm-system"
	@echo ""
	@curl -s \
		-H "Host: vllm-dialogpt-predictor.llm-system.llm.local" \
		-H "Content-Type: application/json" \
		-d '{"model": "microsoft/DialoGPT-small", "messages": [{"role": "user", "content": "Hello, how are you?"}], "max_tokens": 50}' \
		http://$(HOST)/v1/chat/completions | python3 -m json.tool

test-phi2-tls:
	@echo "=== Testing Phi-2 (HTTPS) ==="
	@curl -s -o /dev/null -w "Health: HTTP %{http_code}\n" \
		--insecure \
		https://$(HOST)/health \
		-H "Host: vllm-phi2-predictor.llm-system.llm.local" || \
		echo "Failed. Check: kubectl get certificate -n kourier-system"
	@echo ""
	@curl -s \
		--insecure \
		-H "Host: vllm-phi2-predictor.llm-system.llm.local" \
		-H "Content-Type: application/json" \
		-d '{"model": "microsoft/phi-2", "messages": [{"role": "user", "content": "Say hello in one word"}], "max_tokens": 10}' \
		https://$(HOST)/v1/chat/completions | python3 -m json.tool

test-dialogpt-tls:
	@echo ""
	@echo "=== Testing DialoGPT-small (HTTPS) ==="
	@curl -s -o /dev/null -w "Health: HTTP %{http_code}\n" \
		--insecure \
		https://$(HOST)/health \
		-H "Host: vllm-dialogpt-predictor.llm-system.llm.local" || \
		echo "Failed. Check: kubectl get certificate -n kourier-system"
	@echo ""
	@curl -s \
		--insecure \
		-H "Host: vllm-dialogpt-predictor.llm-system.llm.local" \
		-H "Content-Type: application/json" \
		-d '{"model": "microsoft/DialoGPT-small", "messages": [{"role": "user", "content": "Hello, how are you?"}], "max_tokens": 50}' \
		https://$(HOST)/v1/chat/completions | python3 -m json.tool

logs-phi2:
	@echo "Showing Phi-2 vLLM logs..."
	@kubectl logs -n llm-system -l serving.knative.dev/service=vllm-phi2-predictor --tail=100 -c kserve-container 2>/dev/null || \
		echo "No logs found"

logs-dialogpt:
	@echo "Showing DialoGPT-small vLLM logs..."
	@kubectl logs -n llm-system -l serving.knative.dev/service=vllm-dialogpt-predictor --tail=100 -c kserve-container 2>/dev/null || \
		echo "No logs found"

status:
	@echo "=== KServe InferenceServices ==="
	kubectl get inferenceservice -A 2>/dev/null || echo "(no KServe CRDs)"
	@echo ""
	@echo "=== Knative Services ==="
	kubectl get ksvc -A 2>/dev/null || echo "(no Knative CRDs)"
	@echo ""
	@echo "=== Revisions ==="
	kubectl get revisions -n llm-system 2>/dev/null || echo "(no revisions)"
	@echo ""
	@echo "=== Pods ==="
	kubectl get pods -n llm-system

clean:
	@echo "Removing KServe + Ingress resources..."
	-kubectl delete -f k8s/ingress/traefik-ingress.yaml --ignore-not-found=true
	-kubectl delete -f k8s/kserve/vllm-inference-service.yaml --ignore-not-found=true
	-kubectl delete -f k8s/kserve/vllm-phi2-inference-service.yaml --ignore-not-found=true

clean-all:
	@echo "Removing ALL resources..."
	-$(MAKE) clean
	-$(MAKE) clean-tls
	-kubectl delete -f k8s/storage/storage.yaml --ignore-not-found=true
	-kubectl delete -f k8s/secrets/secrets.yaml --ignore-not-found=true
	-kubectl delete -f k8s/rbac/rbac.yaml --ignore-not-found=true
	-kubectl delete -f k8s/configmaps/phi2-chat-template.yaml --ignore-not-found=true
	-kubectl delete -f k8s/configmaps/configmaps.yaml --ignore-not-found=true
	-kubectl delete -f k8s/namespaces/namespace.yaml --ignore-not-found=true

clean-tls:
	@echo "Removing TLS resources..."
	-kubectl delete -f k8s/ingress/traefik-ingress-tls.yaml --ignore-not-found=true
	-kubectl delete -f k8s/ingress/traefik-ingress.yaml --ignore-not-found=true
	-kubectl delete -f k8s/tls/certificate.yaml --ignore-not-found=true
	-kubectl delete -f k8s/tls/cluster-issuer.yaml --ignore-not-found=true
