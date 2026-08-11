"""Echo Loop 自建 AI 后端 —— 配置。

所有配置均可通过环境变量或 .env 文件覆盖。
自用场景最关键的三个变量：LLM_API_KEY、LLM_BASE_URL、LLM_MODEL。
"""
import os

from dotenv import load_dotenv

load_dotenv()

# ── LLM（翻译 / 解析 / 意群 / 词典）──
# 默认用 DeepSeek（国内直连、便宜）。也可换通义、智谱、OpenAI 等 OpenAI 兼容端点。
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "https://api.deepseek.com/v1")
LLM_API_KEY = os.getenv("LLM_API_KEY", "")
LLM_MODEL = os.getenv("LLM_MODEL", "deepseek-chat")

# LLM 请求超时（秒）与自动重试次数。
# 无显式超时时，个别请求（如意群 fine 粒度）遇到连接停滞会一直挂起，
# 拖垮流式接口并让客户端长时间等待。设定明确超时 + 少量重试：
# 单次停滞会在 LLM_TIMEOUT 秒后中断并自动重试，正常调用不受影响。
LLM_TIMEOUT = float(os.getenv("LLM_TIMEOUT", "30"))
LLM_MAX_RETRIES = int(os.getenv("LLM_MAX_RETRIES", "2"))

# 关闭「思考型」模型的推理模式（默认开启关闭）。
# sensenova-6.7-flash-lite 等 reasoning 模型会把大段思考写进 reasoning 字段，
# 对意群切分这类任务思考尤其冗长，会耗尽输出 token 预算导致正式 content 为空、
# 请求长时间挂起甚至超时。关闭思考后直接产出 JSON（意群实测 60s+ → <1s）。
# 若换用不支持该参数的 provider（如 OpenAI/DeepSeek），设为 false 以免报错。
LLM_DISABLE_THINKING = os.getenv("LLM_DISABLE_THINKING", "true").lower() in ("1", "true", "yes")

# 默认翻译/解析目标语言（BCP 47）。客户端也会传 targetLanguage，以客户端为准。
TARGET_LANGUAGE = os.getenv("TARGET_LANGUAGE", "zh-CN")

# ── 转录引擎 ──
# openai  : 调用 OpenAI Whisper API（需 OPENAI_API_KEY），质量好、省心。
# local   : 本地 faster-whisper（免费，但需额外安装依赖 + 下载模型，j4125 较慢）。
TRANSCRIBE_ENGINE = os.getenv("TRANSCRIBE_ENGINE", "openai")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")
# 转录模型名（默认 OpenAI whisper-1；换 Groq 等兼容端点时设为 whisper-large-v3 等）
TRANSCRIBE_MODEL = os.getenv("TRANSCRIBE_MODEL", "whisper-1")

# ── 服务 ──
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "8000"))

# 上传音频与转录结果的本地存储目录
UPLOAD_DIR = os.getenv("UPLOAD_DIR", "./uploads")

# 客户端自检更新托管目录（version.json + 各版本 APK）
# 仅家庭 LAN 可访问；端口 8000 不暴露公网。
UPDATES_DIR = os.getenv("UPDATES_DIR", "./updates")

# HomeSchooling 直传包存储目录
HOMESCHOOLING_PACKAGES_DIR = os.getenv(
    "HOMESCHOOLING_PACKAGES_DIR",
    "./homeschooling_packages",
)
