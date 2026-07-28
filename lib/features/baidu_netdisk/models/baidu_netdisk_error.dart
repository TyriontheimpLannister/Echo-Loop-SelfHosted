/// 百度网盘导入链路的错误分类。
///
/// 当前任务只落 OAuth 基础设施，后续文件列表、下载与入库会继续复用这些错误码，
/// 避免 UI 根据原始异常字符串做分支。
library;

/// 后端 OAuth 协议定义的错误码。
enum BaiduNetdiskOAuthErrorCode {
  /// 百度配置缺失。
  baiduNotConfigured('baidu_not_configured'),

  /// 授权会话无效。
  oauthSessionInvalid('oauth_session_invalid'),

  /// 授权会话过期。
  oauthSessionExpired('oauth_session_expired'),

  /// 用户取消授权。
  oauthCanceled('oauth_canceled'),

  /// 授权码交换失败。
  tokenExchangeFailed('token_exchange_failed'),

  /// 返回 scope 缺少基础或网盘权限。
  scopeMissing('scope_missing'),

  /// refresh token 已不可用，需要重新授权。
  reauthorizationRequired('reauthorization_required'),

  /// 服务端限流。
  rateLimited('rate_limited'),

  /// 客户端无法识别的新错误码。
  unknown('unknown');

  const BaiduNetdiskOAuthErrorCode(this.wireName);

  /// 后端 JSON 中使用的稳定字符串。
  final String wireName;

  /// 从后端字符串安全映射为枚举。
  static BaiduNetdiskOAuthErrorCode fromWireName(Object? value) {
    if (value is! String) return BaiduNetdiskOAuthErrorCode.unknown;
    for (final code in BaiduNetdiskOAuthErrorCode.values) {
      if (code.wireName == value) return code;
    }
    return BaiduNetdiskOAuthErrorCode.unknown;
  }
}

/// 后端统一错误体中的业务错误。
class BaiduNetdiskApiError implements Exception {
  /// 构造后端业务错误。
  const BaiduNetdiskApiError({required this.code, required this.message});

  /// 错误码。
  final BaiduNetdiskOAuthErrorCode code;

  /// 可展示或记录的非敏感错误信息。
  final String message;

  @override
  String toString() => 'BaiduNetdiskApiError(${code.wireName}, $message)';
}
