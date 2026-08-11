"""转录引擎 + 任务管理。

默认引擎 openai：调用 OpenAI 兼容 Whisper API；本项目生产使用 Groq 兼容端点（verbose_json + 词级时间戳）。
转录模型名由 config.TRANSCRIBE_MODEL 控制；本项目生产用 whisper-large-v3，OpenAI 官方直连可改回 whisper-1。
注意：本地 faster-whisper 依赖 CTranslate2，需 CPU 支持 AVX2；J4125 这类低功耗机器
无 AVX2，本地引擎不可用，故默认走云端兼容端点。
"""
import json
import os
import threading
import time

from config import (
    OPENAI_API_KEY,
    OPENAI_BASE_URL,
    TRANSCRIBE_ENGINE,
    TRANSCRIBE_MODEL,
    UPLOAD_DIR,
)
from openai import OpenAI

# job_id -> {"status": queued|running|succeeded|failed, "result": {...}, "error": str|None}
jobs: dict[str, dict] = {}

# 合并短句的阈值（秒）：小于该时长的相邻 segment 合并到上一句
_MERGE_THRESHOLD = 1.2


def _normalize_lang(bcp47: str | None) -> str | None:
    if not bcp47:
        return None
    return bcp47.lower()[:2]


def _build_result(raw: dict, merge: bool) -> dict:
    segments = raw.get("segments") or []
    words = raw.get("words") or []

    # 1) 合并短句（可选）
    if merge:
        merged = []
        for seg in segments:
            s, e = seg["start"], seg["end"]
            if merged and (e - s) < _MERGE_THRESHOLD:
                prev = merged[-1]
                prev["text"] = (prev["text"] + " " + seg["text"]).strip()
                prev["end"] = e
            else:
                merged.append({"text": seg["text"].strip(), "start": s, "end": e})
    else:
        merged = [{"text": s["text"].strip(), "start": s["start"], "end": s["end"]} for s in segments]

    # 2) 词按时间归属到合并后的句子，跨句累积到全局 all_words，并计算每句在
    #    all_words 中的起止索引（供字幕单词高亮 / 词级时间轴对齐使用）。
    sentences = []
    all_words = []
    for m in merged:
        seg_words = [w for w in words if m["start"] <= w["start"] <= m["end"]]
        start_idx = len(all_words)
        for w in seg_words:
            all_words.append(
                {
                    "word": w["word"],
                    "startTime": float(w["start"]),
                    "endTime": float(w["end"]),
                    "confidence": float(w.get("confidence", 1.0)),
                }
            )
        end_idx = len(all_words) - 1
        sentences.append(
            {
                "text": m["text"],
                "startTime": float(m["start"]),
                "endTime": float(m["end"]),
                "startWordIndex": start_idx if seg_words else None,
                "endWordIndex": end_idx if seg_words else None,
            }
        )

    full_text = raw.get("text", "")
    return {"sentences": sentences, "words": all_words, "fullText": full_text}


def transcribe_file(path: str, language: str, job_id: str, merge: bool = True):
    jobs[job_id] = {"status": "running", "result": None, "error": None}
    try:
        if TRANSCRIBE_ENGINE == "local":
            raise NotImplementedError(
                "local 引擎未内置，请在 transcribe.py 接入 faster-whisper，"
                "或把 TRANSCRIBE_ENGINE 设为 openai 并配置 OPENAI_API_KEY。"
            )
        if not OPENAI_API_KEY:
            raise RuntimeError("未配置 OPENAI_API_KEY，无法使用 openai 转录引擎。")

        client = OpenAI(base_url=OPENAI_BASE_URL, api_key=OPENAI_API_KEY)
        lang = _normalize_lang(language)
        # 优先请求词级+句级时间戳；若 provider 不支持词级（如部分兼容端点），退化到仅句级
        try:
            with open(path, "rb") as f:
                resp = client.audio.transcriptions.create(
                    model=TRANSCRIBE_MODEL,
                    file=f,
                    language=lang,
                    response_format="verbose_json",
                    timestamp_granularities=["segment", "word"],
                )
        except Exception:
            with open(path, "rb") as f:
                resp = client.audio.transcriptions.create(
                    model=TRANSCRIBE_MODEL,
                    file=f,
                    language=lang,
                    response_format="verbose_json",
                    timestamp_granularities=["segment"],
                )
        raw = json.loads(resp.model_dump_json())
        result = _build_result(raw, merge)
        jobs[job_id] = {"status": "succeeded", "result": result, "error": None}
    except Exception as e:  # noqa: BLE001
        jobs[job_id] = {"status": "failed", "result": None, "error": str(e)}


def submit_transcription(sha256: str, language: str, merge: bool) -> str:
    """根据 sha256 找到本地音频文件，启动后台转录，返回 job_id。"""
    path = _find_audio(sha256)
    if not path:
        raise FileNotFoundError(f"未找到 sha256={sha256} 的已上传音频")
    # 直接用 sha256 作为 jobId，使 job-status/{jobId} 与 transcript?sha256= 统一可查。
    job_id = sha256
    jobs[job_id] = {"status": "queued", "result": None, "error": None}
    t = threading.Thread(
        target=transcribe_file, args=(path, language, job_id, merge), daemon=True
    )
    t.start()
    return job_id


def _find_audio(sha256: str) -> str | None:
    # 精确匹配：文件名去扩展名后须与 sha256 完全相等（上传时按 "<sha>.<ext>" 命名）。
    # 用 startswith 会让空串/短前缀误匹配到目录内任意音频，故改为精确比较。
    if not sha256:
        return None
    for name in os.listdir(UPLOAD_DIR):
        if os.path.splitext(name)[0] == sha256:
            return os.path.join(UPLOAD_DIR, name)
    return None
