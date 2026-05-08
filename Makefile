.PHONY: help deploy deploy-kserve deploy-domain deploy-phi2 \
        deploy-cache deploy-monitoring \
        test test-phi2 test-dialogpt logs-phi2 logs-dialogpt \
        clean clean-all status

help:
	@echo "LLM Production Deployment - vLLM + KServe + Knative"
	@echo ""
	@echo "=== Deploy ==="
	@echo "  deploy            - Deploy full stack (both models)"
	@echo "  deploy-kserve     - Deploy DialoGPT-small InferenceService"
	@echo "  deploy-phi2       - Deploy Phi-2 InferenceService"
	@echo "  deploy-domain     - Configure Knative domain (llm.local)"
	@echo ""
	@echo "=== Test ==="
	@echo "  test              - Test both models via Traefik"
	@echo "  test-phi2         - Test Phi-2 model"
	@echo "  test-dialogpt     - Test DialoGPT-small model"
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

deploy: base deploy-domain
	@echo "Deploying both InferenceServices..."
	kubectl apply -f k8s/kserve/vllm-inference-service.yaml
	kubectl apply -f k8s/kserve/vllm-phi2-inference-service.yaml
	kubectl apply -f k8s/ingress/traefik-ingress.yaml
	@echo "Waiting for revisions to be ready..."
	@sleep 5
	@echo ""
	@echo "=== DNS Setup ==="
	@echo "Add to /etc/hosts:"
	@echo "  192.168.4.35  vllm-llm-predictor.llm-system.llm.local"
	@echo "  192.168.4.35  vllm-phi2-predictor.llm-system.llm.local"
	@echo ""
	@echo "=== Test ==="
	@echo "  make test"

deploy-kserve: base deploy-domain
	@echo "Deploying DialoGPT-small..."
	kubectl apply -f k8s/kserve/vllm-inference-service.yaml

deploy-phi2: base deploy-domain
	@echo "Deploying Phi-2..."
	kubectl apply -f k8s/kserve/vllm-phi2-inference-service.yaml

deploy-cache:
	@echo "Deploying Redis cache..."
	kubectl apply -f k8s/cache/redis-deployment.yaml

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
		-H "Host: vllm-llm-predictor.llm-system.llm.local" || \
		echo "Failed. Check: kubectl get revisions -n llm-system"
	@echo ""
	@curl -s \
		-H "Host: vllm-llm-predictor.llm-system.llm.local" \
		-H "Content-Type: application/json" \
		-d '{"model": "microsoft/DialoGPT-small", "messages": [{"role": "user", "content": "Hello, how are you?"}], "max_tokens": 50}' \
		http://$(HOST)/v1/chat/completions | python3 -m json.tool

logs-phi2:
	@echo "Showing Phi-2 vLLM logs..."
	@kubectl logs -n llm-system -l serving.knative.dev/service=vllm-phi2-predictor --tail=100 -c kserve-container 2>/dev/null || \
		echo "No logs found"

logs-dialogpt:
	@echo "Showing DialoGPT-small vLLM logs..."
	@kubectl logs -n llm-system -l serving.knative.dev/service=vllm-llm-predictor --tail=100 -c kserve-container 2>/dev/null || \
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
	-kubectl delete -f k8s/storage/storage.yaml --ignore-not-found=true
	-kubectl delete -f k8s/secrets/secrets.yaml --ignore-not-found=true
	-kubectl delete -f k8s/rbac/rbac.yaml --ignore-not-found=true
	-kubectl delete -f k8s/configmaps/phi2-chat-template.yaml --ignore-not-found=true
	-kubectl delete -f k8s/configmaps/configmaps.yaml --ignore-not-found=true
	-kubectl delete -f k8s/namespaces/namespace.yaml --ignore-not-found=true
