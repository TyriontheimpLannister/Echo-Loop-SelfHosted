# Echo Loop Handoff

> Updated: 2026-08-01 23:36
> Owner: Codex
> Status: READY_FOR_REVIEW

## Current Goal

保持句子级 AI 追问、HomeSchooling 双向互通、双账号隔离和 HONOR PAD 更新链路可接管、可验证。

## Current State

- `Naomi` / `Francis` 使用独立 SQLite 数据库；首次升级旧数据库归 Francis。
- HomeSchooling child slug 按 Echo Loop 用户隔离保存，发送与在线接收均校验用户/孩子映射。
- Graphify 已刷新：2,520 nodes / 3,696 edges / 133 communities；代码-only，无 LLM 语义标注。
- 1.0.40 自托管瘦身版已发布：官方合集、AI 聊天、远程配置轮询和第三方分析 SDK 已从运行路径移除；未配置认证时隐藏官方账号入口。
- Podcast 搜索/RSS、网页词典、自建 AI、HomeSchooling、PDF、离线 ASR/TTS 保留。
- HomeSchooling 在线拉取失败已定位并修复：当前任务 API 返回
  `child_id` 而非 `child_slug`；客户端现按孩子 ID 选择最新完成任务。
- 在线接收现于密码校验后展示当前孩子全部任务；完成任务可多选，生成中/失败任务可见但禁用。
- 批量导入按顺序执行，支持整篇/逐句模式，并为每个任务保留成功、重复或失败结果。
- 可见的旧 HomeSchooling JSON 文件包入口已移除；内部包模型/解析器继续供在线接收复用。
- 音频直链导入保留；相关服务测试已在 Windows 下改为跨平台路径断言并通过。
- 1.0.41（versionCode 84）已构建并发布；APK 内含 LAN API 地址，远端下载哈希与本地一致。
- 1.0.42（versionCode 85）已发布，包含 HomeSchooling 任务列表多选和旧 JSON 入口移除。
- 1.0.43（versionCode 86）已发布；HomeSchooling 整篇导入按真实片段时长保留原句边界。
- 句子级 AI 追问已部署：聊天空 session 使用 `local` token；生产后端真实契约 5/5。
- 1.0.44 真机反馈右上角图标难以发现；现已在解析结果下方加入显式“问 AI”按钮，
  并发布 1.0.45（versionCode 88）。

## Scope

Allowed paths:
- 双账号：`lib/services/profile_service.dart`、`lib/providers/profile_provider.dart`、`lib/screens/profile_selection_screen.dart`
- HomeSchooling：`lib/features/audio_import/`、`lib/widgets/import_audio_sheet.dart`
- 发布：`pubspec.yaml`、`android/app/build.gradle.kts`、`../scripts/publish-apk.ps1`
- 图谱：`graphify-out/`

Do not modify:
- `CLAUDE.md`、`.claude/` 和上游无关文件
- secrets、设备数据和生产后端密钥

## Next Steps

1. 希沃用同一材料标记至少 1 个难句，确认后续“难句跟读”触发模型下载和录音。
2. 用户确认后刷新 Graphify、提交并推送源码。

## Verification

- Passed: HomeSchooling 互通测试 5/5。
- Passed: Graphify `extract . --code-only --no-cluster` 与 `cluster-only . --no-viz --no-label`。
- Passed: HomeSchooling 传输/接收服务单测 5/5；导入弹层完整回归 29/29；
  针对性 analyze 无问题。
- Passed: 直链导入与音频注册 17/17；HomeSchooling 接收服务 3/3；传输服务 3/3。
- Passed: 导入弹层完整回归 29/29；HomeSchooling 多选覆盖密码后加载、不可用状态、
  多选、逐句模式、顺序导入和逐项反馈。
- Passed: 相关 Dart analyze 无问题；`git diff --check` 通过。
- Passed: APK `app.echoloop.dev` / 1.0.41 / 84 / 99,824,136 B；
  SHA-256 `84FA23E38351FC65C7BE08056F2CB80AD74EFDBF2CAA54255C343DC18CB660E6`。
- Passed: 服务器 manifest 1.0.41；远端下载 HTTP 200，字节数和 SHA-256 与本地一致。
- Passed: APK `app.echoloop.dev` / 1.0.42 / 85 / 99,824,388 B；
  SHA-256 `A5B13742F14F5C0FA6D4ECF1EEA882098A045F49C84A295222A5688C0BE332CB`；
  APK 内含 `http://192.168.123.187:8000`。
- Passed: 服务器 manifest 1.0.42；远端回下载字节数、版本元数据和 SHA-256 与本地一致。
- Passed: 两台学习机 1.0.45 均显示“问 AI”；小课屏聊天正常。Pending: 希沃难句跟读链路。
- Passed: 1.0.43 / versionCode 86 本地 release 构建；40 项相关测试和针对性 analyze。
- Passed: 句子聊天合并后测试 90/90；10 个相关文件 analyze 无问题。
- Passed: 后端 self test 15/15、生产真实契约 5/5；服务重启后健康。
- Passed: 追问入口组件 43/43、相关页面 72/72；4 个改动相关文件 analyze 无问题。
- Passed: `app-dev-release-1.0.45.apk` / 100,873,252 B / SHA-256
  `B5085089AC77F87C41AA51C673EFA0BBA59DD01571AA13174515075F2D91ED2B`；
  包元数据为 1.0.45/88，远端与回下载一致。

## Quick Index

| Need | Read |
|---|---|
| 双账号 | `lib/services/profile_service.dart` |
| HomeSchooling 接收 | `lib/features/audio_import/homeschooling_package_receiver_service.dart` |
| 句子 AI 追问 | `docs/handoffs/2026-08-01-echoloop_sentence_chat_handoff.md` |
| 发布 | `../scripts/publish-apk.ps1` |
| 图谱 | `graphify-out/` |

## Recent History

- 2026-08-01：两台学习机确认“问 AI”；希沃待用已标记难句验证跟读录音链路。
- 2026-07-31：发布 1.0.42，加入 HomeSchooling 任务列表多选和逐项导入反馈。
- 2026-07-31：发布 1.0.41，修复 HomeSchooling 在线拉取孩子筛选与无即时反馈。
- 2026-07-31：在线接收改为任务列表多选；移除可见的旧 JSON 文件包入口。
- 2026-07-31：审计官方功能，构建并发布瘦身版 1.0.40；远端哈希一致。
- 2026-07-31：修复 API 地址注入并发布 1.0.39；Graphify 刷新。
- 2026-07-31：确认旧 APK 的 `localhost:3000` 是更新失败根因。
- 2026-07-29：发布双账号/HomeSchooling 映射 1.0.38。
- 1.0.43（versionCode 86）候选包已本地构建，尚未发布；HomeSchooling
  整篇导入现按实际条目数逐段读取真实音频时长，合成一个音频并保留全部原句边界。
- 1.0.43（versionCode 86）已发布到
  `http://192.168.123.187:8000/updates/app-dev-release-1.0.43.apk`，
  SHA-256 `B8EF350A4C422F50E02939ACA24DD1694807536EBD5F5A27A2E31D9FC27E8987`，
  大小 99,824,388 B；远端下载字节数和 SHA-256 与本地一致；`version.json`
  release note UTF-8 正常。详见 `docs/handoffs/2026-08-01-passage-boundaries.md`。
