import 'package:echo_loop/features/subscription/services/subscription_management_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('googlePlaySubscriptionManagementUris', () {
    test('有商品 ID 时优先打开 Play Store 订阅详情，再回退 HTTPS', () {
      final uris = googlePlaySubscriptionManagementUris(
        packageName: 'app.echoloop',
        productId: 'echo_loop_plus_monthly',
      );

      expect(uris, hasLength(2));
      expect(uris.first.scheme, 'market');
      expect(uris.first.host, 'subscriptions');
      expect(uris.first.queryParameters, {
        'sku': 'echo_loop_plus_monthly',
        'package': 'app.echoloop',
      });
      expect(
        uris.last.toString(),
        'https://play.google.com/store/account/subscriptions'
        '?sku=echo_loop_plus_monthly&package=app.echoloop',
      );
    });

    test('无商品 ID 时打开订阅列表', () {
      final uris = googlePlaySubscriptionManagementUris(
        packageName: 'app.echoloop.dev',
      );

      expect(uris.map((uri) => uri.toString()), [
        'market://subscriptions',
        'https://play.google.com/store/account/subscriptions',
      ]);
    });
  });
}
