import '../../models/audio_item.dart';

/// 支持的音频导入来源。
///
/// 直链和未来 Podcast RSS 单集都会先规整成可下载的音频来源，再复用同一套
/// 下载、落盘和入库流程。
sealed class AudioImportSource {
  const AudioImportSource();
}

/// 从音频直链导入。
class DirectUrlImportSource extends AudioImportSource {
  const DirectUrlImportSource(this.url);

  final String url;
}

/// 未来 RSS 单集导入的预留来源。
class PodcastEpisodeImportSource extends AudioImportSource {
  const PodcastEpisodeImportSource({
    required this.audioUrl,
    required this.title,
    this.publishedAt,
  });

  final String audioUrl;
  final String title;
  final DateTime? publishedAt;
}

/// 链接解析后的可下载音频信息。
class ResolvedAudioImport {
  const ResolvedAudioImport({
    required this.uri,
    required this.displayName,
    required this.fileName,
    required this.extension,
    this.mimeType,
    this.contentLength,
  });

  final Uri uri;
  final String displayName;
  final String fileName;
  final String extension;
  final String? mimeType;
  final int? contentLength;
}

/// 仅落盘的音频下载结果（不入库）。
///
/// 供 podcast 单集懒下载使用：拿到沙盒相对路径、时长、指纹后，由调用方更新
/// 已存在的占位 [AudioItem]，而不是新建条目。
class DownloadedAudio {
  const DownloadedAudio({
    required this.relativePath,
    required this.durationSeconds,
    this.audioSha256,
    this.originalAudioSha256,
  });

  final String relativePath;
  final int durationSeconds;
  final String? audioSha256;
  final String? originalAudioSha256;
}

enum AudioImportFailureCode {
  invalidUrl,
  unsupportedScheme,
  unsupportedFormat,
  invalidPayload,
  network,
  notAudio,
  duplicate,
  storage,
  canceled,
  unknown,
}

class AudioImportException implements Exception {
  const AudioImportException(this.code, this.message, [this.cause]);

  final AudioImportFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

sealed class AudioImportState {
  const AudioImportState();
}

class AudioImportIdle extends AudioImportState {
  const AudioImportIdle();
}

class AudioImportResolving extends AudioImportState {
  const AudioImportResolving();
}

class AudioImportDownloading extends AudioImportState {
  const AudioImportDownloading({
    required this.displayName,
    required this.progress,
    this.receivedBytes,
    this.totalBytes,
  });

  final String displayName;

  /// 0..1；-1 表示服务端未提供总大小，UI 使用不定进度。
  final double progress;
  final int? receivedBytes;
  final int? totalBytes;
}

class AudioImportSaving extends AudioImportState {
  const AudioImportSaving(this.displayName);

  final String displayName;
}

class AudioImportCompleted extends AudioImportState {
  const AudioImportCompleted(this.audioItem);

  final AudioItem audioItem;
}

class AudioImportFailed extends AudioImportState {
  const AudioImportFailed(this.error);

  final AudioImportException error;
}
