# Echo Loop 自建 AI 后端

复刻 [Echo Loop](https://github.com/echo-loop/Echo-Loop) 官方未开源的 AI 后端，
用于在**本地/家庭局域网**运行，配合「去锁」后的 Echo Loop App，让孩子**免订阅**使用
全部 AI 功能（翻译 / 解析 / 意群 / 词典 / 转录字幕）。

> 适用场景：个人自用，不对外分发、不上架。AGPL-3.0 下个人自用无需公开源码。

---

## 1. 接口范围

| 端点 | 功能 |
|------|------|
| `POST /api/v2/ai/translate` | 句子翻译 |
| `POST /api/v2/ai/analyze` | 句子解析（语法/词汇/听力） |
| `POST /api/v2/ai/sense-groups` | 意群切分 |
| `POST /api/v1/stream/lookup-word` | 单词词典（NDJSON 流式） |
| `POST /api/v1/stream/lookup-phrase` | 短语词典（NDJSON 流式） |
| `POST /api/v1/stream/chat/sentence` | 当前句多轮辅导（NDJSON 流式） |
| `POST /api/v2/user-audio/upload-url` | 转录：获取上传地址 |
| `PUT  /api/v2/user-audio/raw-upload` | 转录：上传音频（伪 R2） |
| `POST /api/v2/user-audio/submit-transcription` | 转录：提交任务 |
| `GET  /api/v2/user-audio/job-status/{job_id}` | 转录：轮询状态 |
| `GET  /api/v2/user-audio/transcript` | 转录：获取结果 |

所有接口**忽略 Authorization**（自用后端不鉴权）。

---

## 2. 安装与运行

```bash
# ① 准备 Python 虚拟环境（推荐）
python3 -m venv .venv
source .venv/bin/activate

# ② 安装依赖
pip install -r requirements.txt

# ③ 配置（复制模板后填入你的 LLM / 转录 Key）
cp .env.example .env
#   编辑 .env：至少填 LLM_API_KEY（翻译/解析/意群/词典必需）
#   转录若要 AI 字幕，还需 OPENAI_API_KEY

# ④ 启动（调试）
python main.py
#   或生产常驻：
uvicorn main:app --host 0.0.0.0 --port 8000
```

启动后访问 `http://<本机IP>:8000/` 看到 `{"status":"ok"}` 即成功。

---

## 3. 作为系统服务常驻（推荐，7×24）

把后端注册成 systemd 服务，开机自启、崩溃自愈：

```ini
# /etc/systemd/system/echoloop-ai.service
[Unit]
Description=Echo Loop AI Backend
After=network.target

[Service]
WorkingDirectory=/opt/echoloop-ai-backend
ExecStart=/opt/echoloop-ai-backend/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
User=youruser

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now echoloop-ai
```

---

## 4. 转录引擎说明

- **openai（默认）**：调用 OpenAI Whisper API，返回句子级 + 词级时间戳，
  质量好、实现简单。按音频时长计费，几分钟的音频几分钱。
- **local**：本地 `faster-whisper` 推理，完全免费，但需在 `transcribe.py` 接入
  并下载模型；j4125 这类低功耗 CPU 上一段 5 分钟音频可能要数分钟。

若暂不配置 `OPENAI_API_KEY`，转录功能不可用，但翻译/解析/意群/词典均正常。

---

## 5. 对接 App

App 端通过 `API_BASE_URL` 指向本服务：

```
flutter build apk --dart-define=API_BASE_URL=http://<工控机局域网IP>:8000
```

详见随附的《部署手册》。
