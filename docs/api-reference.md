# API Reference

vLLM exposes an **OpenAI-compatible API**. Use any OpenAI client library by pointing it at the cluster.

## Base URL

```
http://192.168.4.35
```

All requests require the `Host` header matching the Knative service domain:

| Model | Host Header | Port |
|-------|-------------|:---:|
| Phi-2 | `vllm-phi2-predictor.llm-system.llm.local` | 80 |
| DialoGPT-small | `vllm-llm-predictor.llm-system.llm.local` | 80 |

## Endpoints

### Chat Completions

**POST** `/v1/chat/completions`

```bash
curl http://192.168.4.35/v1/chat/completions \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "microsoft/phi-2",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50,
    "temperature": 0.7
  }'
```

**Response:**
```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 1778237680,
  "model": "microsoft/phi-2",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "Hello\n"
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 11,
    "total_tokens": 14,
    "completion_tokens": 3
  }
}
```

### Text Completions

**POST** `/v1/completions`

```bash
curl http://192.168.4.35/v1/completions \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "microsoft/phi-2",
    "prompt": "Once upon a time",
    "max_tokens": 50
  }'
```

### List Models

**GET** `/v1/models`

```bash
curl http://192.168.4.35/v1/models \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local"
```

### Health Check

**GET** `/health`

```bash
curl -s http://192.168.4.35/health \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local"
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model` | string | required | Model ID (e.g. `microsoft/phi-2`) |
| `messages` | array | required | Chat messages `[{role, content}]` |
| `prompt` | string | required | Text prompt (completions endpoint) |
| `max_tokens` | int | 512 | Max tokens to generate |
| `temperature` | float | 1.0 | Sampling temperature |
| `top_p` | float | 1.0 | Nucleus sampling |
| `stream` | bool | false | Stream tokens via SSE |

## Streaming

```bash
curl http://192.168.4.35/v1/chat/completions \
  -H "Host: vllm-phi2-predictor.llm-system.llm.local" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "microsoft/phi-2",
    "messages": [{"role": "user", "content": "Count to 5"}],
    "stream": true
  }'
```

## Using with OpenAI Client Libraries

### Python

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://192.168.4.35/v1",
    default_headers={
        "Host": "vllm-phi2-predictor.llm-system.llm.local"
    },
    api_key="not-needed"
)

response = client.chat.completions.create(
    model="microsoft/phi-2",
    messages=[{"role": "user", "content": "Hello"}]
)
print(response.choices[0].message.content)
```
