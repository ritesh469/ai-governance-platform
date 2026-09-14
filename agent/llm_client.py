"""Single OpenAI-SDK client for both real LLM providers.

Groq exposes an OpenAI-compatible /v1 endpoint, so we don't need a second
SDK — just point base_url at Groq and use the Groq API key. Shared by the
agent service, model-governance scripts, and the demo scripts so there is
exactly one place that knows how to reach each provider.
"""
import os
from openai import OpenAI

# Cap on generated tokens per call. Unbounded requests get rejected outright
# on Groq's free tier: it estimates a request's output up front and refuses
# anything over the per-minute output-token budget (observed: a 1168-token
# estimate against a 1000 OTPM limit on qwen/qwen3.8-27b). Bounding output is
# also just correct for an evaluation harness — a degenerate model that loops
# forever should be cut off, not allowed to burn the budget.
MAX_TOKENS = int(os.environ.get("LLM_MAX_TOKENS", "512"))

_ENDPOINTS = {
    "openai": {"base_url": None, "api_key_env": "OPENAI_API_KEY"},
    "groq": {"base_url": "https://api.groq.com/openai/v1", "api_key_env": "GROQ_API_KEY"},
}


def get_client(provider: str) -> OpenAI:
    if provider not in _ENDPOINTS:
        raise ValueError(f"unknown provider '{provider}', expected one of {list(_ENDPOINTS)}")
    cfg = _ENDPOINTS[provider]
    api_key = os.environ.get(cfg["api_key_env"])
    if not api_key:
        raise RuntimeError(f"{cfg['api_key_env']} is not set — copy .env.example to .env and fill it in")
    kwargs = {"api_key": api_key}
    if cfg["base_url"]:
        kwargs["base_url"] = cfg["base_url"]
    return OpenAI(**kwargs)


def chat(provider: str, model_id: str, prompt: str, system: str | None = None) -> str:
    """One real, non-streaming chat completion. Used wherever we need a plain
    text-in/text-out call (MLflow pyfunc model, demo scripts)."""
    client = get_client(provider)
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    resp = client.chat.completions.create(
        model=model_id, messages=messages, temperature=0.2, max_tokens=MAX_TOKENS
    )
    return resp.choices[0].message.content or ""
