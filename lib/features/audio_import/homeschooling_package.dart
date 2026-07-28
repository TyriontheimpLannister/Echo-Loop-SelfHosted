// HomeSchooling ↔ Echo Loop 听写包模型。
//
// 两个 App 互不直连，只通过这个 JSON 包传递音频 + 文本。版本字段 `version`
// 永远递增；解析时遇到不识别的版本应回退为"未知"而不是抛异常。
//
// HomeSchooling 侧在 `deployment/deeptutor/bridge/dictation/router.py` 的
// `admin_export_echo_loop` / `admin_import_echo_loop` 也是同样的 JSON 形状。
library;

import 'dart:convert';

/// HomeSchooling 听写/跟读材料包。
class HomeschoolingPackage {
  const HomeschoolingPackage({
    required this.version,
    required this.sourceApp,
    required this.sourceId,
    required this.title,
    required this.childSlug,
    required this.lang,
    required this.items,
    this.voice = '',
    this.speed = 1.0,
    this.skippedCount = 0,
    this.contentMode = 'sentences',
  });

  /// 包格式版本。新字段必须保持向后兼容，解析器对未知版本应保守回退。
  final int version;

  /// 来源 App：`homeschooling` 或 `echoloop`。
  final String sourceApp;

  /// 在源 App 里的稳定 ID，例如 `task:42`。
  final String sourceId;

  /// 任务或合集的可读名。
  final String title;

  /// 源 App 中的孩子标识；HomeSchooling 用 slug，Echo Loop 用本地 ID。
  final String childSlug;

  /// 语言：`en` 或 `zh`。
  final String lang;

  /// HomeSchooling 端的合成声音；Echo Loop 端导入时仅作展示。
  final String voice;

  /// HomeSchooling 端合成速度；保留 1.0 默认。
  final double speed;

  /// 包内每个句子/词条。
  final List<HomeschoolingPackageItem> items;

  /// 导出时跳过（音频尚未准备好）的条目数量，便于 UI 提示。
  final int skippedCount;

  /// HomeSchooling 家长指定的组织方式：`passage` 合为一篇，`sentences`
  /// 保持逐句独立。Echo Loop 不根据文本自动猜测。
  final String contentMode;

  Map<String, dynamic> toJson() => {
    'version': version,
    'source_app': sourceApp,
    'source_id': sourceId,
    'title': title,
    'child_slug': childSlug,
    'lang': lang,
    'voice': voice,
    'speed': speed,
    'items': items.map((item) => item.toJson()).toList(),
    'skipped_count': skippedCount,
    'content_mode': contentMode,
  };

  /// 序列化为紧凑 JSON。文件名等场景使用 indent 让家长更易读。
  String encode({bool pretty = false}) =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  static HomeschoolingPackage? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final version = raw['version'];
    if (version is! int || version != 1) return null;
    final itemsRaw = raw['items'];
    if (itemsRaw is! List) return null;
    final items = <HomeschoolingPackageItem>[];
    for (final entry in itemsRaw) {
      final item = HomeschoolingPackageItem.tryParse(entry);
      if (item != null) items.add(item);
    }
    return HomeschoolingPackage(
      version: version,
      sourceApp: (raw['source_app'] as String?) ?? '',
      sourceId: (raw['source_id'] as String?) ?? '',
      title: (raw['title'] as String?) ?? '',
      childSlug: (raw['child_slug'] as String?) ?? '',
      lang: (raw['lang'] as String?) ?? 'en',
      voice: (raw['voice'] as String?) ?? '',
      speed: (raw['speed'] as num?)?.toDouble() ?? 1.0,
      items: items,
      skippedCount: (raw['skipped_count'] as num?)?.toInt() ?? 0,
      contentMode: raw['content_mode'] == 'passage' ? 'passage' : 'sentences',
    );
  }
}

/// 包内一条听写/跟读项。
class HomeschoolingPackageItem {
  const HomeschoolingPackageItem({
    required this.text,
    required this.audioFormat,
    required this.audioBase64,
    this.transcriptVerified = true,
    this.source = '',
    this.order = 0,
  });

  /// 该条对应的标准文本。
  final String text;

  /// 音频格式，目前固定 `mp3`。
  final String audioFormat;

  /// base64 编码的音频字节；解码失败或缺失会被解析器丢弃。
  final String audioBase64;

  /// true 表示该条文本是源 App 已确认的，可直接进入听写答案；false 时
  /// Echo Loop 端只展示但不入库。
  final bool transcriptVerified;

  /// 原始音频来源，例如 `minimax_speech_2_8_hd` 或 `echoloop_upload`。
  final String source;

  /// 在源任务中的原始顺序。
  final int order;

  Map<String, dynamic> toJson() => {
    'text': text,
    'audio_format': audioFormat,
    'audio_b64': audioBase64,
    'transcript_verified': transcriptVerified,
    'source': source,
    'order': order,
  };

  static HomeschoolingPackageItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final text = (raw['text'] as String?)?.trim() ?? '';
    final audio = (raw['audio_b64'] as String?)?.trim() ?? '';
    if (text.isEmpty || audio.isEmpty) return null;
    return HomeschoolingPackageItem(
      text: text,
      audioFormat: (raw['audio_format'] as String?) ?? 'mp3',
      audioBase64: audio,
      transcriptVerified: raw['transcript_verified'] == true,
      source: (raw['source'] as String?) ?? '',
      order: (raw['order'] as num?)?.toInt() ?? 0,
    );
  }
}
