<div align="right">
  <a href="./README.en.md">English</a> | <strong>简体中文</strong>
</div>

> 📌 **个人 fork 说明**：本仓库是从 [echo-loop/Echo-Loop](https://github.com/echo-loop/Echo-Loop) fork 而来，仅作**个人自用**，不向上游提交 Pull Request。如需为上游贡献代码或反馈问题，请前往原仓库。

# Echo Loop — 个人自用全功能版

Echo Loop 是一款英语听说训练 App（盲听 · 精听 · 跟读 · 复述 · 复习）。本 fork 在官方基础上集成了**自托管 AI 后端**（家庭局域网内的翻译 / 解析 / 意群 / 词典 / 转录服务）并**解除订阅限制（去锁）**，供家庭内孩子英语学习自用。

> ⚠️ 仅个人使用，不对外发布、不接受 Pull Request。

---

## 🧑‍💻 给开发者（自用构建）

<details open>
<summary><strong>🚀 快速开始</strong></summary>

```bash
git clone git@github.com:TyriontheimpLannister/Echo-Loop-SelfHosted.git
cd Echo-Loop
cp .dev.env.template .dev.env   # 填入 API 地址等编译期变量
flutter pub get
dart run build_runner build
flutter run -d <ios|android|macos> --dart-define-from-file=.dev.env
```

> 编译期环境变量（`SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`、`GOOGLE_WEB_CLIENT_ID`、`API_BASE_URL`）
> 统一放在 `.dev.env`（调试）/ `.prod.env`（发布），通过 `--dart-define-from-file` 注入。
> 这两个文件已被 `.gitignore`，请勿提交。`.prod.env` 用相同的键，把 `API_BASE_URL` 换成生产地址即可。

</details>

<details>
<summary><strong>🛠️ 技术栈</strong></summary>

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white)
![Riverpod](https://img.shields.io/badge/Riverpod-1F2937?logo=flutter&logoColor=white)
![Drift](https://img.shields.io/badge/Drift-SQLite-003B57?logo=sqlite&logoColor=white)
![Material 3](https://img.shields.io/badge/Material-3-757575?logo=materialdesign&logoColor=white)

| 类别 | 技术 | 用途 |
|------|------|------|
| UI 框架 | Flutter + Material 3 | 跨平台 UI |
| 状态管理 | Riverpod（代码生成） | 单向数据流 |
| 音频播放 | just_audio + audio_session | 音频引擎层 |
| 字幕解析 | subtitle | SRT/VTT |
| 文件选择 | file_picker | 本地音频/字幕导入 |
| 数据持久化 | Drift (SQLite) + shared_preferences | 学习进度、收藏、缓存 |
| 国际化 | flutter_localizations + ARB | 简体中文 / English |
| 测试 | flutter_test + mocktail | 单元 / Widget / 集成 |
| 静态分析 | flutter_lints | 代码规范 |

</details>

<details>
<summary><strong>📁 项目结构</strong></summary>

```
lib/
├── l10n/              # 国际化翻译文件（ARB 格式）
├── models/            # 数据模型（AudioItem, Sentence, Collection 等）
├── providers/         # Riverpod 状态管理
│   ├── audio_engine/  # 音频引擎层（底层播放控制）
│   └── listening_practice/  # 听力练习层（业务逻辑）
│       ├── sentence_tracker.dart   # 句子定位（二分查找）
│       └── bookmark_manager.dart   # 书签管理
├── screens/           # 页面
├── services/          # 服务层（StorageService, SubtitleParser）
└── widgets/           # 可复用组件
```

integration_test/      # 端到端测试
test/                  # 单元 / Widget 测试

</details>

<details>
<summary><strong>⌨️ 开发命令速查</strong></summary>

**运行**

```bash
flutter run -d ios            # iOS
flutter run -d android        # Android
flutter run -d macos          # macOS（开发中，未发布）
flutter run -d chrome         # Web（仅调试用，无发布计划）

# iOS 模拟器
xcrun simctl list devices available
xcrun simctl boot <DEVICE_UDID>
open -a Simulator
```

**测试 / 质量检查**

```bash
flutter analyze                          # 静态分析
flutter test                             # 全部测试
flutter test integration_test -d macos   # 集成测试
dart format .                            # 格式化
```

**代码生成**（修改 Riverpod Provider 后）

```bash
dart run build_runner build
```

**构建**

```bash
# 编译期变量从 env 文件注入（dev 用 .dev.env，发布用 .prod.env）
flutter build macos --dart-define-from-file=.prod.env
flutter build apk   --dart-define-from-file=.prod.env
flutter build ios   --dart-define-from-file=.prod.env

# 真机运行
flutter run --release -d <DEVICE_ID> --dart-define-from-file=.dev.env
```

> 发布脚本 `scripts/run_simulator.sh`（读 `.dev.env`）、`scripts/release_{android,ios,macos}.sh`（读 `.prod.env`）
> 已内置 `--dart-define-from-file`，无需手动传参。

**环境要求**

- Flutter SDK 3.9.2+
- iOS 模拟器 / Android 模拟器 / 真机
- 桌面端：macOS / Windows / Linux 开发环境

</details>

---

## 📄 License

[AGPL-3.0](./LICENSE)
