#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""客户端 ↔ 后端契约测试（端到端）。

self_test.py 只测后端自己的 v2 接口，证明不了 App 可用。本测试直接按
sentence_ai_api_client.dart 的契约打三个 /api/v1/stream/* 流式端点，并解析
NDJSON（ops+done），断言最终结构与客户端模型一致：
  - translate    → 顶层 translation (str)
  - analyze      → 顶层 grammar/vocabulary/listening 均为「对象数组」（非字符串！）
  - sense-groups → 顶层 medium/fine 均为字符串数组
  - chat/sentence → messages/context/targetLanguage 请求，delta+done 响应
另测上传路径穿越拦截（token=../../escape 必须 400）。

用法（在部署机上、后端已运行时）：
    python contract_test.py [BASE_URL]      # 默认 http://127.0.0.1:8000
退出码 0=全部通过，1=有失败。
仅用标准库（urllib），无需额外依赖。
"""
import json
import sys
import urllib.error
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"


def _stream_ndjson(path, payload):
    """POST 并逐行解析 NDJSON，yield 每个事件 dict。"""
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        BASE + path,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=90) as resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line:
                continue
            yield json.loads(line)


def _accumulate(path, payload):
    """模拟客户端 accumulateNdjsonObject：应用 ops 到 acc，遇 done 返回完整对象。"""
    acc = {}
    for ev in _stream_ndjson(path, payload):
        if ev.get("__error"):
            raise AssertionError(f"{path} 返回错误帧: {ev}")
        for op in ev.get("ops", []) or []:
            p = op.get("p")
            v = op.get("v")
            if not isinstance(p, list):
                continue
            d = acc
            for seg in p[:-1]:
                d = d.setdefault(seg, {})
            d[p[-1]] = v
    return acc


def _accumulate_chat(path, payload):
    """模拟 ChatApiClient：累加 delta，且必须收到 done 终帧。"""
    parts = []
    saw_done = False
    for ev in _stream_ndjson(path, payload):
        if ev.get("__error"):
            raise AssertionError(f"{path} 返回错误帧: {ev}")
        if isinstance(ev.get("delta"), str):
            parts.append(ev["delta"])
        if ev.get("done") is True:
            saw_done = True
            break
    if not saw_done:
        raise AssertionError(f"{path} 流结束但没有 done 终帧")
    return "".join(parts)


def _check(name, cond, detail=""):
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {name}  {detail}")
    return cond


def _put_raw(token, body=b"x", mime="audio/mpeg"):
    req = urllib.request.Request(
        BASE + f"/api/v2/user-audio/raw-upload?token={token}",
        data=body,
        headers={"Content-Type": mime},
        method="PUT",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        return e.code


def main():
    ok = True

    # 1) translate
    try:
        r = _accumulate(
            "/api/v1/stream/translate",
            {"text": "Hello world", "targetLanguage": "zh-CN"},
        )
        ok &= _check(
            "translate",
            isinstance(r.get("translation"), str) and bool(r.get("translation")),
            f"translation={r.get('translation')!r}",
        )
    except Exception as e:  # noqa: BLE001
        ok &= _check("translate", False, f"异常: {e}")

    # 2) analyze —— 关键：必须是「对象数组」，字符串会被客户端 _mapList 丢弃成空
    try:
        r = _accumulate(
            "/api/v1/stream/analyze",
            {"text": "She has been working here since 2019.", "targetLanguage": "zh-CN"},
        )
        g = r.get("grammar") or []
        v = r.get("vocabulary") or []
        l = r.get("listening") or []
        shape_ok = (
            isinstance(g, list) and isinstance(v, list) and isinstance(l, list)
            and all(isinstance(x, dict) for x in g + v + l)
        )
        ok &= _check(
            "analyze",
            shape_ok and (len(g) + len(v) + len(l)) > 0,
            f"grammar={len(g)} vocabulary={len(v)} listening={len(l)} (须为对象数组且非空)",
        )
    except Exception as e:  # noqa: BLE001
        ok &= _check("analyze", False, f"异常: {e}")

    # 3) sense-groups
    try:
        r = _accumulate(
            "/api/v1/stream/sense-groups",
            {"text": "The quick brown fox jumps over the lazy dog"},
        )
        m = r.get("medium") or []
        f = r.get("fine") or []
        ok &= _check(
            "sense-groups",
            isinstance(m, list) and isinstance(f, list) and len(m) > 0,
            f"medium={len(m)} fine={len(f)}",
        )
    except Exception as e:  # noqa: BLE001
        ok &= _check("sense-groups", False, f"异常: {e}")

    # 4) 句子级聊天 —— 必须使用客户端当前 messages/context/targetLanguage 契约
    try:
        answer = _accumulate_chat(
            "/api/v1/stream/chat/sentence",
            {
                "messages": [
                    {
                        "role": "user",
                        "content": "Why is the present perfect continuous used here?",
                    }
                ],
                "context": {
                    "sentence": "She has been working here since 2019.",
                },
                "targetLanguage": "zh-CN",
            },
        )
        ok &= _check(
            "sentence-chat",
            bool(answer.strip()),
            f"answer_chars={len(answer)}",
        )
    except Exception as e:  # noqa: BLE001
        ok &= _check("sentence-chat", False, f"异常: {e}")

    # 5) 路径穿越拦截
    code = _put_raw("../../escape")
    ok &= _check(
        "path-traversal-blocked",
        code == 400,
        f"PUT raw-upload?token=../../escape → HTTP {code} (期望 400)",
    )

    print()
    print("CONTRACT_TEST", "ALL PASS" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
