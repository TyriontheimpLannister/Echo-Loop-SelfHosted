/// 上报通道抽象接口（Strategy Pattern）
///
/// 业务代码只依赖此接口；家庭版实现不会连接第三方分析平台。
/// 自托管家庭版使用本地 [LogOnlyChannel] 实现。
library;

/// 分析上报通道
///
/// [AnalyticsService] 持有一个 Channel 实例，将事件转发到此接口。
abstract class AnalyticsChannel {
  /// 通道名称（用于日志和调试）
  String get name;

  /// 初始化通道（如 SDK 初始化）
  Future<void> initialize();

  /// 记录事件
  ///
  /// [name] 事件名（使用 [Events] 常量）。
  /// [parameters] 事件属性，值只允许 String/int/double/bool。
  Future<void> logEvent(String name, Map<String, Object>? parameters);

  /// 设置用户 ID（匿名 ID 或登录后的真实 ID）
  Future<void> setUserId(String? id);

  /// 设置用户属性
  Future<void> setUserProperty(String name, String? value);

  /// 注册 super properties（事件级冻结属性）。
  ///
  /// 调用后，本地 SDK 之后发出的所有事件都会自动附加这些属性，
  /// 值在事件发出时被冻结，不会被未来覆盖。
  /// 家庭版的 LogOnly 实现仅写入本地日志。
  ///
  /// 与 [setUserProperty] 的区别：
  /// - super property 写到事件上，可查"事件发生时的状态"
  /// - user property 写到用户画像，覆盖式更新，查"用户当前状态"
  ///
  /// [properties] 的 value 只允许 String/int/double/bool。
  Future<void> registerSuperProperties(Map<String, Object> properties);

  /// 注销 super property。
  ///
  /// LogOnly 通道只更新本地诊断日志。
  Future<void> unregisterSuperProperty(String name);
}
