#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Echo Loop 后端「无 Key 自检」。

部署后端、装好依赖后运行：
    python self_test.py

特点：
- 用 FastAPI TestClient 真实走完全部接口；
- LLM / Whisper 均被本地 stub 替换，不消耗任何 API Key；
- 验证 15 项（含词典/聊天 NDJSON 流式协议、转录全流程）。

全部 PASS 说明后端代码与接口契约正确；之后再填真实 .env Key 即可投入使用。
"""
import os
import sys
import json
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# 在 import main 前把所有运行时目录隔离到临时目录，避免自检污染部署目录。
TEST_ROOT = tempfile.mkdtemp(prefix="echoloop_test_")
os.environ["UPLOAD_DIR"] = os.path.join(TEST_ROOT, "uploads")
os.environ["UPDATES_DIR"] = os.path.join(TEST_ROOT, "updates")
os.environ["HOMESCHOOLING_PACKAGES_DIR"] = os.path.join(
    TEST_ROOT,
    "homeschooling_packages",
)

import main
import transcribe
import chat.routes as chat_routes
from fastapi.testclient import TestClient

UPLOAD_DIR = os.environ["UPLOAD_DIR"]


# ── stub LLM（按 system 提示词判断返回结构）──
def fake_chat_json(system, user, temperature=0.3):
    if "意群" in system:
        return {"medium": ["Hello there", "my friend"], "fine": ["Hello", "there", "my friend"]}
    if "解析" in system:
        return {"analysis": {"grammar": "一般现在时", "vocabulary": "friend 名词", "listening": "连读"}}
    if "翻译" in system:
        return {"translation": "你好，我的朋友"}
    if "多词" in system:
        return {
            "originalExpression": "give up", "naturalness": "", "category": "phrasal verb",
            "pronunciationTips": ["连读 gɪvʌp"],
            "keyPoints": [{"point": "表示放弃", "sentence": "He gave up.", "translation": "他放弃了。"}],
            "meanings": [{"translation": ["放弃"], "examples": [{"sentence": "give up smoking", "translation": "戒烟"}]}],
            "similarExpressions": [], "background": "",
        }
    if "单词" in system:
        return {
            "headword": "run", "pronunciation": {"uk": "/rʌn/", "us": "/rʌn/"},
            "meanings": [{"partOfSpeech": "v.", "translation": ["跑"], "definition": "to move fast",
                          "usageNote": "", "examples": [{"sentence": "He runs.", "translation": "他跑。"}],
                          "synonyms": ["sprint"], "antonyms": ["walk"]}],
            "commonExpressions": [], "wordFamily": [],
            "forms": [{"form": "ran", "label": "过去式"}], "etymology": "", "learnerTips": ["注意过去式"],
        }
    return {}


main.chat_json = fake_chat_json


# ── stub 句子聊天 ──
chat_calls = []


def fake_chat_reply(system, history, temperature=0.3):
    chat_calls.append({"system": system, "history": history})
    return {"reply": "这里的 has been working 是现在完成进行时。"}


chat_routes.chat_reply = fake_chat_reply


# ── stub 转录 ──
def fake_transcribe_file(path, language, job_id, merge=True):
    transcribe.jobs[job_id] = {
        "status": "succeeded",
        "result": {
            "sentences": [{"text": "Hello world.", "startTime": 0.0, "endTime": 1.5,
                           "startWordIndex": 0, "endWordIndex": 1}],
            "words": [{"word": "Hello", "startTime": 0.0, "endTime": 0.7, "confidence": 0.99},
                      {"word": "world", "startTime": 0.8, "endTime": 1.5, "confidence": 0.98}],
            "fullText": "Hello world.",
        },
        "error": None,
    }


transcribe.transcribe_file = fake_transcribe_file
transcribe.UPLOAD_DIR = UPLOAD_DIR
main.UPLOAD_DIR = UPLOAD_DIR

client = TestClient(main.app)
fails = []


def check(name, cond):
    print(("PASS" if cond else "FAIL"), name)
    if not cond:
        fails.append(name)


# 1. 健康检查
r = client.get("/")
check("GET /", r.status_code == 200 and r.json().get("status") == "ok")

# 2. 翻译
r = client.post("/api/v2/ai/translate", json={"text": "Hello there my friend", "targetLanguage": "zh-CN"})
check("translate", r.status_code == 200 and r.json().get("translation") == "你好，我的朋友")

# 3. 解析
r = client.post("/api/v2/ai/analyze", json={"text": "Hello there my friend"})
a = r.json().get("analysis", {})
check("analyze", r.status_code == 200 and a.get("grammar") == "一般现在时" and a.get("listening") == "连读")

# 4. 意群
r = client.post("/api/v2/ai/sense-groups", json={"text": "Hello there my friend"})
sg = r.json()
check("sense-groups", r.status_code == 200 and len(sg.get("medium", [])) == 2 and len(sg.get("fine", [])) == 3)

# 5. 词典（单词）流式 + 模拟客户端累积
r = client.post("/api/v1/stream/lookup-word", json={"query": "run", "targetLanguage": "zh-CN"})
lines = [l for l in r.text.split("\n") if l.strip()]
acc = {}
saw_done = False
for ev in lines:
    obj = json.loads(ev)
    if "ops" in obj:
        for op in obj["ops"]:
            acc[op["p"][0]] = op["v"]
    if obj.get("done"):
        saw_done = True
        break
check("lookup-word stream frames", len(lines) == 2 and saw_done)
check("lookup-word entry", acc.get("queryType") == "single_word" and acc.get("headword") == "run"
      and acc["meanings"][0]["partOfSpeech"] == "v." and acc["forms"][0]["form"] == "ran")

# 6. 词典（短语）流式
r = client.post("/api/v1/stream/lookup-phrase", json={"query": "give up"})
lines = [l for l in r.text.split("\n") if l.strip()]
acc = {}
for ev in lines:
    obj = json.loads(ev)
    if "ops" in obj:
        for op in obj["ops"]:
            acc[op["p"][0]] = op["v"]
    if obj.get("done"):
        break
check("lookup-phrase entry", acc.get("queryType") == "multi_word" and acc.get("originalExpression") == "give up"
      and acc["keyPoints"][0]["point"] == "表示放弃")

# 7. 句子聊天（客户端 messages/context/targetLanguage + delta/done）
chat_payload = {
    "messages": [
        {"role": "user", "content": "这里为什么用 has been working？"},
        {"role": "assistant", "content": "你想重点了解时态还是语气？"},
        {"role": "user", "content": "重点讲时态。"},
    ],
    "context": {"sentence": "She has been working here since 2019."},
    "targetLanguage": "zh-CN",
}
r = client.post("/api/v1/stream/chat/sentence", json=chat_payload)
chat_lines = [json.loads(line) for line in r.text.splitlines() if line.strip()]
check(
    "sentence-chat stream",
    r.status_code == 200
    and chat_lines == [
        {"delta": "这里的 has been working 是现在完成进行时。"},
        {"done": True},
    ],
)
call = chat_calls[-1] if chat_calls else {}
check(
    "sentence-chat request contract",
    call.get("history") == chat_payload["messages"]
    and "She has been working here since 2019." in call.get("system", "")
    and "中文" in call.get("system", ""),
)
r = client.post(
    "/api/v1/stream/chat/sentence",
    json={
        "history": chat_payload["messages"],
        "question": "旧协议不应再被接受",
        "context": chat_payload["context"],
    },
)
check("sentence-chat rejects legacy shape", r.status_code == 400)

# 8-12. 转录流程
sha = "a" * 64
r = client.post(
    "/api/v2/user-audio/upload-url",
    json={"sha256": sha, "mimeType": "audio/mpeg", "fileSize": 1000},
)
ju = r.json()
check(
    "upload-url (new)",
    ju.get("audioExists") is False
    and ju.get("uploadUrl", "").endswith(f"{sha}.mp3"),
)

r = client.put(ju["uploadUrl"], content=b"FAKEAUDIO", headers={"Content-Type": "audio/mpeg"})
check("raw-upload PUT", r.status_code == 200 and r.json().get("ok") is True)

r = client.post(
    "/api/v2/user-audio/submit-transcription",
    json={"sha256": sha, "language": "en", "mergeSentences": True},
)
job_id = r.json().get("jobId")
check("submit-transcription", r.status_code == 200 and job_id == sha)

r = client.get(f"/api/v2/user-audio/job-status/{job_id}")
check("job-status succeeded", r.json().get("status") == "succeeded")

r = client.get(
    "/api/v2/user-audio/transcript",
    params={"sha256": sha, "language": "en"},
)
tr = r.json()
check("transcript result", tr["sentences"][0]["text"] == "Hello world." and tr["words"][1]["word"] == "world")

print("\n==== RESULT:", "ALL PASS" if not fails else f"FAILURES={fails}")
shutil.rmtree(TEST_ROOT, ignore_errors=True)
sys.exit(1 if fails else 0)
