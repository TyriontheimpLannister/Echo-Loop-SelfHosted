# Echo Loop 自用「全功能」部署 — Agent 执行简报

> 本文件给你（执行 agent）看。任务目标、文件清单、每一步命令都已就绪，照做即可。
> 不要自作主张猜 IP / API Key；缺信息就**先问用户**。

---

## 0. 任务目标

帮用户部署一套「给孩子用的 Echo Loop 英语听说 App · 全功能版」：

- 在孩子的一台 **Android 学习机** 上，用上 Echo Loop **全部功能**（含官方要订阅的
  AI 翻译 / 解析 / 意群切分 / 词典 / 转录字幕），**免订阅、免登录**。
- 在用户家里一台 **7×24 的 Ubuntu 工控机（j4125）** 上，常驻一个**自建 AI 后端**。
- 数据留在用户自家局域网，不经过官方服务器；个人自用，不分发、不上架。

**为什么能免费**：Echo Loop 是 AGPL-3.0 开源。官方源码免费，只是其 AI 后端未开源且高级功能要订阅。
本包给你补了两块：① 一个**自建 AI 后端**（代码已写好、已测试通过）；② 一个**客户端去锁补丁**
（让 fork 后的 App 不登录/不订阅也能用全部 AI，并把请求指向你自己的后端）。

---

## 1. 这个包里有什么

```
echoloop-deploy-kit/
├── AGENT.md                  ← 本文件（你首先读这个）
├── README.md                 ← 给用户的交付说明（可选读）
├── backend/                 ← AI 后端，部署到工控机
│   ├── main.py              # FastAPI 主程序（10 个接口）
│   ├── llm.py              # LLM 调用（OpenAI 兼容，默认 Sensenova）
│   ├── prompts.py          # 各功能提示词（字段严格对齐客户端）
│   ├── dictionary.py       # 词典 NDJSON 流式协议
│   ├── transcribe.py       # 转录引擎（openai / local 可切换）
│   ├── config.py           # 配置
│   ├── requirements.txt
│   ├── .env.example
│   ├── README.md           # 后端运行说明
│   └── self_test.py       # 后端「无 Key 自检」（部署后必跑）
├── client-patch/
│   └── apply_unlock.py    # 客户端去锁补丁（在官方 Echo-Loop 仓库根目录运行）
└── docs/
    └── 部署手册.md          ← 人读详细手册（备查）
```

---

## 2. 执行前：先向用户确认这些（缺一不可，不要猜）

1. **工控机的局域网 IP**（如 `192.168.1.50`）？你（agent）能否从当前机器 `ssh` 上去？
2. **Sensenova API Key**（翻译/解析/意群/词典必需，极便宜）。
3. 是否需要 **AI 转录字幕**？需要则还要 **OpenAI API Key**（按音频时长计费）。
4. **编译 APK 的机器在哪**？你（agent）所在机器是否已装 **Flutter 3.9.2+ 和 Android SDK**？
   （没有则告诉用户在哪台装，或你帮装。）
5. **学习机是 Android**？能否开启「未知来源安装」？

> 缺任何一项，先停下来问用户。IP 和 Key 必须由用户提供，你无法替他注册。

---

## 3. 执行步骤

### A. 部署 AI 后端（到工控机，或你能 ssh 的机器）

> 平台差异：Linux 用 `sudo apt`；macOS 用 `brew`；Windows 手动装 Python 3.11+。
> venv 激活：Linux/macOS `source .venv/bin/activate`；Windows `.venv\Scripts\activate`。

```bash
# 1. 把本包的 backend/ 整个目录传到工控机，放到 /opt/echoloop-ai-backend
#    （scp / U 盘 / 网盘均可）

# 2. 进工控机，准备 Python 虚拟环境
sudo apt update && sudo apt install -y python3-venv python3-pip   # Linux
cd /opt/echoloop-ai-backend
python3 -m venv .venv
source .venv/bin/activate

# 3. 装依赖
pip install -r requirements.txt

# 4. 配置密钥
cp .env.example .env
#   编辑 .env：至少填 LLM_API_KEY=sk-你的Sensenova或Groq兼容端点Key
#   需要转录则填 OPENAI_API_KEY=sk-你的openai-key

# 5. 无 Key 自检（务必跑，验证接口契约正确）
python self_test.py
#   → 应看到 12 项全部 PASS

# 6. 前台测试启动
python main.py
#   另开终端：curl http://localhost:8000/  → {"status":"ok"}
#   Ctrl+C 退出

# 7. 设为开机自启（推荐，7×24）
#   按 backend/README.md 里的 systemd 片段写 /etc/systemd/system/echoloop-ai.service
sudo systemctl daemon-reload && sudo systemctl enable --now echoloop-ai
sudo ufw allow 8000          # 放行端口，让学习机访问
```

