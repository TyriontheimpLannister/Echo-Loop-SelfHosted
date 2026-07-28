// 从单个 Echo Loop 音频生成 HomeSchooling 听写包。
//
// 解析该音频已有的 SRT 字幕作为每条听写项的 text，并按字幕起止时间用
// FFmpeg 真正裁出对应音频，保证 HomeSchooling 收到的文字和音频逐句对齐。
library;

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:path/path.dart" as p;
import "package:uuid/uuid.dart";
import "package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart";
import "package:ffmpeg_kit_flutter_new_min/return_code.dart";
import "package:flutter/foundation.dart" show visibleForTesting;

import "../../database/daos/audio_item_dao.dart";
import "../../models/audio_item.dart";
import "../../models/sentence.dart";
import "../../utils/app_data_dir.dart";
import "../../services/app_logger.dart";
import "../../services/subtitle_parser.dart";
import "homeschooling_package.dart";

/// HomeSchooling 包导出器。
///
/// 解析 SRT 后逐句生成包项，每项的 audio_b64 只包含该句时间范围。
class HomeschoolingPackageExporter {
  HomeschoolingPackageExporter();

  static const int _kMaxItemCount = 200;
  static const int _kMaxItemBytes = 25 * 1024 * 1024;

  /// 构建 [HomeschoolingPackage]。
  ///
  /// 返回 null 表示没有字幕（导出方应提示用户先转写或手动编辑字幕）。
  Future<HomeschoolingPackage?> buildPackage({
    required AudioItemDao dao,
    required AudioItem audioItem,
    String lang = "en",
    String childSlug = "",
    String voice = "",
  }) async {
    if (!audioItem.isAudioReady) return null;
    final sentences = await _readSentences(dao, audioItem);
    // 兜底：当 DB 列返回空但模型层已标记为有字幕（少数旧设备未自愈），
    // 调用方可在调用前通过 [primeExtraSentences] 注入当前内存中的句子。
    var resolved = sentences;
    if (resolved.isEmpty &&
        _extraSentences != null &&
        _extraSentences!.isNotEmpty) {
      resolved = _extraSentences!;
    }
    if (resolved.isEmpty) return null;
    final sliced = resolved.length > _kMaxItemCount
        ? resolved.sublist(0, _kMaxItemCount)
        : resolved;
    final audioPath = await audioItem.getFullAudioPath();
    if (audioPath == null || !await File(audioPath).exists()) return null;
    final items = <HomeschoolingPackageItem>[];
    for (var i = 0; i < sliced.length; i++) {
      final s = sliced[i];
      final text = s.text.trim();
      if (text.isEmpty) continue;
      final audioBytes = await _sliceAudio(
        sourcePath: audioPath,
        sentence: s,
        index: i,
      );
      if (audioBytes == null || audioBytes.isEmpty) continue;
      if (audioBytes.length > _kMaxItemBytes) continue;
      items.add(
        HomeschoolingPackageItem(
          text: text,
          audioFormat: "m4a",
          audioBase64: base64.encode(audioBytes),
          transcriptVerified: true,
          source: "echoloop_${audioItem.id.substring(0, 8)}",
          order: i,
        ),
      );
    }
    if (items.isEmpty) return null;
    return HomeschoolingPackage(
      version: 1,
      sourceApp: "echoloop",
      sourceId: "audio:${audioItem.id}",
      title: audioItem.name,
      childSlug: childSlug,
      lang: lang,
      voice: voice,
      speed: 1.0,
      items: items,
    );
  }

  /// 调用方在 [buildPackage] 之前注入当前可用的句子列表，
  /// 用于 DB 列丢失但内存仍持有句子的兜底路径。
  List<Sentence>? _extraSentences;
  void primeExtraSentences(List<Sentence> sentences) {
    _extraSentences = sentences.isEmpty ? null : sentences;
  }

  /// 仅供测试访问内部兜底状态使用。
  @visibleForTesting
  List<Sentence>? debugExtraSentences() => _extraSentences;

