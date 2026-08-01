// 把 HomeSchooling 听写包转换为 N 个 Echo Loop 音频条目。
//
// 每条 item 落本地沙盒，写入数据库，字幕里写一行 SRT。落盘复用现有
// `AudioFinalizationService`：它按内容指纹去重，避免重复占用空间。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';

import '../../database/daos/audio_item_dao.dart';
import '../../models/audio_item.dart';
import '../../providers/audio_library_provider.dart';
import '../../providers/collection_provider.dart';
import '../../utils/app_data_dir.dart';
import 'audio_finalization_service.dart';
import 'audio_import_models.dart';
import 'audio_registration_service.dart';
import 'homeschooling_package.dart';

/// 单次导入结果。包含已入库的条目、按指纹跳过的重复条目和解析失败计数。
class HomeschoolingPackageImportResult {
  const HomeschoolingPackageImportResult({
    required this.added,
    required this.duplicates,
    required this.failed,
  });

  final List<AudioItem> added;
  final List<String> duplicates;
  final int failed;

  int get total => added.length + duplicates.length + failed;
}

/// HomeSchooling 包导入器。
///
/// 内部用 `AudioFinalizationService` 落盘 + `AudioRegistrationService` 入库，
/// 不会自己写文件，遵循「落盘逻辑只此一处」。
class HomeschoolingPackageImporter {
  HomeschoolingPackageImporter({
    AudioFinalizationService? finalizationService,
    AudioRegistrationService? registrationService,
    Uuid? uuid,
    Future<Duration> Function(File file)? readSegmentDuration,
    Future<bool> Function(List<File> inputs, File output)? concatenateAudio,
  }) : _finalizationService = finalizationService ?? AudioFinalizationService(),
       _registrationService =
           registrationService ?? AudioRegistrationService(uuid: uuid),
       _uuid = uuid ?? const Uuid(),
       _readSegmentDuration =
           readSegmentDuration ?? _readSegmentDurationWithFfprobe,
       _concatenateAudio = concatenateAudio ?? _concatenateAudioWithFfmpeg;

  static const String _kTargetSubdir = 'audios/homeschooling_import';
  static const int _kMaxItemCount = 200;
  static const int _kMaxItemBytes = 25 * 1024 * 1024;

  final AudioFinalizationService _finalizationService;
  final AudioRegistrationService _registrationService;
  final Uuid _uuid;
  final Future<Duration> Function(File file) _readSegmentDuration;
  final Future<bool> Function(List<File> inputs, File output) _concatenateAudio;

