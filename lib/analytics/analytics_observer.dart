/// GoRouter NavigatorObserver — 自动采集 screen_view 事件
///
/// 全屏路由（学习页面、播放器等）的页面切换由此 Observer 自动采集。
/// StatefulShellRoute 的 Tab 切换不经过 Navigator，需在 Tab 切换回调中
/// 手动调用 [AnalyticsService.track]。
library;

import 'package:flutter/material.dart';

import 'analytics_service.dart';
import 'models/event_names.dart';
import '../services/app_logger.dart';

/// 页面浏览事件观察者
///
/// 在 GoRouter 的 `observers` 列表中注册即可自动采集
/// push/replace 产生的 screen_view 事件。
class AnalyticsObserver extends NavigatorObserver {
  final AnalyticsService _analytics;

  /// 上一个页面名称，用于 previous_screen 参数
  String? _previousScreen;

  AnalyticsObserver(this._analytics);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _logNavigationAction('didPush', route, previousRoute);
    _trackScreenView(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      _logNavigationAction('didReplace', newRoute, oldRoute);
      _trackScreenView(newRoute);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _logNavigationAction('didPop', route, previousRoute);
    if (previousRoute != null) {
      _trackScreenView(previousRoute);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _logNavigationAction('didRemove', route, previousRoute);
  }

  /// 打印 Navigator 层动作，配合 GoRouter path 日志判断是否发生双 pop。
  void _logNavigationAction(
    String action,
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    AppLogger.log(
      'Navigation',
      '$action route=${_routeName(route)} previous=${_routeName(previousRoute)}',
    );
  }

  static String _routeName(Route<dynamic>? route) =>
      route?.settings.name ?? '(null)';

  /// 提取路由名称并上报 screen_view 事件
  void _trackScreenView(Route<dynamic> route) {
    final screenName = _extractScreenName(route);
    if (screenName == null) return;

    _analytics.track(Events.screenView, {
      EventParams.screenName: screenName,
      if (_previousScreen != null) EventParams.previousScreen: _previousScreen!,
    });
    _previousScreen = screenName;
  }

  /// 从路由中提取页面名称
  ///
  /// 优先使用 RouteSettings.name，其次从路由路径中提取。
  /// 路径中的动态参数（UUID 等）被去除，只保留结构性路径段。
  static String? _extractScreenName(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name == '/') return null;

    // 去除路径中的 UUID 参数，只保留结构性路径段
    // 例如 /collections/abc-123/def-456/blind-listen → blind-listen
    final segments = name.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    // 返回最后一个非参数段作为 screen name
    // 常见的参数段是 UUID 格式、纯数字或 GoRouter 模板变量
    for (var i = segments.length - 1; i >= 0; i--) {
      if (!_isParameterSegment(segments[i])) {
        return segments[i];
      }
    }
    // 所有段都是参数（如纯 `:collectionId`），跳过此路由
    return null;
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static final _numericPattern = RegExp(r'^\d+$');

  /// 判断路径段是否为动态参数（UUID、纯数字、GoRouter 模板变量）
  static bool _isParameterSegment(String segment) {
    // GoRouter 模板参数，如 :collectionId, :audioId
    if (segment.startsWith(':')) return true;
    // UUID 格式：8-4-4-4-12 hex
    if (_uuidPattern.hasMatch(segment)) return true;
    // 纯数字（时间戳 ID 等）
    if (_numericPattern.hasMatch(segment)) return true;
    return false;
  }
}