  /// 诊断 audio_items 表是否包含 transcript_srt 列，用于区分「schema 缺失」
  /// 与「字幕落库失败」两种情况。
  Future<bool> debugHasTranscriptSrtColumn(AudioItemDao dao) async {
    try {
      final columns = await dao.listAudioItemColumns();
      return columns.contains('transcript_srt');
    } catch (_) {
      return false;
    }
  }

  /// 落盘到临时文件并返回路径。调用方负责清理。
  Future<File> writePackageToTempFile(
    HomeschoolingPackage package, {
    Directory? tempDir,
  }) async {
    final Directory dir;
    if (tempDir != null) {
      dir = tempDir;
    } else {
      final dataDir = await getAppDataDirectory();
      dir = Directory(p.join(dataDir.path, "tmp", "homeschooling_export"));
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(
      p.join(dir.path, "${const Uuid().v4()}.homeschooling.json"),
    );
    await file.writeAsString(package.encode(pretty: true), flush: true);
    return file;
  }

  Future<List<Sentence>> _readSentences(
    AudioItemDao daoArg,
    AudioItem audioItem,
  ) async {
    final dao = daoArg;
    final srt = await dao.getTranscriptSrt(audioItem.id);
    if (srt == null || srt.isEmpty) {
      // 兜底：旧行（transcriptPath 非空但 SRT 列为空）从遗留文件读。
      final transcriptPath = await audioItem.getFullTranscriptPath();
      if (transcriptPath == null) return const [];
      return await SubtitleParser.parseSubtitle(transcriptPath);
    }
    return await SubtitleParser.parseSubtitleString(srt);
  }

  Future<Uint8List?> _sliceAudio({
    required String sourcePath,
    required Sentence sentence,
    required int index,
  }) async {
    if (sentence.endTime <= sentence.startTime) return null;
    final dataDir = await getAppDataDirectory();
    final dir = Directory(p.join(dataDir.path, "tmp", "homeschooling_export"));
    await dir.create(recursive: true);
    final output = File(p.join(dir.path, "${const Uuid().v4()}-$index.m4a"));
    try {
      final session = await FFmpegKit.executeWithArguments(
        buildSentenceSliceArguments(
          sourcePath: sourcePath,
          outputPath: output.path,
          sentence: sentence,
        ),
      );
      final returnCode = await session.getReturnCode();
      final outputExists = await output.exists();
      final outputLength = outputExists ? await output.length() : 0;
      if (!ReturnCode.isSuccess(returnCode) || outputLength == 0) {
        final logs = await session.getOutput() ?? "";
        AppLogger.log(
          "HomeSchoolingExport",
          "sentence slice failed index=$index "
              "start=${sentence.startTime.inMilliseconds} "
              "end=${sentence.endTime.inMilliseconds} "
              "returnCode=$returnCode outputBytes=$outputLength logs=$logs",
        );
        return null;
      }
      return await output.readAsBytes();
    } finally {
      if (await output.exists()) await output.delete();
    }
  }
}

/// 构造 HomeSchooling 逐句音频裁切参数。
///
/// 当前依赖是 FFmpeg Kit `min`，不包含外部 LAME 编码器；因此必须使用该包
/// 自带的 AAC 编码器，并输出为 M4A。
@visibleForTesting
List<String> buildSentenceSliceArguments({
  required String sourcePath,
  required String outputPath,
  required Sentence sentence,
}) {
  return [
    "-nostdin",
    "-y",
    "-loglevel",
    "error",
    "-i",
    sourcePath,
    "-ss",
    (sentence.startTime.inMilliseconds / 1000).toStringAsFixed(3),
    "-t",
    ((sentence.endTime - sentence.startTime).inMilliseconds / 1000)
        .toStringAsFixed(3),
    "-vn",
    "-map",
    "0:a:0",
    "-map_metadata",
    "-1",
    "-map_chapters",
    "-1",
    "-c:a",
    "aac",
    "-b:a",
    "96k",
    outputPath,
  ];
}
