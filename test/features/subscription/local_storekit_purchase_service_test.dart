/// 本地 StoreKit 购买服务的纯映射逻辑单测。
///
/// 不触达 `in_app_purchase` 平台通道（那部分需真机/StoreKit 环境，无法单测），
/// 仅覆盖可纯函数化的核心映射：商品 ID → 周期 / 试用天数、活跃订阅 → Entitlement。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mocktail/mocktail.dart';
import 'package:echo_loop/features/subscription/models/entitlement.dart';
import 'package:echo_loop/features/subscription/models/subscription_plan.dart';
import 'package:echo_loop/features/subscription/services/local_storekit_purchase_service.dart';

class _MockInAppPurchase extends Mock implements InAppPurchase {}

class _FakePurchaseDetails extends Fake implements PurchaseDetails {}

/// 构造一条购买流回执（用于驱动 `_onPurchaseUpdates`）。
PurchaseDetails _purchase({
  required String productId,
  required String? purchaseId,
  required PurchaseStatus status,
  bool pendingComplete = true,
}) {
  return PurchaseDetails(
    purchaseID: purchaseId,
    productID: productId,
    status: status,
    transactionDate: null,
    verificationData: PurchaseVerificationData(
      localVerificationData: '',
      serverVerificationData: '',
      source: 'app_store',
    ),
  )..pendingCompletePurchase = pendingComplete;
}

