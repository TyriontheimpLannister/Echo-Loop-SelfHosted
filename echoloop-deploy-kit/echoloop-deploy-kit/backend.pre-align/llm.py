"""LLM 调用封装（OpenAI 兼容）。

DeepSeek / 通义 / 智谱 / OpenAI 等都兼容这套接口，只需改 config 里的
LLM_BASE_URL 与 LLM_MODEL。
"""
import json
import re

from openai import OpenAI

from config import (
    LLM_API_KEY,
    LLM_BASE_URL,
    LLM_DISABLE_THINKING,
    LLM_MAX_RETRIES,
    LLM_MODEL,
    LLM_TIMEOUT,
)

_client = None


def client() -> OpenAI:
    global _client
    if _client is None:
        # 显式超时 + 自动重试：避免个别请求（如意群 fine 粒度）连接停滞时
        # 无限期挂起，拖垮流式接口。超时后 SDK 会自动重试 LLM_MAX_RETRIES 次。
        _client = OpenAI(
            base_url=LLM_BASE_URL,
            api_key=LLM_API_KEY,
            timeout=LLM_TIMEOUT,
            max_retries=LLM_MAX_RETRIES,
        )
    return _client


def _clean_json(text: str) -> str:
    """去掉 LLM 可能包裹的 ```json ... ``` 代码块。"""
    text = text.strip()
    m = re.search(r"```(?:json)?\s*(.*?)```", text, re.DOTALL)
    if m:
        text = m.group(1).strip()
    return text


def chat_json(system: str, user: str, temperature: float = 0.3) -> dict:
    """调用 LLM 并要求返回 JSON 对象。"""
    extra: dict = {}
    if LLM_DISABLE_THINKING:
        # 关闭 reasoning 模型的思考，直接产出 JSON。见 config.LLM_DISABLE_THINKING 说明。
        extra["extra_body"] = {"thinking": {"type": "disabled"}}
    resp = client().chat.completions.create(
        model=LLM_MODEL,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        response_format={"type": "json_object"},
        temperature=temperature,
        **extra,
    )
    content = resp.choices[0].message.content or "{}"
    return json.loads(_clean_json(content))


def chat_reply(system: str, history: list[dict], temperature: float = 0.3) -> dict:
    extra: dict = {}
    if LLM_DISABLE_THINKING:
        extra["extra_body"] = {"thinking": {"type": "disabled"}}
    messages = [{"role": "system", "content": system}]
    for item in history:
        role = item.get("role")
        content = (item.get("content") or "").strip()
        if not content:
            continue
        messages.append({"role": "user" if role == "user" else "assistant", "content": content})
    resp = client().chat.completions.create(
        model=LLM_MODEL,
        messages=messages,
        response_format={"type": "json_object"},
        temperature=temperature,
        **extra,
    )
    content = resp.choices[0].message.content or "{}"
    return json.loads(_clean_json(content))
