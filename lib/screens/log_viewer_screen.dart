/// 开发者日志查看页面
///
/// 实时显示应用内日志，支持滚动、清空、分享。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/app_logger.dart';
import '../services/device_diagnostics_service.dart';
import '../theme/app_theme.dart';

/// 日志分享启动函数，供 widget 测试替换系统分享面板。
typedef LogShareLauncher =
    Future<ShareResult> Function(
      List<XFile> files, {
      String? subject,
      String? text,
      Rect? sharePositionOrigin,
      List<String>? fileNameOverrides,
    });

/// 日志查看页面
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key, this.shareLauncher});

  /// 系统分享启动函数。生产环境为空时使用 [Share.shareXFiles]。
  final LogShareLauncher? shareLauncher;

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  final _scrollController = ScrollController();
  final _deviceDiagnosticsService = const DeviceDiagnosticsService();
  Future<void>? _deviceInfoLogFuture;
  bool _didLogDeviceInfo = false;

  @override
  void initState() {
    super.initState();
    AppLogger.instance.addListener(_onLogUpdated);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLogDeviceInfo) return;
    _didLogDeviceInfo = true;
    _deviceInfoLogFuture = _logDeviceInfo();
  }

  @override
  void dispose() {
    AppLogger.instance.removeListener(_onLogUpdated);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogUpdated() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  /// 记录设备信息快照，便于分享日志时直接包含机型、系统版本和 App 版本。
  Future<void> _logDeviceInfo() async {
    try {
      final line = await _deviceDiagnosticsService.buildLogLine(context);
      if (!mounted) return;
      AppLogger.log('DeviceInfo', line);
    } catch (e) {
      AppLogger.log('DeviceInfo', 'collect failed: $e');
    }
  }

  /// 分享日志：优先导出落盘文件（含 Worker isolate 的 ASR 推理日志、跨进程历史），
  /// 落盘不可用时回退到内存缓冲，并通过系统分享面板发出 .log 文件。
  Future<void> _shareAll() async {
    AppLogger.log('LogViewer', 'share logs start');
    try {
      await _deviceInfoLogFuture;
      AppLogger.log('LogViewer', 'share logs device info ready');
      final persisted = await AppLogger.readPersistedLog();
      final text = (persisted != null && persisted.trim().isNotEmpty)
          ? persisted
          : AppLogger.instance.entries.map((e) => e.toString()).join('\n');
      if (!mounted) return;
      final path = await _writeLogExportFile(text);
      AppLogger.log('LogViewer', 'share logs file ready: $path');
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final share = widget.shareLauncher ?? Share.shareXFiles;
      AppLogger.log(
        'LogViewer',
        'share logs launch custom=${widget.shareLauncher != null}',
      );
      await share(
        [XFile(path, mimeType: 'text/plain')],
        subject: 'Echo Loop Logs',
        sharePositionOrigin: box == null
            ? Rect.zero
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      AppLogger.log('LogViewer', 'share logs failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分享日志失败：$e')));
    }
  }

  /// 写入供系统分享使用的临时日志文件。
  ///
  /// 分享后不能立即删除：macOS / AirDrop 可能在用户选择目标后才开始读取文件。
  /// `log_export_` 目录由 temp_cleanup_service 白名单回收。
  Future<String> _writeLogExportFile(String text) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final dir = Directory(p.join(tempDir.path, 'log_export_$timestamp'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'echo_loop_logs_$timestamp.log'));
    await file.writeAsString(text, flush: true);
    return file.path;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = AppLogger.instance.entries;

    return Scaffold(
      appBar: AppBar(
        title: Text('日志 (${entries.length})'),
        centerTitle: true,
        actions: [
          IconButton(
            key: const ValueKey('log_viewer_share_button'),
            tooltip: '分享日志',
            icon: const Icon(Icons.ios_share),
            onPressed: entries.isEmpty ? null : () => unawaited(_shareAll()),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: entries.isEmpty
                ? null
                : () {
                    AppLogger.instance.clear();
                    setState(() {});
                  },
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Text(
                '暂无日志',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              itemCount: entries.length,
              padding: const EdgeInsets.all(AppSpacing.s),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _LogEntryTile(entry: entry);
              },
            ),
    );
  }
}

/// 单条日志显示
class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;
  const _LogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr =
        '${entry.time.hour.toString().padLeft(2, '0')}:'
        '${entry.time.minute.toString().padLeft(2, '0')}:'
        '${entry.time.second.toString().padLeft(2, '0')}.'
        '${entry.time.millisecond.toString().padLeft(3, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: timeStr,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            TextSpan(
              text: ' [${entry.tag}] ',
              style: TextStyle(
                color: _tagColor(entry.tag, theme),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
            TextSpan(
              text: entry.message,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _tagColor(String tag, ThemeData theme) {
    return switch (tag) {
      'Turn' => Colors.orange,
      'Player' => Colors.blue,
      'Screen' => Colors.green,
      _ => theme.colorScheme.primary,
    };
  }
}
