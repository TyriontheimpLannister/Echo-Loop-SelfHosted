import 'package:echo_loop/features/subscription/services/purchase_service.dart';
import 'package:echo_loop/features/subscription/services/revenuecat_purchase_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('restore 错误码映射', () {
    const channel = MethodChannel('purchases_flutter');

    /// 让 restorePurchases 抛出指定 RC 错误码的 [PlatformException]。
    void mockRestoreError(PurchasesErrorCode code) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'restorePurchases') {
              throw PlatformException(
                code: code.index.toString(),
                message: 'mock ${code.name}',
              );
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
    }

    test('receiptAlreadyInUseError → PurchaseException.receiptInUse', () async {
      mockRestoreError(PurchasesErrorCode.receiptAlreadyInUseError);
      await expectLater(
        RevenueCatPurchaseService().restore(),
        throwsA(
          isA<PurchaseException>()
              .having((e) => e.receiptInUse, 'receiptInUse', isTrue)
              .having((e) => e.cancelled, 'cancelled', isFalse),
        ),
      );
    });

    test('purchaseCancelledError → PurchaseException.cancelled', () async {
      mockRestoreError(PurchasesErrorCode.purchaseCancelledError);
      await expectLater(
        RevenueCatPurchaseService().restore(),
        throwsA(
          isA<PurchaseException>()
              .having((e) => e.cancelled, 'cancelled', isTrue)
              .having((e) => e.receiptInUse, 'receiptInUse', isFalse),
        ),
      );
    });
  });

  group('RevenueCat CustomerInfo 诊断日志', () {
    test('摘要包含权益裁决关键字段', () {
      final entitlement = EntitlementInfo(
        'pro',
        true,
        true,
        '2026-07-15T01:00:00Z',
        '2026-07-01T01:00:00Z',
        'pro_monthly',
        true,
        store: Store.appStore,
        periodType: PeriodType.normal,
        expirationDate: '2026-08-11T01:00:00Z',
        productPlanIdentifier: 'base-monthly',
      );
      final info = CustomerInfo(
        EntitlementInfos({'pro': entitlement}, {'pro': entitlement}),
        const {'pro_monthly': '2026-07-15T01:00:00Z'},
        const ['pro_monthly'],
        const ['pro_monthly'],
        const [],
        '2026-07-01T00:00:00Z',
        'user_123',
        const {'pro_monthly': '2026-08-11T01:00:00Z'},
        '2026-07-15T01:02:03Z',
        latestExpirationDate: '2026-08-11T01:00:00Z',
        managementURL: 'https://apps.apple.com/account/subscriptions',
      );

      final summary = revenueCatCustomerInfoSummary(
        info,
        lookForEntitlementId: 'pro',
        stage: 'currentEntitlement',
      );

      expect(summary, contains('CustomerInfo[currentEntitlement]'));
      expect(summary, contains('originalAppUserId=user_123'));
      expect(summary, contains('lookFor=pro'));
      expect(summary, contains('activeEntitlements=[pro]'));
      expect(summary, contains('productIdentifier=pro_monthly'));
      expect(summary, contains('productPlanIdentifier=base-monthly'));
      expect(summary, contains('expirationDate=2026-08-11T01:00:00Z'));
      expect(summary, contains('willRenew=true'));
      expect(summary, contains('activeSubs=[pro_monthly]'));
      expect(summary, contains('latestExpirationDate=2026-08-11T01:00:00Z'));
    });

    test('快照包含 debug 页面需要展示的 entitlement 明细', () {
      final entitlement = EntitlementInfo(
        'pro',
        true,
        false,
        '2026-07-15T01:00:00Z',
        '2026-07-01T01:00:00Z',
        'pro_yearly',
        false,
        store: Store.playStore,
        periodType: PeriodType.trial,
        expirationDate: '2026-08-11T01:00:00Z',
        unsubscribeDetectedAt: '2026-07-20T01:00:00Z',
        billingIssueDetectedAt: '2026-07-21T01:00:00Z',
      );

      final snapshot = revenueCatEntitlementInfoSnapshot(entitlement);

      expect(snapshot['identifier'], 'pro');
      expect(snapshot['isActive'], isTrue);
      expect(snapshot['willRenew'], isFalse);
      expect(snapshot['productIdentifier'], 'pro_yearly');
      expect(snapshot['expirationDate'], '2026-08-11T01:00:00Z');
      expect(snapshot['unsubscribeDetectedAt'], '2026-07-20T01:00:00Z');
      expect(snapshot['billingIssueDetectedAt'], '2026-07-21T01:00:00Z');
      expect(snapshot['store'], 'playStore');
      expect(snapshot['periodType'], 'trial');
    });
  });
}
