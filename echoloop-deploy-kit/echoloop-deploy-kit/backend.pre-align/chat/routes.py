"""句子级辅导对话接口。"""

import json

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse

from llm import chat_reply
from prompts import CHAT_SENTENCE_PROMPT, lang_name

router = APIRouter()


@router.post("/api/v1/stream/chat/sentence")
async def chat_sentence(request: Request):
    data = await request.json()
    if not isinstance(data, dict):
        raise HTTPException(status_code=400, detail="invalid request body")

    raw_messages = data.get("messages")
    if not isinstance(raw_messages, list):
        raise HTTPException(status_code=400, detail="messages must be a list")
    messages = []
    for item in raw_messages:
        if not isinstance(item, dict):
            raise HTTPException(status_code=400, detail="invalid message")
        role = item.get("role")
        content = item.get("content")
        if role not in ("user", "assistant") or not isinstance(content, str):
            raise HTTPException(status_code=400, detail="invalid message")
        if content.strip():
            messages.append({"role": role, "content": content.strip()})
    if not messages or not any(item["role"] == "user" for item in messages):
        raise HTTPException(status_code=400, detail="a user message is required")
    if messages[-1]["role"] != "user":
        raise HTTPException(status_code=400, detail="last message must be from user")

    raw_context = data.get("context") or {}
    if not isinstance(raw_context, dict):
        raise HTTPException(status_code=400, detail="context must be an object")
    sentence = raw_context.get("sentence")
    if not isinstance(sentence, str) or not sentence.strip():
        raise HTTPException(status_code=400, detail="context.sentence is required")
    raw_target_language = data.get("targetLanguage")
    if raw_target_language is not None and not isinstance(raw_target_language, str):
        raise HTTPException(status_code=400, detail="targetLanguage must be a string")
    target_language = (raw_target_language or "").strip() or "zh-CN"

    system = CHAT_SENTENCE_PROMPT.format(lang=lang_name(target_language))
    context_json = json.dumps(raw_context, ensure_ascii=False, separators=(",", ":"))
    if context_json != "{}":
        system += f"\n\n学习上下文（JSON）：\n{context_json}"

    def event_stream():
        try:
            result = chat_reply(system, messages)
        except Exception as exc:  # noqa: BLE001
            yield json.dumps({"__error": str(exc)}, ensure_ascii=False) + "\n"
            return
        reply = (result.get("reply") or "").strip() or "我目前只能基于当前解析给你讲解，请再具体说明你的问题。"
        yield json.dumps({"delta": reply}, ensure_ascii=False) + "\n"
        yield json.dumps({"done": True}, ensure_ascii=False) + "\n"

    return StreamingResponse(event_stream(), media_type="application/x-ndjson")