void main() {
  group('localPlanPeriod', () {
    test('年付商品映射为 yearly', () {
      expect(
        localPlanPeriod(echoLoopAnnualProductId),
        SubscriptionPeriod.yearly,
      );
    });

    test('月付商品映射为 monthly', () {
      expect(
        localPlanPeriod(echoLoopMonthlyProductId),
        SubscriptionPeriod.monthly,
      );
    });

    test('未知商品默认 monthly（容错）', () {
      expect(localPlanPeriod('unknown_product'), SubscriptionPeriod.monthly);
    });
  });

  group('localPlanTrialDays', () {
    test('年付含 7 天试用（与 .storekit introductoryOffer 一致）', () {
      expect(localPlanTrialDays(echoLoopAnnualProductId), 7);
    });

    test('月付无试用', () {
      expect(localPlanTrialDays(echoLoopMonthlyProductId), 0);
    });
  });

  group('localEntitlementFromActiveIds', () {
    const entitlementId = 'Echo Loop Plus';

    test('无活跃订阅返回 free', () {
      final ent = localEntitlementFromActiveIds(
        const {},
        entitlementId: entitlementId,
      );
      expect(ent, Entitlement.free);
      expect(ent.isPremium, isFalse);
    });

    test('有月付订阅返回 pro，挂到 entitlement', () {
      final ent = localEntitlementFromActiveIds(const {
        echoLoopMonthlyProductId,
      }, entitlementId: entitlementId);
      expect(ent.isPremium, isTrue);
      expect(ent.productId, echoLoopMonthlyProductId);
      expect(ent.activeEntitlements, {entitlementId});
      expect(ent.willRenew, isTrue);
    });

    test('同时有月付与年付时，年付优先作为代表商品', () {
      final ent = localEntitlementFromActiveIds(const {
        echoLoopMonthlyProductId,
        echoLoopAnnualProductId,
      }, entitlementId: entitlementId);
      expect(ent.isPremium, isTrue);
      expect(ent.productId, echoLoopAnnualProductId);
    });

    test('expiresAt 为空 → 视为持续有效（由 Xcode 删交易控制）', () {
      final ent = localEntitlementFromActiveIds(const {
        echoLoopAnnualProductId,
      }, entitlementId: entitlementId);
      expect(ent.expiresAt, isNull);
      expect(ent.isActive(DateTime.now()), isTrue);
    });
  });

  group('购买流回执（防 SK2 null purchaseID 崩溃）', () {
    late _MockInAppPurchase iap;
    late StreamController<List<PurchaseDetails>> stream;

    setUpAll(() => registerFallbackValue(_FakePurchaseDetails()));

    setUp(() {
      iap = _MockInAppPurchase();
      stream = StreamController<List<PurchaseDetails>>.broadcast();
      when(() => iap.purchaseStream).thenAnswer((_) => stream.stream);
      when(() => iap.restorePurchases()).thenAnswer((_) async {});
      when(() => iap.completePurchase(any())).thenAnswer((_) async {});
    });

    tearDown(() => stream.close());

    test('purchaseID 为 null 时跳过回执，不调用 completePurchase（不崩溃）', () async {
      LocalStoreKitPurchaseService(iap: iap);
      stream.add([
        _purchase(
          productId: echoLoopAnnualProductId,
          purchaseId: null,
          status: PurchaseStatus.canceled,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      verifyNever(() => iap.completePurchase(any()));
    });

    test('purchaseID 有效时正常回执', () async {
      LocalStoreKitPurchaseService(iap: iap);
      stream.add([
        _purchase(
          productId: echoLoopMonthlyProductId,
          purchaseId: '1000000123',
          status: PurchaseStatus.purchased,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      verify(() => iap.completePurchase(any())).called(1);
    });

    test('completePurchase 抛错被兜住，不向上冒泡', () async {
      when(
        () => iap.completePurchase(any()),
      ).thenThrow(Exception('plugin boom'));
      LocalStoreKitPurchaseService(iap: iap);
      stream.add([
        _purchase(
          productId: echoLoopMonthlyProductId,
          purchaseId: '1000000123',
          status: PurchaseStatus.purchased,
        ),
      ]);
      // 不抛异常即通过（错误被 _completePurchaseSafely 捕获并记日志）。
      await Future<void>.delayed(Duration.zero);
      verify(() => iap.completePurchase(any())).called(1);
    });
  });

  group('restore 重建活跃集合（退订后降级，无需重启）', () {
    late _MockInAppPurchase iap;
    late StreamController<List<PurchaseDetails>> stream;

    setUpAll(() => registerFallbackValue(_FakePurchaseDetails()));

    setUp(() {
      iap = _MockInAppPurchase();
      stream = StreamController<List<PurchaseDetails>>.broadcast();
      when(() => iap.purchaseStream).thenAnswer((_) => stream.stream);
      when(() => iap.completePurchase(any())).thenAnswer((_) async {});
    });

    tearDown(() => stream.close());

    test('已取消/过期订阅不再投递 → restore 后降级为 free', () async {
      // restorePurchases 不投递任何 restored 回执（模拟订阅已失效）。
      when(() => iap.restorePurchases()).thenAnswer((_) async {});
      final service = LocalStoreKitPurchaseService(
        iap: iap,
        restoreSettleDelay: Duration.zero,
      );
      // 先模拟之前已购买（活跃集合含月订）。
      stream.add([
        _purchase(
          productId: echoLoopMonthlyProductId,
          purchaseId: '1000000123',
          status: PurchaseStatus.purchased,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect((await service.currentEntitlement()).isPremium, isTrue);

      // 退订后 restore：先清空、restorePurchases 不再投递 → 收敛为 free。
      final ent = (await service.restore()).entitlement;
      expect(ent.isPremium, isFalse);
    });

    test('仍有效订阅会被重新投递 → restore 后保持 pro', () async {
      // restorePurchases 同步投递一条有效月订回执（模拟订阅仍生效）。
      when(() => iap.restorePurchases()).thenAnswer((_) async {
        stream.add([
          _purchase(
            productId: echoLoopMonthlyProductId,
            purchaseId: '1000000123',
            status: PurchaseStatus.restored,
          ),
        ]);
      });
      final service = LocalStoreKitPurchaseService(
        iap: iap,
        restoreSettleDelay: Duration.zero,
      );
      final ent = (await service.restore()).entitlement;
      expect(ent.isPremium, isTrue);
      expect(ent.productId, echoLoopMonthlyProductId);
    });
  });
}
