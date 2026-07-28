/// Direct 渠道 Paddle 购买服务。
library;

import '../models/entitlement.dart';
import '../models/subscription_plan.dart';
import '../../../services/app_logger.dart';
import 'paddle_billing_repository.dart';
import 'purchase_service.dart';

/// 将 Paddle plans 接入现有 PurchaseService 契约，同时禁止误走 native purchase。
class PaddlePurchaseService implements PurchaseService {
  PaddlePurchaseService({
    required PaddleBillingRepository repository,
    required String? Function() accessToken,
  }) : _repository = repository,
       _accessToken = accessToken;

  final PaddleBillingRepository _repository;
  final String? Function() _accessToken;
  List<SubscriptionPlan>? _latestPlans;

  @override
  Future<List<SubscriptionPlan>> fetchPlans({
    bool includeIntroEligibility = true,
  }) async {
    final cached = _latestPlans;
    if (includeIntroEligibility && cached != null) {
      AppLogger.log(
        'Subscription',
        'Paddle plans 命中会话缓存: count=${cached.length} '
            'ids=${cached.map((p) => p.planId).toList()}',
      );
      return cached;
    }
    AppLogger.log(
      'Subscription',
      'Paddle plans 拉取入口: includeIntroEligibility=$includeIntroEligibility',
    );
    final plans = await _repository.fetchPlans();
    _latestPlans = plans;
    AppLogger.log(
      'Subscription',
      'Paddle plans 拉取完成: count=${plans.length} '
          'ids=${plans.map((p) => p.planId).toList()}',
    );
    return plans;
  }

  @override
  Future<Entitlement> currentEntitlement() async {
    throw StateError('Paddle entitlement is read from /api/entitlements');
  }

  @override
  Stream<Entitlement> get entitlementStream => const Stream.empty();

  @override
  Future<Entitlement> purchase(String planId) async {
    throw UnsupportedError(
      'Paddle checkout must be started by SubscriptionController',
    );
  }

  @override
  Future<RestorePurchaseResult> restore() async {
    throw UnsupportedError('Paddle restore is a backend entitlement refresh');
  }

  @override
  Future<void> identify(String? userId) async {}

  @override
  Future<bool> ensureIdentified(String userId) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      AppLogger.log(
        'Subscription',
        'Paddle 身份检查失败: userId=$userId accessToken=empty',
      );
      return false;
    }
    AppLogger.log('Subscription', 'Paddle 身份检查通过: userId=$userId');
    return true;
  }

  @override
  Future<void> invalidateCustomerInfoCache() async {}

  @override
  Future<Map<String, Object?>> debugCustomerInfoSnapshot() async => const {};

  @override
  Future<String?> storefrontCountryCode() async => null;
}