  Future<HomeschoolingPackageImportResult> importJsonString(
    String source, {
    required AudioItemDao dao,
    required String childSlug,
    required AudioLibrary audioLibrary,
    required AudioLibraryState audioLibraryState,
    CollectionList? collectionList,
    CollectionState? collectionState,
  }) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } catch (error) {
      throw AudioImportException(
        AudioImportFailureCode.invalidPayload,
        'HomeSchooling 包不是合法 JSON。',
        error,
      );
    }
    final package = HomeschoolingPackage.tryParse(decoded);
    if (package == null) {
      throw const AudioImportException(
        AudioImportFailureCode.invalidPayload,
        'HomeSchooling 包结构无法识别。',
      );
    }
    return importPackage(
      package,
      dao: dao,
      childSlug: childSlug,
      audioLibrary: audioLibrary,
      audioLibraryState: audioLibraryState,
      collectionList: collectionList,
      collectionState: collectionState,
    );
  }

  Future<HomeschoolingPackageImportResult> importPackage(
    HomeschoolingPackage package, {
    required AudioItemDao dao,
    required String childSlug,
    required AudioLibrary audioLibrary,
    required AudioLibraryState audioLibraryState,
    CollectionList? collectionList,
    CollectionState? collectionState,
  }) async {
    if (package.items.length > _kMaxItemCount) {
      throw AudioImportException(
        AudioImportFailureCode.invalidPayload,
        'HomeSchooling 包条目太多（> $_kMaxItemCount）。',
      );
    }
    final dataDir = await getAppDataDirectory();
    final added = <AudioItem>[];
    final duplicates = <String>[];
    var failed = 0;

    if (package.contentMode == 'passage') {
      return _importPassage(
        package,
        dataDir: dataDir,
        audioLibrary: audioLibrary,
        audioLibraryState: audioLibraryState,
        collectionList: collectionList,
        collectionState: collectionState,
        dao: dao,
      );
    }

    for (var index = 0; index < package.items.length; index++) {
      final item = package.items[index];
      if (!item.transcriptVerified) {
        failed++;
        continue;
      }
      final bytes = _decodeBase64(item.audioBase64);
      if (bytes == null || bytes.isEmpty) {
        failed++;
        continue;
      }
      if (bytes.length > _kMaxItemBytes) {
        failed++;
        continue;
      }
      try {
        final tempRelative = await _writeTemp(
          dataDir: dataDir,
          bytes: bytes,
          format: item.audioFormat,
          index: index,
        );
        final finalized = await _finalizationService.finalize(
          dataDir: dataDir,
          tempRelativePath: tempRelative,
          targetSubdir: _kTargetSubdir,
        );

        final displayName = item.text.length > 80
            ? '${item.text.substring(0, 77)}...'
            : item.text;
        final safeName = '$displayName (${index + 1})';
        final srt = _buildSingleLineSrt(index: index, text: item.text);

        final registration = await _registrationService.registerSandboxedAudio(
          input: SandboxedAudioRegistrationInput(
            name: safeName,
            relativePath: finalized.relativePath,
            importSourceType: AudioImportSourceType.local,
            importSourceUrl: null,
            audioSha256: finalized.sha256,
            originalAudioSha256: finalized.originalSha256,
          ),
          audioLibrary: audioLibrary,
          audioLibraryState: audioLibraryState,
          collectionList: collectionList,
          collectionState: collectionState,
        );

        final addedItem = switch (registration) {
          AudioRegistrationAdded(:final item) => item,
          AudioRegistrationDuplicate(:final name) => () {
            duplicates.add(name);
            return null;
          }(),
        };
        if (addedItem != null) {
          // 写入单行 SRT 字幕 + 来源标记，方便家长在资源库看到「来自 HomeSchooling」。
          final withMeta = addedItem.copyWith(
            transcriptSource: TranscriptSource.local,
          );
          await audioLibrary.updateAudioItem(withMeta);
          await dao.updateTranscriptSrt(withMeta.id, srt);
          added.add(withMeta);
        }
      } catch (_) {
        failed++;
      }
    }
    return HomeschoolingPackageImportResult(
      added: added,
      duplicates: duplicates,
      failed: failed,
    );
  }

  Future<HomeschoolingPackageImportResult> _importPassage(
    HomeschoolingPackage package, {
    required Directory dataDir,
    required AudioLibrary audioLibrary,
    required AudioLibraryState audioLibraryState,
    required AudioItemDao dao,
    CollectionList? collectionList,
    CollectionState? collectionState,
  }) async {
    final validItems = package.items
        .where((item) => item.transcriptVerified)
        .toList(growable: false);
    if (validItems.isEmpty) {
      return HomeschoolingPackageImportResult(
        added: const [],
        duplicates: const [],
        failed: package.items.length,
      );
    }
    final decoded = <Uint8List>[];
    for (final item in validItems) {
      final bytes = _decodeBase64(item.audioBase64);
      if (bytes == null || bytes.isEmpty || bytes.length > _kMaxItemBytes) {
        return HomeschoolingPackageImportResult(
          added: const [],
          duplicates: const [],
          failed: package.items.length,
        );
      }
      decoded.add(bytes);
    }
    try {
      final combined = await _concatAudioSegments(
        dataDir: dataDir,
        segments: decoded,
        format: validItems.first.audioFormat,
      );
      final finalized = await _finalizationService.finalize(
        dataDir: dataDir,
        tempRelativePath: combined.relativePath,
        targetSubdir: _kTargetSubdir,
      );
      final registration = await _registrationService.registerSandboxedAudio(
        input: SandboxedAudioRegistrationInput(
          name: package.title.isEmpty ? 'HomeSchooling 短文' : package.title,
          relativePath: finalized.relativePath,
          importSourceType: AudioImportSourceType.local,
          importSourceUrl: null,
          audioSha256: finalized.sha256,
          originalAudioSha256: finalized.originalSha256,
        ),
        audioLibrary: audioLibrary,
        audioLibraryState: audioLibraryState,
        collectionList: collectionList,
        collectionState: collectionState,
      );
      return switch (registration) {
        AudioRegistrationDuplicate(:final name) =>
          HomeschoolingPackageImportResult(
            added: const [],
            duplicates: [name],
            failed: 0,
          ),
        AudioRegistrationAdded(:final item) => await _finishPassageImport(
          item,
          validItems,
          segmentDurations: combined.segmentDurations,
          dao: dao,
          audioLibrary: audioLibrary,
        ),
      };
    } catch (_) {
      return HomeschoolingPackageImportResult(
        added: const [],
        duplicates: const [],
        failed: package.items.length,
      );
    }
  }

  Future<HomeschoolingPackageImportResult> _finishPassageImport(
    AudioItem item,
    List<HomeschoolingPackageItem> sourceItems, {
    required List<Duration> segmentDurations,
    required AudioItemDao dao,
    required AudioLibrary audioLibrary,
  }) async {
    final withMeta = item.copyWith(transcriptSource: TranscriptSource.local);
    await audioLibrary.updateAudioItem(withMeta);
    await dao.updateTranscriptSrt(
      withMeta.id,
      buildHomeschoolingPassageSrt(sourceItems, segmentDurations),
    );
    return HomeschoolingPackageImportResult(
      added: [withMeta],
      duplicates: const [],
      failed: 0,
    );
  }

  Future<_CombinedPassageAudio> _concatAudioSegments({
    required Directory dataDir,
    required List<Uint8List> segments,
    required String format,
  }) async {
    final ext = format.isEmpty ? 'mp3' : format.toLowerCase();
    final tmpDir = Directory(
      p.join(dataDir.path, 'tmp', 'homeschooling_import'),
    );
    await tmpDir.create(recursive: true);
    final runId = _uuid.v4();
    final inputs = <File>[];
    for (var index = 0; index < segments.length; index++) {
      final input = File(p.join(tmpDir.path, '$runId-$index.$ext'));
      await input.writeAsBytes(segments[index], flush: true);
      inputs.add(input);
    }
    final output = File(p.join(tmpDir.path, '$runId-combined.m4a'));
    try {
      final durations = <Duration>[];
      for (final input in inputs) {
        final duration = await _readSegmentDuration(input);
        if (duration <= Duration.zero) {
          throw const FileSystemException('HomeSchooling 句子音频时长无效。');
        }
        durations.add(duration);
      }
      final concatenated = await _concatenateAudio(inputs, output);
      if (!concatenated || !await output.exists()) {
        throw const FileSystemException('无法合并 HomeSchooling 短文音频。');
      }
      return _CombinedPassageAudio(
        relativePath: p.relative(output.path, from: dataDir.path),
        segmentDurations: durations,
      );
    } finally {
      for (final input in inputs) {
        if (await input.exists()) await input.delete();
      }
    }
  }

  Future<String> _writeTemp({
    required Directory dataDir,
    required Uint8List bytes,
    required String format,
    required int index,
  }) async {
    final tmpDir = Directory(
      p.join(dataDir.path, 'tmp', 'homeschooling_import'),
    );
    await tmpDir.create(recursive: true);
    final ext = format.isEmpty ? 'mp3' : format.toLowerCase();
    final tempRelative = p.join(
      'tmp',
      'homeschooling_import',
      '$index-${_uuid.v4()}.$ext',
    );
    final tempFile = File(p.join(dataDir.path, tempRelative));
    await tempFile.writeAsBytes(bytes, flush: true);
    return tempRelative;
  }

  Uint8List? _decodeBase64(String source) {
    try {
      return Uint8List.fromList(base64.decode(source));
    } catch (_) {
      return null;
    }
  }

  String _buildSingleLineSrt({required int index, required String text}) {
    final id = index + 1;
    final safeText = text.replaceAll('\r', ' ').replaceAll('\n', ' ');
    return '$id\n00:00:00,000 --> 00:00:01,000\n$safeText\n';
  }

  static Future<Duration> _readSegmentDurationWithFfprobe(File file) async {
    final session = await FFprobeKit.getMediaInformation(file.path, 10000);
    final seconds = double.tryParse(
      session.getMediaInformation()?.getDuration() ?? '',
    );
    if (seconds == null || !seconds.isFinite || seconds <= 0) {
      throw FileSystemException('无法读取 HomeSchooling 句子音频时长。', file.path);
    }
    return Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round(),
    );
  }

  static Future<bool> _concatenateAudioWithFfmpeg(
    List<File> inputs,
    File output,
  ) async {
    final arguments = <String>['-nostdin', '-y', '-loglevel', 'error'];
    for (final input in inputs) {
      arguments.addAll(['-i', input.path]);
    }
    final filterInputs = List.generate(
      inputs.length,
      (index) => '[$index:a:0]',
    ).join();
    arguments.addAll([
      '-filter_complex',
      '${filterInputs}concat=n=${inputs.length}:v=0:a=1[out]',
      '-map',
      '[out]',
      '-c:a',
      'aac',
      '-b:a',
      '96k',
      output.path,
    ]);
    final session = await FFmpegKit.executeWithArguments(arguments);
    final returnCode = await session.getReturnCode();
    return ReturnCode.isSuccess(returnCode);
  }
}

