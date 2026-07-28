/// 自家后端请求的统一 Dio 工厂。
///
/// **凡是请求自家后端（[apiBaseUrl]）的 Dio 都应经此工厂创建**，工厂自动把
/// client-info 公共 header（`x-app-platform` / `x-app-distribution` / `x-app-version`）
/// 写入 [BaseOptions.headers]，使平台/渠道标识随该 Dio 的每个请求上送——后端据此按
/// 「平台+渠道」组合决定 AI 免费额度等策略（见 docs/subscription-setup.md）。
///
/// 好处：header 注入集中一处，新增后端 client 无需再手写，杜绝「漏带渠道 header」。
///
/// **不得**用于外部主机请求（R2 presigned 上传、CDN 模型/资源下载、播客 RSS、
/// App Store Lookup 等）——那些请求不应携带自家标识 header。此类请求继续裸构造 `Dio`，
/// 或（如 [AppUpdateChecker] 那种同一 Dio 混打后端与外部主机的场景）改用 per-request
/// [Options.headers] 只在打后端的那个请求上带 [clientInfoHeaders]。
library;

import 'package:dio/dio.dart';

import 'api_log_interceptor.dart';
import 'client_info.dart';
import 'entitlement_signal_interceptor.dart';

/// 构造一个已注入 client-info 公共 header 的后端 Dio。
///
/// 统一安装 [ApiLogInterceptor]；Geo、HTTP2 等差异化能力仍由各 client 追加。
///
/// [baseUrl] 为空时表示各请求用完整 URL（header 仍随每个请求上送，故仅用于纯后端 Dio）。
/// [appVersion] 为空/null 时省略版本 header（降级不阻断，见 [clientInfoHeaders]）。
Dio createBackendDio({
  String baseUrl = '',
  String? appVersion,
  Duration connectTimeout = const Duration(seconds: 15),
  Duration receiveTimeout = const Duration(seconds: 30),
  String apiLogTag = 'BACKEND',
  void Function(String message)? apiLogPrint,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      headers: clientInfoHeaders(appVersion: appVersion),
    ),
  );
  dio.interceptors.add(
    ApiLogInterceptor(tag: apiLogTag, logPrint: apiLogPrint),
  );
  // E6：读取权益信号响应头，服务端权益变化（退款/到期）时提示订阅层回源对账。
  dio.interceptors.add(EntitlementSignalInterceptor());
  return dio;
}
