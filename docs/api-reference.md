# API Reference

Both models expose an **OpenAI-compatible API** through the vLLM inference engine. This means you can use any OpenAI SDK or library to interact with them by changing the base URL.

---

## Base URLs

| Model | Knative Service URL | Host Header |
|---|---|---|
| Phi-2 | `http://vllm-phi2-predictor.llm-system.llm.local` | `vllm-phi2-predictor.llm-system.llm.local` |
| DialoGPT-small | `http://vllm-dialogpt-predictor.llm-system.llm.local` | `vllm-dialogpt-predictor.llm-system.llm.local` |

Both are accessible on port **80** via the Traefik ingress at the cluster node IP (e.g., `192.168.4.35`).

---

## Endpoints

### List Models

```http
GET /v1/models
Host: vllm-phi2-predictor.llm-system.llm.local
```

Returns available models:

```json
{
  "object": "list",
  "data": [
    {
      "id": "microsoft/phi-2",
      "object": "model",
      "created": 1700000000,
      "owned_by": "vllm"
    }
  ]
}
```

### Chat Completions

```http
POST /v1/chat/completions
Host: vllm-phi2-predictor.llm-system.llm.local
Content-Type: application/json
```

Request body:

```json
{
  "model": "microsoft/phi-2",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "What is Kubernetes?"}
  ],
  "max_tokens": 150,
  "temperature": 0.7,
  "top_p": 0.9
}
```

Response:

```json
{
  "id": "cmpl-abc123",
  "object": "chat.completion",
  "created": 1700000000,
  "model": "microsoft/phi-2",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Kubernetes is an open-source platform for automating deployment, scaling, and management of containerized applications."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 18,
    "completion_tokens": 22,
    "total_tokens": 40
  }
}
```

### Text Completions

```http
POST /v1/completions
Host: vllm-phi2-predictor.llm-system.llm.local
Content-Type: application/json
```

```json
{
  "model": "microsoft/phi-2",
  "prompt": "Once upon a time",
  "max_tokens": 100,
  "temperature": 0.8
}
```

### Health Check

```http
GET /health
Host: vllm-phi2-predictor.llm-system.llm.local
```

Returns `200 OK` when the model is ready to serve requests (used by Kubernetes probes).

---

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `model` | string | (required) | Model identifier (e.g., `microsoft/phi-2`) |
| `messages` | array | (required for chat) | Array of message objects with `role` and `content` |
| `prompt` | string | (required for completions) | Input text for text completions |
| `max_tokens` | int | 512 | Maximum tokens to generate |
| `temperature` | float | 1.0 | Sampling temperature (0 = deterministic, higher = more random) |
| `top_p` | float | 1.0 | Nucleus sampling threshold |
| `top_k` | int | -1 | Top-k sampling (default: all tokens) |
| `stream` | bool | false | Whether to stream the response |
| `stop` | string/array | null | Stop sequences |
| `frequency_penalty` | float | 0.0 | Penalize frequent tokens |
| `presence_penalty` | float | 0.0 | Penalize tokens that have appeared |

---

## Model Specifications

| Property | Phi-2 | DialoGPT-small |
|---|---|---|
| Parameters | 2.7 billion | 117 million |
| Architecture | Transformer decoder | Transformer decoder |
| Max sequence length | 2048 tokens | 1024 tokens |
| Device | CPU | CPU |
| Data type | float32 | float32 |
| Chat template | Custom Jinja2 (see below) | Built-in |

### Phi-2 Chat Template

Phi-2 does not have a built-in chat template, so we provide one via a ConfigMap:

```
{% for message in messages %}
{% if message['role'] == 'user' %}
User: {{ message['content'] }}
{% elif message['role'] == 'assistant' %}
Assistant: {{ message['content'] }}
{% elif message['role'] == 'system' %}
System: {{ message['content'] }}
{% endif %}
{% endfor %}
{% if add_generation_prompt %}
Assistant:
{% endif %}
```

This transforms OpenAI-style messages into Phi-2's expected format:

```
User: What is Kubernetes?
Assistant: Kubernetes is...
```

---

## Testing

### Using curl

```bash
# Set your cluster node IP
NODE_IP=192.168.4.35

# Test Phi-2 health
curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local" \
  http://$NODE_IP/health

# Test Phi-2 chat
curl -s \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{"model": "microsoft/phi-2", "messages": [{"role": "user", "content": "Say hello in one word"}], "max_tokens": 10}' \
  http://$NODE_IP/v1/chat/completions | python3 -m json.tool

# Test DialoGPT chat
curl -s \
  -H "Host: vllm-dialogpt-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{"model": "microsoft/DialoGPT-small", "messages": [{"role": "user", "content": "Hello, how are you?"}], "max_tokens": 50}' \
  http://$NODE_IP/v1/chat/completions | python3 -m json.tool
```

### Using Python (OpenAI SDK)

```python
from openai import OpenAI

# Point to your local deployment
client = OpenAI(
    base_url="http://192.168.4.35/v1",
    api_key="not-needed",  # vLLM does not require an API key by default
    default_headers={"Host": "vllm-phi2-predictor.llm-system.llm.local"}
)

response = client.chat.completions.create(
    model="microsoft/phi-2",
    messages=[
        {"role": "user", "content": "What is Kubernetes?"}
    ],
    max_tokens=150
)

print(response.choices[0].message.content)
```

> Note: The `Host` header must be passed because Traefik routes based on it. Without it, the request will not reach the correct model.

---

## Streaming

The API supports streaming via Server-Sent Events (SSE):

```bash
curl -s \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{"model": "microsoft/phi-2", "messages": [{"role": "user", "content": "Count to 5"}], "stream": true, "max_tokens": 50}' \
  http://192.168.4.35/v1/chat/completions
```

Each event looks like:

```
data: {"id":"...","object":"chat.completion.chunk","choices":[{"delta":{"content":"1"},"index":0}]}

data: {"id":"...","object":"chat.completion.chunk","choices":[{"delta":{"content":"2"},"index":0}]}

data: [DONE]
```

---

## Related

- [Getting Started](getting-started.md) — Quick start guide
- [Deployment](deployment.md) — How to deploy
- [Configuration](configuration.md) — All configuration options
