"""Echo Loop 自建 AI 后端（FastAPI）。

复刻 Echo Loop 官方后端的核心接口，自用、免订阅、可常驻在局域网机器上。
所有接口忽略 Authorization（自用后端不鉴权）。

接口清单（与客户端 lib/services/*.dart 严格对齐）：
  POST /api/v1/stream/translate        (NDJSON 流式，客户端 sentence_ai_api_client.translateStream)
  POST /api/v1/stream/analyze          (NDJSON 流式，客户端 analyzeStream)
  POST /api/v1/stream/sense-groups     (NDJSON 流式，客户端 senseGroupsStream)
  POST /api/v1/stream/lookup-word      (NDJSON 流式)
  POST /api/v1/stream/lookup-phrase    (NDJSON 流式)
  POST /api/v1/stream/chat/sentence    (NDJSON 句子级辅导对话)
  POST /api/v2/ai/translate            (非流式，兼容/自检用)
  POST /api/v2/ai/analyze              (非流式，兼容/自检用)
  POST /api/v2/ai/sense-groups         (非流式，兼容/自检用)
  POST /api/v2/user-audio/upload-url
  PUT  /api/v2/user-audio/raw-upload    (伪 R2 上传接收，已防路径穿越 + 限流)
  POST /api/v2/user-audio/submit-transcription
  GET  /api/v2/user-audio/job-status/{job_id}
  GET  /api/v2/user-audio/transcript

安全说明：监听 0.0.0.0 且接口无鉴权，仅限家庭 LAN 使用，切勿暴露到公网/WAN。
"""
import asyncio
import json
import uuid
from datetime import datetime
import os
import re

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles

from chat.routes import router as chat_router
from config import HOST, PORT, UPLOAD_DIR, UPDATES_DIR, HOMESCHOOLING_PACKAGES_DIR
from dictionary import entry_ndjson_stream
from llm import chat_json
from prompts import (
    ANALYZE_PROMPT,
    PHRASE_PROMPT,
    SENSE_GROUP_PROMPT,
    TRANSLATE_PROMPT,
    WORD_PROMPT,
    lang_name,
)
from transcribe import jobs, submit_transcription as _submit_transcription

os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(UPDATES_DIR, exist_ok=True)
os.makedirs(HOMESCHOOLING_PACKAGES_DIR, exist_ok=True)

app = FastAPI(title="Echo Loop 自建 AI 后端")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(chat_router)


# ── 工具 ──
_MIME_EXT = {
    "audio/mpeg": ".mp3",
    "audio/mp3": ".mp3",
    "audio/mp4": ".m4a",
    "audio/x-m4a": ".m4a",
    "audio/aac": ".aac",
    "audio/wav": ".wav",
    "audio/x-wav": ".wav",
    "audio/wave": ".wav",
    "audio/ogg": ".ogg",
    "audio/flac": ".flac",
    "audio/webm": ".weba",
    "audio/amr": ".amr",
}


def _ext_from_mime(mime: str) -> str:
    return _MIME_EXT.get((mime or "").lower(), ".audio")


def _utc_now() -> str:
    return datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")


def _target_lang(req_lang: str | None) -> str:
    return req_lang or "zh-CN"


# ── 安全常量与工具 ──
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
# 上传体积上限（字节）。家庭 LAN 自用，200MB 足够覆盖一段长音频，
# 同时防止任意局域网设备用超大请求把后端内存打爆。
MAX_UPLOAD_BYTES = 200 * 1024 * 1024


def _is_sha256(s: str) -> bool:
    """上传 token 的 sha256 部分必须是 64 位十六进制，杜绝路径穿越。"""
    return bool(_SHA256_RE.match(s or ""))


def _safe_upload_path(sha: str, ext: str) -> str:
    """拼接上传路径并校验其真实路径必须落在 UPLOAD_DIR 内，否则抛 400。"""
    root = os.path.realpath(UPLOAD_DIR)
    path = os.path.realpath(os.path.join(UPLOAD_DIR, f"{sha}{ext}"))
    if os.path.commonpath([root, path]) != root:
        raise HTTPException(status_code=400, detail="invalid upload path")
    return path


# ── 文本类 AI（翻译 / 解析 / 意群）──
@app.post("/api/v2/ai/translate")
async def translate(request: Request):
    data = await request.json()
    text = data.get("text", "")
    lang = _target_lang(data.get("targetLanguage"))
    out = chat_json(TRANSLATE_PROMPT.format(lang=lang_name(lang)), text)
    return {"translation": out.get("translation", "")}


@app.post("/api/v2/ai/analyze")
async def analyze(request: Request):
    data = await request.json()
    text = data.get("text", "")
    lang = _target_lang(data.get("targetLanguage"))
    out = chat_json(ANALYZE_PROMPT.format(lang=lang_name(lang)), text)
    analysis = out.get("analysis", {})
    return {
        "analysis": {
            "grammar": analysis.get("grammar", ""),
            "vocabulary": analysis.get("vocabulary", ""),
            "listening": analysis.get("listening", ""),
        }
    }


