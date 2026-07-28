/// 百度 OAuth 浏览器启动器。
///
/// 移动端优先使用系统安全浏览器容器，失败后回退系统浏览器；桌面端直接使用
/// 系统默认浏览器。浏览器关闭不代表取消，授权状态由 Controller 后续轮询决定。
library;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 打开百度授权页的抽象。
abstract interface class BaiduOAuthLauncher {
  /// 打开授权 URL。
  Future<void> open(Uri authorizationUri);
}

/// 基于 url_launcher 的实现。
class UrlLauncherBaiduOAuthLauncher implements BaiduOAuthLauncher {
  /// 构造浏览器启动器。
  const UrlLauncherBaiduOAuthLauncher({
    TargetPlatform? platform,
    Future<bool> Function(Uri uri, LaunchMode mode)? launch,
  }) : _platform = platform,
       _launch = launch;

  final TargetPlatform? _platform;
  final Future<bool> Function(Uri uri, LaunchMode mode)? _launch;

  TargetPlatform get _effectivePlatform => _platform ?? defaultTargetPlatform;

  @override
  Future<void> open(Uri authorizationUri) async {
    if (_isMobile(_effectivePlatform)) {
      final openedInBrowserView = await _tryLaunch(
        authorizationUri,
        LaunchMode.inAppBrowserView,
      );
      if (openedInBrowserView) return;
    }
    final openedExternally = await _tryLaunch(
      authorizationUri,
      LaunchMode.externalApplication,
    );
    if (!openedExternally) {
      throw StateError('无法打开百度授权页面。');
    }
  }

  Future<bool> _tryLaunch(Uri uri, LaunchMode mode) async {
    try {
      final launch = _launch;
      if (launch != null) {
        return launch(uri, mode);
      }
      return launchUrl(uri, mode: mode);
    } catch (_) {
      return false;
    }
  }

  bool _isMobile(TargetPlatform platform) {
    return platform == TargetPlatform.iOS || platform == TargetPlatform.android;
  }
}