### B. 编译「去锁版」App（在装了 Flutter 的机器上）

```bash
# 1. 环境（已具备可跳过）：Flutter 3.9.2+、Java 17、Android SDK
#    （cmdline-tools + build-tools;34.0.0 + platforms;android-34），并 flutter doctor --android-licenses

# 2. 拉官方仓库
git clone https://github.com/echo-loop/Echo-Loop.git
cd Echo-Loop

# 3. 把本包的 client-patch/apply_unlock.py 放到仓库根目录，运行去锁补丁
cp /path/to/echoloop-deploy-kit/client-patch/apply_unlock.py ./
python apply_unlock.py
#   → 自动改 4 个文件（付费墙/伪登录/AI鉴权/Android明文），幂等可重复跑

# 4. 配置编译变量
cp .dev.env.template .dev.env
#   编辑 .dev.env，关键两行：
#     SUPABASE_URL=                        ← 留空（App 会跳过登录，零崩溃风险）
#     SUPABASE_PUBLISHABLE_KEY=             ← 留空
#     API_BASE_URL=http://192.168.1.50:8000   ← 改成工控机真实局域网 IP
#     REVENUECAT_*=                        ← 全部留空
#   （其余 GOOGLE_WEB_CLIENT_ID 等也留空即可）

# 5. 编译 APK
flutter pub get
dart run build_runner build
flutter build apk --dart-define-from-file=.dev.env
#   产物：build/app/outputs/flutter-apk/app-release.apk
```

### C. 安装到学习机 + 联调

任选一种把 `app-release.apk` 送到学习机：

- **U 盘/网盘**：拷过去，文件管理器点开安装（需开「未知来源」）。
- **ADB**：学习机开 USB 调试，`adb install app-release.apk`。
- **局域网**：工控机上 `cd build/app/outputs/flutter-apk && python3 -m http.server 8080`，
  学习机浏览器开 `http://工控机IP:8080/app-release.apk` 下载安装。

联调：学习机与工控机在**同一 WiFi**；打开 App → 导入一段英语音频（或点任意句子「翻译」），
请求会发到 `http://工控机IP:8000`，后端调 LLM 返回结果。**全部 AI 功能应免登录、无订阅提示直接可用。**

> 固定地址：若工控机 IP 是 DHCP 分配可能变化，二选一：① 路由器把工控机 MAC 绑固定 IP；
> ② 用内网穿透（frp / Cloudflare tunnel）给后端一个固定域名。

---

## 4. 关键坑（已为你规避，但要知道）

- **Supabase 留空即可**：`isAuthConfigured` 在 URL/Key 为空时为 false，App 跳过 `Supabase.initialize`，
  零崩溃风险。**不要填假值**。
- **Android 明文 HTTP**：学习机访问局域网 `http://` 后端需要 `usesCleartextTraffic="true"`，
  已由 `apply_unlock.py` 自动加进 AndroidManifest，**重编 APK 后生效**。
- **API_BASE_URL 必须指向工控机可达的地址**（同局域网 IP，或穿透域名）。
- **apply_unlock.py 幂等**：重复运行安全，已改的文件会显示「已应用」跳过。
- **后端端口 8000 需放行**：工控机 `sudo ufw allow 8000`。

---

## 5. 完成后

- 告诉用户：App 已装到学习机、后端在工控机常驻、孩子打开即可用全部功能。
- 提醒成本：Sensenova 做 LLM、Groq 做转录；按实际供应商口径估算成本
  工控机电费约 ¥1–2/月。
- 合规提醒：仅个人自用、不分发、不上架，AGPL-3.0 无额外义务；若日后要分享他人或上架，
  需按 AGPL 开源你的衍生代码（协议传染性）。

---

## 6. 你的边界（做不到的，明确告诉用户）

- 你**无法替用户注册** Sensenova / Groq 的 API Key → 向用户要。
- 编译 APK **需要 Flutter + Android SDK 环境** → 若你所在机器没有，告知用户在哪台装，或你帮装。
- **只改 `apply_unlock.py` 指定的 4 处**，不要改动官方仓库其它代码；不要改动 `backend/` 已验证的代码。
- 若某步报错且超出上述范围（如 Flutter 环境异常、特殊网络），把错误日志带给用户，不要硬猜。
