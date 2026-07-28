import 'package:echo_loop/features/baidu_netdisk/services/baidu_oauth_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  group('UrlLauncherBaiduOAuthLauncher', () {
    test('iOS 优先 inAppBrowserView，成功后不再打开外部浏览器', () async {
      final calls = <LaunchMode>[];
      final launcher = UrlLauncherBaiduOAuthLauncher(
        platform: TargetPlatform.iOS,
        launch: (uri, mode) async {
          calls.add(mode);
          return true;
        },
      );

      await launcher.open(Uri.parse('https://openapi.baidu.com/oauth'));

      expect(calls, [LaunchMode.inAppBrowserView]);
    });

    test('Android inAppBrowserView 失败时回退 externalApplication', () async {
      final calls = <LaunchMode>[];
      final launcher = UrlLauncherBaiduOAuthLauncher(
        platform: TargetPlatform.android,
        launch: (uri, mode) async {
          calls.add(mode);
          return mode == LaunchMode.externalApplication;
        },
      );

      await launcher.open(Uri.parse('https://openapi.baidu.com/oauth'));

      expect(calls, [
        LaunchMode.inAppBrowserView,
        LaunchMode.externalApplication,
      ]);
    });

    test('桌面端直接使用 externalApplication', () async {
      final calls = <LaunchMode>[];
      final launcher = UrlLauncherBaiduOAuthLauncher(
        platform: TargetPlatform.macOS,
        launch: (uri, mode) async {
          calls.add(mode);
          return true;
        },
      );

      await launcher.open(Uri.parse('https://openapi.baidu.com/oauth'));

      expect(calls, [LaunchMode.externalApplication]);
    });

    test('所有打开方式失败时抛错', () async {
      final launcher = UrlLauncherBaiduOAuthLauncher(
        platform: TargetPlatform.android,
        launch: (uri, mode) async => false,
      );

      expect(
        launcher.open(Uri.parse('https://openapi.baidu.com/oauth')),
        throwsStateError,
      );
    });
  });
}
