"""词典流式协议：把 LLM 返回的结构化条目转为 Echo Loop 客户端期望的 NDJSON 流。

客户端（lib/services/sentence_ai_api_client.dart 的 _streamDictionaryFrames）按行读取
NDJSON，逐帧把 ops 按路径累积到 acc，遇到 {"done": true} 时调用 AiDictionaryEntry.fromJson(acc)。
我们只需把整条 entry 的每个顶层字段拆成一个 op，再补一个 done 帧即可。
"""
import json


def entry_to_ops(entry: dict) -> list[dict]:
    """把 entry 的每个顶层键拆成单个 path 写入操作。"""
    return [{"p": [key], "v": value} for key, value in entry.items()]


def entry_ndjson_stream(entry: dict):
    """生成 NDJSON 字节/字符串流。

    帧1：所有顶层字段的 ops（客户端据此填充 acc）
    帧2：{"done": true}（客户端据此判定完成并 fromJson）
    """
    ops = entry_to_ops(entry)
    yield json.dumps({"ops": ops}, ensure_ascii=False) + "\n"
    yield json.dumps({"done": True}, ensure_ascii=False) + "\n"
