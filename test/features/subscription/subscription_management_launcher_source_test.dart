import 'package:echo_loop/features/subscription/models/entitlement_source.dart';
import 'package:echo_loop/features/subscription/services/subscription_management_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// [SubscriptionManagementLauncher.open] 按订阅**来源**分发的单测。
///
/// 测试在 host（非 iOS / 非 Android）运行，因此 apple/google 来源都会走
/// 「跨平台网页回退」分支——正是「Apple 订阅在非 Apple 平台、Google 订阅在
/// 非 Android 平台登录同账号」时应打开对应商店网页管理页的目标场景。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Uri> opened;

  SubscriptionManagementLauncher build() => SubscriptionManagementLauncher(
    launchUrl: (uri, mode) async {
      opened.add(uri);
      return true;
    },
    channel: const MethodChannel('test/subscription_management_noop'),
    packageInfoLoader: () async => PackageInfo(
      appName: 'Echo Loop',
      packageName: 'top.echo-loop',
      version: '1.0.0',
      buildNumber: '1',
    ),
  );

  setUp(() => opened = []);

  test('apple 来源在非 Apple 平台 → 打开 Apple 网页订阅管理页', () async {
    final ok = await build().open(source: EntitlementSource.apple);
    expect(ok, isTrue);
    expect(
      opened.single.toString(),
      'https://apps.apple.com/account/subscriptions',
    );
  });

  test('google 来源在非 Android 平台 → 打开 Play 网页订阅管理页', () async {
    final ok = await build().open(
      source: EntitlementSource.google,
      productId: 'echo_loop_plus_monthly',
    );
    expect(ok, isTrue);
    expect(opened.single.host, 'play.google.com');
    expect(opened.single.path, '/store/account/subscriptions');
  });

  test('paddle 来源不经 launcher（返回 false，交上层走 Customer Portal）', () async {
    final ok = await build().open(source: EntitlementSource.paddle);
    expect(ok, isFalse);
    expect(opened, isEmpty);
  });
}
