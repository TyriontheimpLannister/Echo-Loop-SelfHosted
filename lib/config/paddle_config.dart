/// Direct 渠道 Paddle 配置。
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'client_distribution.dart';
import 'api_config.dart';

@visibleForTesting
bool? debugIsPaddleCheckoutChannelOverride;

/// direct 构建使用后端 Paddle API；Play/App Store 构建不会进入该分支。
bool get isPaddleCheckoutConfigured =>
    isPaddleCheckoutChannel && isPaddleBackendConfigured;

/// Paddle 后端 API 是否具备基础配置；商店包 Web 支付兜底只需要该后端可用，
/// 不要求当前默认支付渠道已经是 direct/Web。
bool get isPaddleBackendConfigured => apiBaseUrl.trim().isNotEmpty;

bool get isPaddleCheckoutChannel {
  final override = debugIsPaddleCheckoutChannelOverride;
  if (override != null) return override;
  return clientPaymentChannel == ClientPaymentChannel.web;
}
