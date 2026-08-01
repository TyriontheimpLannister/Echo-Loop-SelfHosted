# 2026-08-01 HomeSchooling 整篇字幕边界保留 + Echo Loop 1.0.43 发布

## 背景

之前的 HomeSchooling → Echo Loop 整篇导入使用"每句固定 2 秒"的假时间轴生成 SRT，Echo Loop 收到后会在精听等场景下重新按时间戳切句，破坏原句边界。

## 修改

- `lib/features/audio_import/homeschooling_package_importer.dart` 使用 `FFprobeKit.getMediaInformation(...)` 读取每个原始句子片段的真实时长；`_concatAudioSegments` 合并后用累计时长生成 `transcript_srt`。
- 句数与片段数不一致直接抛 `ArgumentError`，避免再次退回伪 2 秒边界。
- 默认 `content_mode` 仍为 `passage`（一篇文章、一个音频）；`import_audio_sheet.dart` 文案改为"整篇文章（保留原句边界）"，删除旧"独立句子"分支。
- 新增 `test/features/audio_import/homeschooling_package_importer_test.dart` 覆盖真实时长累加和句数校验。

## 发布（2026-08-01）

- Echo Loop dev APK 1.0.43 已发布到 `http://192.168.123.187:8000/updates/app-dev-release-1.0.43.apk`；versionName 1.0.43、versionCode 86；大小 99,824,388 B；SHA-256 `B8EF350A4C422F50E02939ACA24DD1694807536EBD5F5A27A2E31D9FC27E8987`；本地/远端字节数和 SHA-256 完全一致。
- 服务器 `version.json` release note 已更新（中文 UTF-8 正常）。
- 40 项相关 Flutter 测试通过；`flutter analyze` 无新问题；`git diff --check` 通过。
- 推送目标：fork `https://github.com/TyriontheimpLannister/Echo-Loop-SelfHosted.git`（commit `d6831bd`）。

## 真机验收

- 旧 1.0.42 已导入的听写材料仍保留旧的"2 秒伪字幕"；用户在 HONOR PAD 上接受 1.0.43 更新后，需要手动删除该条音频条目，再从 HomeSchooling 重新导入一次，才会得到新的真实边界。
