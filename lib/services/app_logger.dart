/// 应用内日志服务
///
/// 环形缓冲区存储最近的日志，供开发者选项中的日志页面查看。
/// 全局单例，通过 [AppLogger.instance] 访问。
/// 调用 [AppLogger.log] 记录日志，同时会 print 到控制台。
///
/// 此外可通过 [AppLogger.initFileSink] 开启**落盘**：每条日志同步写入文件并
/// flush，保证崩溃（含 native SIGABRT，进程被杀、内存缓冲丢失）前的日志仍在磁盘上，
/// 供日志页导出排查。Worker isolate 的日志可用 [AppLogger.formatLine] 按同样格式
/// 直接追加到同一文件（静态字段不跨 isolate 共享，故 isolate 内需自行写文件）。
library;

import 'dart:collection';
import 'dart:io';

/// 单条日志
class LogEntry {
  final DateTime time;
  final String tag;
  final String message;

  const LogEntry({
    required this.time,
    required this.tag,
    required this.message,
  });

  @override
  String toString() => AppLogger.formatLine(time, tag, message);
}

/// 应用内日志服务（环形缓冲区，最多保留 500 条）
class AppLogger {
  AppLogger._();
  static final instance = AppLogger._();

  static const _maxEntries = 500;

  /// 落盘日志文件大小上限，超过则在启动时保留尾部，避免无限增长。
  static const _maxFileBytes = 5 * 1024 * 1024;

  final _entries = Queue<LogEntry>();
  final _listeners = <void Function()>[];

  /// 落盘日志文件路径（[initFileSink] 设置，仅主 isolate 有效）。
  static String? _filePath;

  /// 所有日志条目（只读）
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// 统一的单行日志格式：`HH:MM:SS.mmm [tag] message`。
  ///
  /// 主 isolate 内存缓冲与各 isolate 落盘共用此格式，保证导出后可读、可对齐。
  static String formatLine(DateTime time, String tag, String message) {
    final t =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
    return '$t [$tag] $message';
  }

  /// 开启日志落盘（主 isolate 启动时调用一次）。
  ///
  /// 超过 [_maxFileBytes] 时只保留尾部，避免文件无限增长；随后把落盘日志尾部
  /// 恢复进内存环形缓冲，让重启后的日志页仍能看到最近日志。失败静默忽略
  /// （日志不应影响主流程）。
  static Future<void> initFileSink(String filePath) async {
    _filePath = filePath;
    try {
      final f = File(filePath);
      if (await f.exists() && await f.length() > _maxFileBytes) {
        final content = await f.readAsString();
        final keep = content.length > _maxFileBytes ~/ 2
            ? content.substring(content.length - _maxFileBytes ~/ 2)
            : content;
        await f.writeAsString('--- 日志已截断，保留尾部 ---\n$keep');
      }
      await _restoreRecentEntriesFromFile(f);
    } catch (_) {
      // 忽略：落盘失败不影响内存日志与主流程。
    }
  }

  /// 从落盘日志恢复最近 [_maxEntries] 条到内存缓冲，避免重启后日志页空白。
  ///
  /// 日志格式只有时间没有日期；恢复时使用当天日期补齐 [DateTime]，仅用于日志页排序
  /// 与展示，不参与业务逻辑。
  static Future<void> _restoreRecentEntriesFromFile(File file) async {
    if (!await file.exists()) return;
    final text = await file.readAsString();
    if (text.trim().isEmpty) return;
    final restored = text
        .split('\n')
        .map(_parsePersistedLine)
        .whereType<LogEntry>()
        .toList(growable: false);
    if (restored.isEmpty) return;

    final logger = instance;
    logger._entries.clear();
    final start = restored.length > _maxEntries
        ? restored.length - _maxEntries
        : 0;
    for (final entry in restored.skip(start)) {
      logger._entries.addLast(entry);
    }
  }

  /// 解析 [formatLine] 写出的单行日志；无法解析的截断提示等行会被跳过。
  static LogEntry? _parsePersistedLine(String line) {
    final match = RegExp(
      r'^(\d{2}):(\d{2}):(\d{2})\.(\d{3}) \[([^\]]+)\] (.*)$',
    ).firstMatch(line);
    if (match == null) return null;
    final now = DateTime.now();
    return LogEntry(
      time: DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
      ),
      tag: match.group(5)!,
      message: match.group(6)!,
    );
  }

  /// 读取已落盘的完整日志（含 Worker isolate 写入的部分），供日志页导出。
  ///
  /// 未开启落盘或读取失败时返回 null，调用方应回退到内存缓冲。
  static Future<String?> readPersistedLog() async {
    final path = _filePath;
    if (path == null) return null;
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// 同步追加一行到落盘文件并 flush，保证崩溃前已落盘。
  static void _appendToFile(String line) {
    final path = _filePath;
    if (path == null) return;
    try {
      File(
        path,
      ).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // 忽略：落盘失败不影响内存日志与主流程。
    }
  }

  /// 记录日志：print 到控制台 + 内存缓冲 + 落盘（若已开启）。
  static void log(String tag, String message) {
    final entry = LogEntry(time: DateTime.now(), tag: tag, message: message);
    // ignore: avoid_print
    print(entry);
    _appendToFile(entry.toString());
    final logger = instance;
    logger._entries.addLast(entry);
    if (logger._entries.length > _maxEntries) {
      logger._entries.removeFirst();
    }
    for (final listener in logger._listeners) {
      listener();
    }
  }

  /// 清空内存日志与当前落盘日志。
  void clear() {
    _entries.clear();
    final path = _filePath;
    if (path != null) {
      try {
        File(path).writeAsStringSync('', flush: true);
      } catch (_) {
        // 忽略：清空落盘失败不影响日志页内存清空。
      }
    }
    for (final listener in _listeners) {
      listener();
    }
  }

  /// 添加监听器（日志页面用于刷新 UI）
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// 移除监听器
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}
