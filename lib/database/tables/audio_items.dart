import 'package:drift/drift.dart';

/// 音频元数据表
class AudioItems extends Table {
  /// UUID 主键
  TextColumn get id => text()();

  /// 音频名称
  TextColumn get name => text()();

  /// 音频文件相对路径。
  ///
  /// NULL 表示音频尚未就绪（官方合集加入后、下载完成前）；非 NULL 表示文件已在本地。
  /// 是「音频是否可用」的单一真实来源。
  TextColumn get audioPath => text().nullable()();

  /// 字幕文件相对路径。
  ///
  /// NULL 表示无字幕或尚未下载；非 NULL 表示文件已在本地。
  TextColumn get transcriptPath => text().nullable()();

  /// 添加时间
  DateTimeColumn get addedDate => dateTime()();

  /// 时长（秒）
  IntColumn get totalDuration => integer().withDefault(const Constant(0))();

  /// 字幕句子数
  IntColumn get sentenceCount => integer().withDefault(const Constant(0))();

  /// 字幕单词数
  IntColumn get wordCount => integer().withDefault(const Constant(0))();

  /// 是否置顶
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();

  /// 字幕来源：0=local, 1=ai, null=无字幕
  IntColumn get transcriptSource => integer().nullable()();

  /// 音频文件 SHA256 指纹（缓存，避免重复计算）
  TextColumn get audioSha256 => text().nullable()();

  /// 转码前原始音频 SHA256 指纹。
  ///
  /// AI 转录优先用该值作为后端字幕缓存 key；为空时回退 [audioSha256]。
  TextColumn get originalAudioSha256 => text().nullable()();

  /// AI 转录使用的语言（'en' / 'multi'）
  TextColumn get transcriptLanguage => text().nullable()();

  /// 音频内容有效性状态：0=ok, 1=damaged, 2=silent, null=未检测。
  /// 新下载时检测一次（短解码失败判 damaged，可解码但静音判 silent）。
  IntColumn get audioContentStatus => integer().nullable()();

  /// 最后修改时间
  DateTimeColumn get updatedAt => dateTime()();

  /// 软删除标记
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// 词级时间戳 JSON（AI 转录时由后端返回，与字幕一起管理）
  TextColumn get wordTimestampsJson => text().nullable()();

  /// 字幕内容（完整 SRT 文本）。
  ///
  /// DB 成为字幕的唯一真相源后，本列保存整段 SRT。NULL 表示无字幕，或旧行尚未
  /// backfill（由启动时全量 backfill 从 [transcriptPath] 指向的文件读入）。
  /// 大字段，与 [wordTimestampsJson] 一样不进列表查询，仅按需读写。
  TextColumn get transcriptSrt => text().nullable()();

  /// 同步状态：0=synced, 1=pendingUpload, 2=pendingDelete
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

  /// 官方合集中该音频在后端的 UUID；仅官方合集音频有值。
  /// 用于同步比对（通过 remoteAudioId 反查本地行）。
  TextColumn get remoteAudioId => text().nullable()();

  /// 原始发布/播出日期。官方合集音频从后端 catalog 同步（如 VOA 某期的播出日期）；
  /// 用户自建音频保持 NULL。用于官方合集详情页「最早/最新发布」排序。
  DateTimeColumn get originalDate => dateTime().nullable()();

  /// 用户导入来源类型：local / direct_url / cloud_drive。
  ///
  /// 官方/精选合集不使用该字段，继续由 remoteAudioId 和 collections.source 标识。
  TextColumn get importSourceType => text().nullable()();

  /// 用户导入来源 URL。直链导入记录原始 URL；本地文件导入保持 NULL。
  TextColumn get importSourceUrl => text().nullable()();

  // ── Podcast Episode 字段（podcast 合集的音频条目时有效）──────────────────

  /// Podcast episode 的 RSS guid；用于同一合集内去重。
  /// 无 guid 的 episode 不导入。
  TextColumn get podcastEpisodeGuid => text().nullable()();

  /// Episode 音频文件的 enclosure URL（RSS `<enclosure url="...">`）
  TextColumn get podcastEnclosureUrl => text().nullable()();

  /// Enclosure MIME type，如 audio/mpeg
  TextColumn get podcastEnclosureType => text().nullable()();

  /// Episode 简介文本，来自 RSS item description。
  TextColumn get podcastDescription => text().nullable()();

  /// Episode 封面图 URL，来自 RSS item itunes:image。
  TextColumn get podcastImageUrl => text().nullable()();

  /// Episode 网页链接，来自 RSS item link。
  TextColumn get podcastLink => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
