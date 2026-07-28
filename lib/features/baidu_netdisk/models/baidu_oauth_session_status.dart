/// 百度 OAuth 授权会话状态模型。
library;

import 'baidu_credential_bundle.dart';
import 'baidu_netdisk_error.dart';

/// 后端 OAuth 会话状态。
enum BaiduOAuthSessionPhase {
  /// 等待用户在浏览器中授权。
  pending('pending'),

  /// 后端正在交换授权码。
  exchanging('exchanging'),

  /// 已完成，响应中包含临时 credential。
  completed('completed'),

  /// 用户取消授权。
  canceled('canceled'),

  /// 授权失败。
  failed('failed');

  const BaiduOAuthSessionPhase(this.wireName);

  /// 后端协议中的状态字符串。
  final String wireName;

  /// 从后端字符串解析状态。
  static BaiduOAuthSessionPhase fromWireName(Object? value) {
    if (value is! String) {
      throw const FormatException('status 非法');
    }
    for (final phase in BaiduOAuthSessionPhase.values) {
      if (phase.wireName == value) return phase;
    }
    throw const FormatException('status 非法');
  }
}

/// 授权状态查询结果。
class BaiduOAuthSessionStatus {
  /// 构造授权状态。
  const BaiduOAuthSessionStatus({
    required this.phase,
    this.credential,
    this.error,
  });

  /// 当前状态。
  final BaiduOAuthSessionPhase phase;

  /// completed 时的临时 credential。
  final BaiduCredentialBundle? credential;

  /// failed/canceled 时可选的错误。
  final BaiduNetdiskApiError? error;

  /// 从后端状态响应解析。
  factory BaiduOAuthSessionStatus.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('OAuth status 必须是对象');
    }
    final phase = BaiduOAuthSessionPhase.fromWireName(json['status']);
    final rawCredential = json['credential'];
    final credential = rawCredential == null
        ? null
        : BaiduCredentialBundle.fromJson(rawCredential);
    final rawError = json['error'];
    final error = rawError is Map
        ? BaiduNetdiskApiError(
            code: BaiduNetdiskOAuthErrorCode.fromWireName(rawError['code']),
            message: rawError['message'] is String
                ? rawError['message'] as String
                : '',
          )
        : null;
    if (phase == BaiduOAuthSessionPhase.completed && credential == null) {
      throw const FormatException('completed 缺少 credential');
    }
    return BaiduOAuthSessionStatus(
      phase: phase,
      credential: credential,
      error: error,
    );
  }
}
