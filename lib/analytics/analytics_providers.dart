/// 分析系统 Riverpod Provider 注册
///
/// 参考 [appDatabaseProvider] 的模式：在 `main()` 中提前初始化，
/// Provider 同步暴露。业务代码通过 `ref.read(analyticsServiceProvider)`
/// 获取 [AnalyticsService] 实例。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';
import 'channels/log_only_channel.dart';
import 'consent_manager.dart';

/// 分析服务单例（在 main() 中通过 [initAnalyticsService] 初始化）
late AnalyticsService _analyticsService;

/// 初始化分析服务（在 main() 中 runApp 之前调用）
void initAnalytics(AnalyticsService service) {
  _analyticsService = service;
}

/// 分析服务 Provider（同步，与 appDatabaseProvider 模式一致）
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return _analyticsService;
});

/// 初始化分析服务
///
/// [userId] 由 [initUserIdService] 提前生成，analytics 不负责 ID 管理。
///
/// 自托管家庭版只保留本地日志通道，不初始化或上传到第三方分析服务。
Future<AnalyticsService> initAnalyticsService(
  SharedPreferences prefs, {
  required String userId,
}) async {
  final consent = ConsentManager(prefs);
  final channel = LogOnlyChannel();

  await channel.initialize();
  await channel.registerSuperProperties({'app_anonymous_id': userId});

  return AnalyticsService(channel: channel, consent: consent);
}
