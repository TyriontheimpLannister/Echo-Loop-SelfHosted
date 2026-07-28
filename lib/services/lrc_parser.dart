// LRC 歌词字幕解析器
//
// LRC 是歌词格式，每行只带起始时间标签（如 `[00:12.34]歌词`），没有结束时间。
// 本解析器把 LRC 解析成句子级字幕 [Sentence]：每句结束时间取下一句起点，
// 末句结束时间取音频总时长（未知则退回起点 + 默认间隔）。
//
// 解析结果随后统一经 `generateSrtContent` 序列化为 SRT 入库，与 srt/vtt 一致。
import 'dart:convert';

import '../models/sentence.dart';
import 'subtitle_parser.dart';

/// 末句在缺少音频时长（或时长早于末句起点）时的兜底显示间隔。
const Duration _lastLineFallbackGap = Duration(seconds: 5);

/// 匹配一行开头的一个时间标签：`[mm:ss]`、`[mm:ss.xx]`、`[mm:ss.xxx]`、`[hh:mm:ss.xx]`。
///
/// 分组：1=时(可选) 2=分 3=秒 4=小数(可选)。仅匹配纯数字标签，
/// 元数据标签（如 `[ar:歌手]`）首段非数字，不会命中。
final RegExp _timeTag = RegExp(
  r'\[(?:(\d{1,2}):)?(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]',
);

/// 匹配 `[offset:±毫秒]` 全局时间偏移标签。
final RegExp _offsetTag = RegExp(
  r'\[offset:\s*([+-]?\d+)\s*\]',
  caseSensitive: false,
);

/// 解析 LRC 歌词文本为句子级字幕。
///
/// [audioDuration] 为音频总时长，用于补全末句结束时间；未提供则末句用默认间隔兜底。
/// 无任何有效时间行时抛 [SubtitleParseException]（[SubtitleParseErrorKind.empty]）。
List<Sentence> parseLrc(String content, {Duration? audioDuration}) {
  if (content.trim().isEmpty) {
    throw const SubtitleParseException(SubtitleParseErrorKind.empty);
  }

  final offsetMs = _parseOffset(content);

  // 收集所有 (起始时间, 文本) 条目；一行可含多个时间标签（重复歌词）。
  final entries = <_LrcEntry>[];
  for (final line in const LineSplitter().convert(content)) {
    final matches = _timeTag.allMatches(line).toList();
    if (matches.isEmpty) continue;

    // 文本 = 去掉本行所有时间标签后的剩余内容。
    final text = line.replaceAll(_timeTag, '').trim();
    if (text.isEmpty) continue;

    for (final m in matches) {
      final startMs = _tagToMs(m) - offsetMs;
      entries.add(_LrcEntry(startMs < 0 ? 0 : startMs, text));
    }
  }

  if (entries.isEmpty) {
    throw const SubtitleParseException(SubtitleParseErrorKind.empty);
  }

  entries.sort((a, b) => a.startMs.compareTo(b.startMs));

  final durationMs = audioDuration?.inMilliseconds;
  final sentences = <Sentence>[];
  for (var i = 0; i < entries.length; i++) {
    final start = entries[i].startMs;
    final int end;
    if (i < entries.length - 1) {
      // 下一句起点即本句终点；若同一时间戳多条则至少等于自身（0 长度）。
      end = entries[i + 1].startMs < start ? start : entries[i + 1].startMs;
    } else {
      // 末句：优先贴到音频结尾，否则默认间隔兜底。
      end = (durationMs != null && durationMs > start)
          ? durationMs
          : start + _lastLineFallbackGap.inMilliseconds;
    }
    sentences.add(
      Sentence(
        index: i,
        text: entries[i].text,
        startTime: Duration(milliseconds: start),
        endTime: Duration(milliseconds: end),
      ),
    );
  }
  return sentences;
}

/// 读取 `[offset:±ms]`（毫秒）。正值表示歌词提前，负值延后；无则 0。
///
/// 约定与主流播放器一致：显示时间 = 原始时间 - offset。
int _parseOffset(String content) {
  final m = _offsetTag.firstMatch(content);
  if (m == null) return 0;
  return int.tryParse(m.group(1)!) ?? 0;
}

/// 把一个时间标签匹配转换为毫秒。小数位按位数换算：1位*100、2位*10、3位原样。
int _tagToMs(RegExpMatch m) {
  final hours = int.parse(m.group(1) ?? '0');
  final minutes = int.parse(m.group(2)!);
  final seconds = int.parse(m.group(3)!);
  final fraction = m.group(4);
  var fractionMs = 0;
  if (fraction != null) {
    switch (fraction.length) {
      case 1:
        fractionMs = int.parse(fraction) * 100;
      case 2:
        fractionMs = int.parse(fraction) * 10;
      default:
        fractionMs = int.parse(fraction);
    }
  }
  return ((hours * 3600 + minutes * 60 + seconds) * 1000) + fractionMs;
}

/// LRC 单条歌词（起始毫秒 + 文本）。
class _LrcEntry {
  const _LrcEntry(this.startMs, this.text);

  final int startMs;
  final String text;
}
