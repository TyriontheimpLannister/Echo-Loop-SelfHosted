/// 权益对账纯函数（C4 合并规则）。
///
/// 抽成无副作用纯函数，便于单测覆盖各组合，并避免 SubscriptionController 膨胀
/// （单函数 ≤50 行、单文件 ≤500 行）。
///
/// 合并优先级与时效（critic 修正，不用「任一源 active 即 active」）：
///   1. 在线权威源（后端 / RC）一旦返回，**直接覆盖**本地缓存——退款 / 撤销才能及时降级。
///   2. 在线源缺失（离线 / 错误）时，缓存仅作**乐观兜底**：在新鲜窗口内才采用其结论，
///      超期则降级为「未知 / 待校验」，不无限期放权也不误锁付费用户。
library;

import '../models/entitlement.dart';
import '../state/entitlement_state.dart';
import 'entitlement_cache.dart';

/// 本地缓存的新鲜窗口。超过此时长未被在线源确认的缓存视为过期。
const entitlementCacheFreshness = Duration(hours: 24);

/// premium 缓存的离线宽限上限：超过 24h 未获在线确认时，仍在有效期内的
/// premium 缓存最长可沿用的时长（对齐 RC SDK「信任到 expiration」的业界惯例；
/// 设上限防终身权益/时钟异常无限放权）。free 缓存不享受宽限。
/// 白嫖风险为零：付费能力由服务端 hasActiveEntitlement 在 AI 请求时实时判定。
const entitlementOfflineGraceCap = Duration(days: 30);

/// 根据在线权威结果与本地缓存计算权益运行态。
///
/// - [remote]：在线权威源（后端）结果。**null 表示未能获取**（离线 / 错误），
///   而非「确认无权益」——确认无权益应传入 [Entitlement.free]。
/// - [cached]：本地缓存快照，可为 null。
/// - [now]：当前时刻（显式传入便于测试）。
/// - [freshness]：缓存新鲜窗口，默认 [entitlementCacheFreshness]。
///
/// 离线缓存分两档：新鲜窗口内（≤[freshness]）直接采用缓存结论；
/// 窗口外至 [entitlementOfflineGraceCap] 之间仅对「按自身 expiresAt 仍有效的
/// premium」放宽限（长时间离线的付费用户不被误锁），free / 已到期不放。
EntitlementState reconcileEntitlement({
  required Entitlement? remote,
  required CachedEntitlement? cached,
  required DateTime now,
  Duration freshness = entitlementCacheFreshness,
}) {
  // 1. 在线权威源存在：直接覆盖，非陈旧。
  if (remote != null) {
    return EntitlementState(
      status: remote.isActive(now)
          ? EntitlementStatus.premium
          : EntitlementStatus.free,
      entitlement: remote,
      isStale: false,
    );
  }

  // 2. 离线：新鲜缓存直接采用；过窗的 premium 走离线宽限。
  if (cached != null) {
    final age = now.difference(cached.cachedAt);
    final entitlement = cached.entitlement;
    if (!age.isNegative && age <= freshness) {
      return EntitlementState(
        status: entitlement.isActive(now)
            ? EntitlementStatus.premium
            : EntitlementStatus.free,
        entitlement: entitlement,
        isStale: true,
      );
    }
    if (!age.isNegative &&
        age <= entitlementOfflineGraceCap &&
        entitlement.isActive(now)) {
      return EntitlementState(
        status: EntitlementStatus.premium,
        entitlement: entitlement,
        isStale: true,
      );
    }
  }

  // 3. 无在线源且无可用缓存：未知 / 待校验。
  return const EntitlementState(
    status: EntitlementStatus.unknown,
    isStale: true,
  );
}