class _CombinedPassageAudio {
  const _CombinedPassageAudio({
    required this.relativePath,
    required this.segmentDurations,
  });

  final String relativePath;
  final List<Duration> segmentDurations;
}

/// 用原始句子音频的真实时长生成整篇字幕，不进行二次语义切句。
String buildHomeschoolingPassageSrt(
  List<HomeschoolingPackageItem> items,
  List<Duration> segmentDurations,
) {
  if (items.length != segmentDurations.length) {
    throw ArgumentError('句子数量与音频时长数量不一致。');
  }
  var cursor = Duration.zero;
  final buffer = StringBuffer();
  for (var index = 0; index < items.length; index++) {
    final start = cursor;
    cursor += segmentDurations[index];
    buffer
      ..writeln(index + 1)
      ..writeln(
        '${_formatHomeschoolingSrtTime(start)} --> '
        '${_formatHomeschoolingSrtTime(cursor)}',
      )
      ..writeln(items[index].text.replaceAll('\r', ' ').replaceAll('\n', ' '))
      ..writeln();
  }
  return buffer.toString();
}

String _formatHomeschoolingSrtTime(Duration value) {
  String two(int number) => number.toString().padLeft(2, '0');
  String three(int number) => number.toString().padLeft(3, '0');
  return '${two(value.inHours)}:${two(value.inMinutes.remainder(60))}:'
      '${two(value.inSeconds.remainder(60))},'
      '${three(value.inMilliseconds.remainder(1000))}';
}
