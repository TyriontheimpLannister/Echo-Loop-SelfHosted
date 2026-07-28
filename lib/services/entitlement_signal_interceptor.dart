/// Dio 拦截器：读取后端权益信号响应头（E6）。
///
/// 后端在计费 AI / 转录等端点的响应上附 `x-entitlement-active: 1|0`
/// （服务端当前权益视图，webhook 落库即变化）。拦截器把信号转发给订阅层，
/// 订阅层与本地权益 state 比对，不一致即回源对账——使 Paddle 退款、到期等
/// 服务端已知的变化在用户正常使用功能时被及时发现，无需轮询。
///
/// 由 [createBackendDio] 统一安装（零额外网络请求）；信号处理器由订阅层
/// 在 controller 构建时注册，未注册（或订阅栈未初始化）时信号被安全忽略。
library;

import 'package:dio/dio.dart';

/// 后端权益信号响应头名。
const entitlementActiveHeader = 'x-entitlement-active';

/// 从后端响应头提取权益信号并转发给订阅层。
class EntitlementSignalInterceptor extends Interceptor {
  /// 全局信号回调（由 SubscriptionController 注册；谁注册谁负责解除）。
  ///
  /// 用静态回调而非依赖注入：backend Dio 在众多无 ref 的 service 构造器中创建，
  /// 逐层穿参会污染全部构造签名；信号本身是幂等提示（比对不一致才动作），
  /// 丢失或重复均无害。
  static void Function({required bool serverActive, required String path})?
  onSignal;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _emit(response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 402/403 等错误响应同样携带信号头（如免费用户额度用尽时 server=0）。
    final response = err.response;
    if (response != null) _emit(response);
    handler.next(err);
  }

  void _emit(Response response) {
    final value = response.headers.value(entitlementActiveHeader);
    if (value != '1' && value != '0') return;
    onSignal?.call(
      serverActive: value == '1',
      path: response.requestOptions.path,
    );
  }
}
