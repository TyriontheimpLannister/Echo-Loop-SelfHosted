// 音频条目的共享操作。
//
// 资源库/合集列表项菜单（[AudioListTile]）与学习计划页顶栏菜单共用同一套
// 「管理字幕 / 导出音频」逻辑，避免导出等较复杂流程在两处重复。
// 编辑字幕、导出 PDF 只是单行路由跳转，仍在各调用点内联，不在此聚合。
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:universal_io/io.dart';

import '../database/providers.dart';
import '../l10n/app_localizations.dart';
import '../models/audio_item.dart';
import '../providers/audio_library_provider.dart';
import '../services/audio_export_service.dart';
import '../features/audio_import/homeschooling_package_controller.dart';
import '../features/audio_import/homeschooling_transfer_service.dart';
import '../widgets/dialogs/export_audio_dialog.dart';
import '../widgets/manage_subtitles_sheet.dart';
import 'app_data_dir.dart';

/// 懒检测音频内容有效性。
///
/// 用户接触音频（打开学习 / 管理字幕）时才检测，把开销分摊到实际使用。已确认
/// ok 的音频不重复检测；异常状态允许重检，用于修正旧版误报缓存。
void maybeCheckAudioContent(WidgetRef ref, AudioItem item) {
  if (!item.isAudioReady || item.contentStatus == AudioContentStatus.ok) return;
  unawaited(ref.read(audioLibraryProvider.notifier).checkAudioContent(item.id));
}

/// 打开「管理字幕」底部弹窗（进入前懒检测一次内容状态，让转录前拦截能拿到状态）。
void showManageSubtitlesSheet(
  BuildContext context,
  WidgetRef ref,
  AudioItem audioItem,
) {
  maybeCheckAudioContent(ref, audioItem);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => ManageSubtitlesSheet(audioItem: audioItem),
  );
}

/// 导出音频：弹选项对话框（音频文件 / 字幕）→ 生成临时包 → 平台分发保存。
///
/// 字幕内容存 DB 列时先落临时 SRT 供打包，导出后清理；移动端走系统分享，
/// 桌面端走「另存为」文件选择器。
Future<void> exportAudioItem(
  BuildContext context,
  WidgetRef ref,
  AudioItem audioItem,
) async {
  final l10n = AppLocalizations.of(context)!;

  // 1. 弹出导出选项对话框
  final selection = await showExportAudioDialog(
    context: context,
    hasTranscript: audioItem.hasTranscript,
  );
  if (selection == null || !context.mounted) return;

  try {
    // 2. 解析文件绝对路径
    final audioPath = await audioItem.getFullAudioPath();
    if (audioPath == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.audioFileNotFound)));
      }
      return;
    }
    // 字幕内容存 DB 列：导出需要文件，故把列内容落临时 SRT 供打包。
    // 旧行（transcriptPath 非 null）仍直接用遗留文件。
    String? transcriptPath = await audioItem.getFullTranscriptPath();
    File? tempTranscriptFile;
    if (selection.includeTranscript && transcriptPath == null) {
      final srt = await ref
          .read(audioItemDaoProvider)
          .getTranscriptSrt(audioItem.id);
      if (srt != null && srt.isNotEmpty) {
        final dataDir = await getAppDataDirectory();
        final tmpDir = Directory(p.join(dataDir.path, 'tmp', 'export'));
        await tmpDir.create(recursive: true);
        tempTranscriptFile = File(
          p.join(tmpDir.path, '${audioItem.id}_export.srt'),
        );
        await tempTranscriptFile.writeAsString(srt);
        transcriptPath = tempTranscriptFile.path;
      }
    }

    // 3. 调用导出服务生成临时文件
    final service = AudioExportService();
    final String exportPath;
    try {
      exportPath = await service.exportAudioItem(
        displayName: audioItem.name,
        audioPath: audioPath,
        transcriptPath: transcriptPath,
        includeAudio: selection.includeAudio,
        includeTranscript: selection.includeTranscript,
      );
    } finally {
      // 清理临时字幕文件（导出服务已把内容打包）
      if (tempTranscriptFile != null) {
        try {
          await tempTranscriptFile.delete();
        } catch (_) {}
      }
    }

    if (!context.mounted) return;

    // 4. 平台分发保存
    if (Platform.isIOS || Platform.isAndroid) {
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(exportPath)],
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : Rect.zero,
      );
    } else {
      final ext = p.extension(exportPath).replaceFirst('.', '');
      final fileName = p.basename(exportPath);
      final home = Platform.environment['HOME'];
      final downloadsDir = home != null ? '$home/Downloads' : null;

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: l10n.exportAudio,
        fileName: fileName,
        initialDirectory: downloadsDir,
        type: FileType.custom,
        allowedExtensions: [ext],
      );
      if (savePath != null) {
        await File(exportPath).copy(savePath);
        if (context.mounted) {
          final savedName = p.basename(savePath);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.exportSuccess}: $savedName')),
          );
        }
      }
    }

    // 5. 清理临时文件
    try {
      await File(exportPath).delete();
    } catch (_) {}
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${l10n.exportAudio}: $e')));
  }
}