@app.post("/api/v2/ai/sense-groups")
async def sense_groups(request: Request):
    data = await request.json()
    text = data.get("text", "")
    out = chat_json(SENSE_GROUP_PROMPT, text)
    medium = out.get("medium", []) or []
    fine = out.get("fine", []) or []
    return {"medium": [str(x) for x in medium], "fine": [str(x) for x in fine]}


# ── 流式文本类 AI（与客户端 /api/v1/stream/* 严格对齐）──
# 复用 dictionary.entry_ndjson_stream 的 ops+done 协议，客户端 accumulateNdjsonObject 直接消费。
# LLM 调用离线程池，避免阻塞事件循环；失败则发 {"__error":...} 帧让客户端抛领域异常。
@app.post("/api/v1/stream/translate")
async def stream_translate(request: Request):
    data = await request.json()
    text = data.get("text", "")
    lang = _target_lang(data.get("targetLanguage"))
    user = text
    ctx = []
    if data.get("previousText"):
        ctx.append(f"前文：{data['previousText']}")
    if data.get("nextText"):
        ctx.append(f"后文：{data['nextText']}")
    if ctx:
        user = "\n".join(ctx) + f"\n\n请翻译下面这句：{text}"
    try:
        out = await asyncio.to_thread(
            chat_json, TRANSLATE_PROMPT.format(lang=lang_name(lang)), user
        )
        result = {"translation": out.get("translation", "")}
    except Exception as e:  # noqa: BLE001
        return StreamingResponse(
            (json.dumps({"__error": str(e)}, ensure_ascii=False) + "\n",),
            media_type="application/x-ndjson",
        )
    return StreamingResponse(
        entry_ndjson_stream(result), media_type="application/x-ndjson"
    )


@app.post("/api/v1/stream/analyze")
async def stream_analyze(request: Request):
    data = await request.json()
    text = data.get("text", "")
    lang = _target_lang(data.get("targetLanguage"))
    try:
        out = await asyncio.to_thread(
            chat_json, ANALYZE_PROMPT.format(lang=lang_name(lang)), text
        )
        a = out.get("analysis", {}) or {}
        result = {
            "grammar": a.get("grammar", []) or [],
            "vocabulary": a.get("vocabulary", []) or [],
            "listening": a.get("listening", []) or [],
        }
    except Exception as e:  # noqa: BLE001
        return StreamingResponse(
            (json.dumps({"__error": str(e)}, ensure_ascii=False) + "\n",),
            media_type="application/x-ndjson",
        )
    return StreamingResponse(
        entry_ndjson_stream(result), media_type="application/x-ndjson"
    )


@app.post("/api/v1/stream/sense-groups")
async def stream_sense_groups(request: Request):
    data = await request.json()
    text = data.get("text", "")
    try:
        out = await asyncio.to_thread(chat_json, SENSE_GROUP_PROMPT, text)
        result = {
            "medium": out.get("medium", []) or [],
            "fine": out.get("fine", []) or [],
        }
    except Exception as e:  # noqa: BLE001
        return StreamingResponse(
            (json.dumps({"__error": str(e)}, ensure_ascii=False) + "\n",),
            media_type="application/x-ndjson",
        )
    return StreamingResponse(
        entry_ndjson_stream(result), media_type="application/x-ndjson"
    )


# ── 词典（流式 NDJSON）──
@app.post("/api/v1/stream/lookup-word")
async def lookup_word(request: Request):
    data = await request.json()
    word = data.get("query", "")
    lang = _target_lang(data.get("targetLanguage"))
    entry = chat_json(WORD_PROMPT.format(lang=lang_name(lang)), word)
    entry["queryType"] = "single_word"
    return StreamingResponse(
        entry_ndjson_stream(entry), media_type="application/x-ndjson"
    )


@app.post("/api/v1/stream/lookup-phrase")
async def lookup_phrase(request: Request):
    data = await request.json()
    phrase = data.get("query", "")
    lang = _target_lang(data.get("targetLanguage"))
    entry = chat_json(PHRASE_PROMPT.format(lang=lang_name(lang)), phrase)
    entry["queryType"] = "multi_word"
    return StreamingResponse(
        entry_ndjson_stream(entry), media_type="application/x-ndjson"
    )


