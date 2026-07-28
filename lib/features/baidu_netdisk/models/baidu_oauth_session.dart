/// 百度 OAuth 授权会话模型。
///
/// 会话由自家后端创建，App 只持有一次性轮询凭证并通过浏览器打开授权 URL。
library;

/// App 支持的百度授权平台值。
enum BaiduNetdiskPlatform {
  /// iOS。
  ios('ios'),

  /// Android。
  android('android'),

  /// macOS。
  macos('macos'),

  /// Windows。
  windows('windows'),

  /// Linux。
  linux('linux');

  const BaiduNetdiskPlatform(this.wireName);

  /// 后端协议使用的平台字符串。
  final String wireName;

  /// 从字符串安全映射为平台。
  static BaiduNetdiskPlatform fromWireName(Object? value) {
    if (value is! String) {
      throw const FormatException('platform 非法');
    }
    for (final platform in BaiduNetdiskPlatform.values) {
      if (platform.wireName == value) return platform;
    }
    throw const FormatException('platform 非法');
  }
}

/// 后端创建的 OAuth 授权会话。
class BaiduOAuthSession {
  /// 构造授权会话。
  const BaiduOAuthSession({
    required this.sessionId,
    required this.pollToken,
    required this.authorizationUri,
    required this.expiresAt,
    required this.pollInterval,
  });

  /// 不透明会话 ID。
  final String sessionId;

  /// 一次性轮询凭证，只保存在客户端内存。
  final String pollToken;

  /// 系统浏览器要打开的百度授权地址。
  final Uri authorizationUri;

  /// 会话过期时间（UTC）。
  final DateTime expiresAt;

  /// 服务端建议轮询间隔。
  final Duration pollInterval;

  /// 从后端响应解析授权会话。
  factory BaiduOAuthSession.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('OAuth session 必须是对象');
    }
    final sessionId = json['sessionId'];
    final pollToken = json['pollToken'];
    final authorizationUrl = json['authorizationUrl'];
    final rawExpiresAt = json['expiresAt'];
    final rawPollInterval = json['pollIntervalSeconds'];
    if (sessionId is! String || sessionId.isEmpty) {
      throw const FormatException('sessionId 非法');
    }
    if (pollToken is! String || pollToken.isEmpty) {
      throw const FormatException('pollToken 非法');
    }
    if (authorizationUrl is! String || authorizationUrl.isEmpty) {
      throw const FormatException('authorizationUrl 非法');
    }
    final uri = Uri.tryParse(authorizationUrl);
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('authorizationUrl 非法');
    }
    if (rawExpiresAt is! String) {
      throw const FormatException('expiresAt 非法');
    }
    final expiresAt = DateTime.tryParse(rawExpiresAt);
    if (expiresAt == null) {
      throw const FormatException('expiresAt 非法');
    }
    if (rawPollInterval is! int || rawPollInterval < 1) {
      throw const FormatException('pollIntervalSeconds 非法');
    }
    return BaiduOAuthSession(
      sessionId: sessionId,
      pollToken: pollToken,
      authorizationUri: uri,
      expiresAt: expiresAt.toUtc(),
      pollInterval: Duration(seconds: rawPollInterval),
    );
  }
}