/// 把单个音频导出为 HomeSchooling 听写包并直接写入父端听写任务。
///
/// 包按 SRT 时间轴切分，每条听写项携带对应的句级音频。
Future<void> exportHomeSchoolingPackage(
  BuildContext context,
  WidgetRef ref,
  AudioItem audioItem,
) async {
  final dao = ref.read(audioItemDaoProvider);
  final libraryItems = ref.read(audioLibraryProvider).audioItems;
  final currentItem = libraryItems
      .where((item) => item.id == audioItem.id)
      .cast<AudioItem?>()
      .firstWhere((item) => item != null, orElse: () => audioItem)!;
  if (!currentItem.isAudioReady) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('音频还没有准备好，请先下载或转码。')));
    return;
  }
  final audioPath = await currentItem.getFullAudioPath();
  if (audioPath == null || !await File(audioPath).exists()) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('音频文件没有保存完整，请重新导入或重新转录后再发送。')));
    return;
  }
  try {
    final package = await ref.buildHomeschoolingPackage(currentItem);
    if (package == null) {
      if (!context.mounted) return;
      final exporter = ref.read(homeschoolingPackageExporterProvider);
      final hasColumn = await exporter.debugHasTranscriptSrtColumn(dao);
      if (!context.mounted) return;
      String message;
      if (!hasColumn) {
        message = '当前版本数据库缺字幕存储字段，请先退出并重新打开 App 让 schema 自动补齐，然后再发送。';
      } else if (currentItem.hasTranscript) {
        message = '字幕或句子音频没有生成完整，请重新运行一次 AI 转录后再发送。';
      } else {
        message = '需要先有字幕才能转为听写包。';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (!context.mounted) return;
    final password = await _askHomeSchoolingPassword(context);
    if (password == null || !context.mounted) return;

    final transfer = HomeSchoolingTransferService();
    final children = await transfer.loadChildren(password);
    if (!context.mounted) return;
    final child = children.length == 1
        ? children.first
        : await _chooseHomeSchoolingChild(context, children);
    if (child == null || !context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('正在发送到 HomeSchooling…')));
    final result = await transfer.sendPackage(
      package: package,
      password: password,
      childSlug: child.slug,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已发送给 ${child.name}：${result.taskName}（${result.itemCount} 项）',
        ),
      ),
    );
  } on HomeSchoolingTransferException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.message)));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('生成听写包失败：$e')));
  }
}

Future<String?> _askHomeSchoolingPassword(BuildContext context) async {
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('发送到 HomeSchooling'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(labelText: '家长密码'),
          onSubmitted: (_) {
            final password = controller.text.trim();
            if (password.isNotEmpty) {
              Navigator.of(dialogContext).pop(password);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final password = controller.text.trim();
              if (password.isNotEmpty) {
                Navigator.of(dialogContext).pop(password);
              }
            },
            child: const Text('下一步'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<HomeSchoolingChild?> _chooseHomeSchoolingChild(
  BuildContext context,
  List<HomeSchoolingChild> children,
) {
  return showDialog<HomeSchoolingChild>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('发送给谁'),
      children: [
        for (final child in children)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(child),
            child: Text(child.name),
          ),
      ],
    ),
  );
}