# ── 转录流程（伪 R2）──
@app.post("/api/v2/user-audio/upload-url")
async def upload_url(request: Request):
    data = await request.json()
    sha = data.get("sha256", "")
    if not _is_sha256(sha):
        raise HTTPException(status_code=400, detail="invalid sha256")
    mime = data.get("mimeType", "")
    ext = _ext_from_mime(mime)
    path = _safe_upload_path(sha, ext)
    if os.path.exists(path):
        return {
            "audioExists": True,
            "uploadUrl": None,
            "objectName": sha,
            "publicUrl": None,
        }
    base = str(request.base_url).rstrip("/")
    upload_ep = f"{base}/api/v2/user-audio/raw-upload?token={sha}{ext}"
    return {
        "audioExists": False,
        "uploadUrl": upload_ep,
        "objectName": sha,
        "publicUrl": None,
    }


@app.put("/api/v2/user-audio/raw-upload")
async def raw_upload(request: Request, token: str = ""):
    # token 形如 "<sha256>.ext"；sha256 部分强制 64 位十六进制，ext 仅从 MIME 白名单派生。
    sha = token.split(".")[0] if "." in token else token
    if not _is_sha256(sha):
        raise HTTPException(status_code=400, detail="invalid token")
    ext = _ext_from_mime(request.headers.get("content-type", ""))
    path = _safe_upload_path(sha, ext)
    # 流式写入 + 体积上限：避免一次性读入内存（防内存打爆）。
    total = 0
    tmp = path + ".part"
    try:
        with open(tmp, "wb") as f:
            async for chunk in request.stream():
                total += len(chunk)
                if total > MAX_UPLOAD_BYTES:
                    raise HTTPException(status_code=413, detail="payload too large")
                f.write(chunk)
        os.replace(tmp, path)
    except HTTPException:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise
    return {"ok": True, "objectName": sha, "path": path}


@app.post("/api/v2/user-audio/submit-transcription")
async def submit_transcription(request: Request):
    data = await request.json()
    sha = data.get("sha256", "")
    # 与上传接口一致：sha256 必须是 64 位十六进制。否则空串/非法值会被
    # _find_audio 用作前缀，可能误匹配到上传目录里的任意音频并触发转录。
    if not _is_sha256(sha):
        raise HTTPException(status_code=400, detail="invalid sha256")
    language = data.get("language", "en")
    merge = bool(data.get("mergeSentences", True))
    try:
        job_id = _submit_transcription(sha, language, merge)
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return {"cached": False, "jobId": job_id}


@app.get("/api/v2/user-audio/job-status/{job_id}")
async def job_status(job_id: str):
    job = jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    return {"status": job["status"], "errorMessage": job.get("error")}


@app.get("/api/v2/user-audio/transcript")
async def get_transcript(
    sha256: str,
    language: str = "en",
    mergeSentences: bool = True,
):
    job = jobs.get(sha256)
    if not job or job.get("result") is None:
        return {"sentences": [], "words": [], "fullText": ""}
    return job["result"]


@app.get("/")
async def index():
    return {"service": "echoloop-ai-backend", "status": "ok"}


# ── 客户端自检更新（LAN-only 广播）──
# 版本清单与 APK 均托管在 UPDATES_DIR，仅家庭 LAN 可访问（端口 8000 不暴露公网）。
# 客户端启动时拉取 {apiBaseUrl}/version.json（即本路由），比对版本号决定是否提示更新。
@app.post("/api/v1/homeschooling/package")
async def receive_homeschooling_package(request: Request):
    data = await request.json()
    if not isinstance(data, dict):
        raise HTTPException(status_code=400, detail="invalid package")
    timestamp = _utc_now()
    package_id = str(uuid.uuid4())[:8]
    filename = f"{timestamp}_{package_id}.json"
    path = os.path.join(HOMESCHOOLING_PACKAGES_DIR, filename)
    tmp = path + ".part"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)
    latest_path = os.path.join(HOMESCHOOLING_PACKAGES_DIR, "latest.json")
    with open(latest_path + ".part", "w", encoding="utf-8") as f:
        json.dump(
            {"package": data, "stored_at": timestamp, "filename": filename},
            f,
            ensure_ascii=False,
            indent=2,
        )
    os.replace(latest_path + ".part", latest_path)
    return {"ok": True, "filename": filename}


@app.get("/api/v1/homeschooling/package/latest")
async def get_latest_homeschooling_package():
    latest_path = os.path.join(HOMESCHOOLING_PACKAGES_DIR, "latest.json")
    if not os.path.exists(latest_path):
        raise HTTPException(status_code=404, detail="no package")
    with open(latest_path, "r", encoding="utf-8") as f:
        return JSONResponse(json.load(f))


@app.get("/version.json")
async def version_manifest():
    path = os.path.join(UPDATES_DIR, "version.json")
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="version manifest not found")
    with open(path, "r", encoding="utf-8") as f:
        return JSONResponse(json.load(f))


# 静态托管各版本 APK：{apiBaseUrl}/updates/<filename>
# StaticFiles 已限制只能访问 UPDATES_DIR 内文件，杜绝路径穿越。
app.mount("/updates", StaticFiles(directory=UPDATES_DIR), name="updates")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=HOST, port=PORT)
