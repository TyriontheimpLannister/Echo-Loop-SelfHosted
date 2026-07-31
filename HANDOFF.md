# Echo Loop Handoff

> Updated: 2026-07-31 16:45
> Owner: Codex
> Status: READY_FOR_REVIEW

## Current Goal

保持 HomeSchooling 双向互通、双账号本地数据隔离和 HONOR PAD 上的自用更新链路可接管、可验证。

## Current State

- `Naomi` / `Francis` 使用独立 SQLite 数据库；首次升级旧数据库归 Francis。
- HomeSchooling child slug 按 Echo Loop 用户隔离保存，发送与在线接收均校验用户/孩子映射。
- 1.0.39（versionCode 82）已发布；APK 使用 `192.168.123.187:8000`，不再回退到 `localhost:3000`。
- `scripts/publish-apk.ps1` 已改为显式注入 `API_BASE_URL`，避免 `.dev.env` 格式差异造成配置丢失。
- Graphify 已刷新：2,520 nodes / 3,696 edges / 133 communities；代码-only，无 LLM 语义标注。

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

1. HONOR PAD 手动安装 `exports/app-dev-release-1.0.39.apk`。
2. 验收用户选择、双库隔离、HomeSchooling 发送/接收和更新检查。
3. 如需语义图谱，配置 Graphify LLM backend 后再运行 `graphify label .`。

## Verification

- Passed: HomeSchooling 互通测试 5/5。
- Passed: Graphify `extract . --code-only --no-cluster` 与 `cluster-only . --no-viz --no-label`。
- Passed: APK `app.echoloop.dev` / 1.0.39 / 82，服务器下载与本地 SHA-256 一致。
- Not run: 真机 adb 验收；当前未连接 HONOR PAD。

## Quick Index

| Need | Read |
|---|---|
| 双账号 | `lib/services/profile_service.dart` |
| HomeSchooling 接收 | `lib/features/audio_import/homeschooling_package_receiver_service.dart` |
| 发布 | `../scripts/publish-apk.ps1` |
| 图谱 | `graphify-out/` |

## Recent History

- 2026-07-31：修复 API 地址注入并发布 1.0.39；Graphify 刷新。
- 2026-07-31：确认旧 APK 的 `localhost:3000` 是更新失败根因。
- 2026-07-29：发布双账号/HomeSchooling 映射 1.0.38。
