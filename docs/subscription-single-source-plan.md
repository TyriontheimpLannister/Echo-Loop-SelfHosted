# 订阅权益重构（定稿 v2）：全平台统一单一来源（后端 `/api/entitlements` 唯一权威 + 必要时 forceReconcile）

> 本文件是**可直接实现的交付规格**。实现者无需重新规划，按"接口设计"（§4）、"逐文件改动清单"（§9）与"测试"（§10）照做即可。
> 代码库：Flutter App `/Volumes/SamsungT7/workspace/fluency/fluency`；后端 `fluency-frontend`（**本次包含小改动**，见 §4.1）。

---

## 1. Context（为什么改）

App 有两套订阅来源：App Store/Google Play 走 RevenueCat（RC）；Web/direct 走自建 Paddle。后端 `/api/entitlements` 已在服务端合并 RC + Paddle。但客户端 native 渠道先信 RC `currentEntitlement()`，产生三个已复现线上 bug：

- **Bug1**：Paddle 会员在 App Store 包点"恢复购买" → 调 RC `restorePurchases()` → `receiptAlreadyInUseError` → 误报"购买失败"。
- **Bug2**：RC restore 返回空权益 → `_applyEntitlement` 把 status 置 free 并写缓存，覆盖有效的 Paddle premium。
- **Bug3**：native RC 返回 free、后端补查失败 → remote 保留 RC free → 权威降级，忽略新鲜 Paddle premium 缓存。

评审（对照代码逐条验证）另发现方案 v1 的四个缺口，本版已全部纳入：

- **R1（严重）**：购买/恢复成交后，RC `customerInfoUpdateListener`（`subscription_controller.dart:94`）必然自动触发 `refresh()`；此刻后端投影尚未收到 RC webhook → 返回权威 `isPremium=false` → 刚付钱的用户被降级 free 且缓存被污染。"`_applyEntitlement` 后不主动 refresh"防不住这个自动触发。→ 本版用 **forceReconcile 收敛**修复（§4.1/§4.6）。
- **R2**：restore 把 `_ensurePurchaseIdentity()` 放在后端刷新前，RC identify 故障会让 Paddle 会员点"刷新会员状态"直接报"购买失败"（Bug1 UX 复活）。→ 顺序调整（§4.5）。
- **R3**：续费边界——RENEWAL webhook 延迟时后端按 `expiresAtMs > now` 过滤返回权威 free，自动续费成功的会员在续费点被硬降级。→ 后端自动 force 规则（§4.1）。
- **R4**：单一来源后缓存新鲜窗仅 24h，而现状 native 离线时 RC SDK 缓存长期有效——长时间离线的付费用户会被锁 premium 功能（行为回退）。→ reconciler 离线宽限（§4.7）。

---

## 2. 方案定稿

**全平台（appleStore / googlePlay / web-direct）一条完全相同的权益流程：**

```
成交（RC purchase / RC restore 认领 / Paddle checkout 回流）
   → refresh(force: true)         // 后端绕过 24h 节流回源 RC，秒级收敛
   → reconcileEntitlement(后端结果, 本地缓存)   // 客户端唯一裁决点，契约不变
   → UI 只读 EntitlementState
```

- **客户端不做任何本地权益裁决**：删除 `_applyEntitlement` 乐观解锁（Bug2 的载体随之消失）。渠道差异只剩"支付执行器"（`PurchaseService` 已抽象）：RC 弹窗 / Paddle 浏览器。
- **RC 的角色（不删除，只瘦身）**：Apple/Google 购买执行、Offerings 价格、收据服务端校验 + webhook 进后端、商店 restore 认领、`identify(supabaseUserId)` 绑定。`currentEntitlement()` 保留在接口（debug 面板用），reconcile 路径不再调用。
- **未来扩展点（本次不实现）**：若商店渠道需要"成交即解锁 0 延迟"，在 `purchase()`/`restore()` 的"成交成功后、`_convergeAfterTransaction` 前"插入渠道内乐观 apply + 保持窗口即可，单一来源骨架不变。代码不留死钩子。
- **成本说明**：`/api/entitlements` 普通请求 2~3 条索引查表；force 请求受每用户 60s 防刷（§4.1），且只在用户主动动作/成交后发生。RC 不按 API 调用计费。

---

## 3. 架构与数据模型（现状，基本不动）

分层：UI(`paywall_screen.dart`) → `SubscriptionController`（唯一状态入口）→ `EntitlementRepository`（后端）/ `PurchaseService`（支付执行）/ `EntitlementCache`（本地缓存）。

数据模型均无需改：`Entitlement`（`isPremium/productId/expiresAt/willRenew/source`、`isActive(now)`、`Entitlement.free`）、`EntitlementSource`、`EntitlementState`（`status/entitlement/isStale/error`）。

`reconcileEntitlement` 契约不变 + 新增离线宽限（§4.7）：`remote!=null`→采用且 `isStale=false`；`remote==null` 表示"未能获取"而非"确认无权益"，确认无权益必须传 `Entitlement.free`。

---

## 4. 接口设计与输入输出（核心改动）

### 4.1 后端：`?force=1` 绕节流 + 续费边界自动回源

**文件 1**：`fluency-frontend/packages/payments/libs/entitlements.ts`

```ts
/** force 回源的每用户最小间隔（防客户端滥用打爆 RC API）。 */
export const ENTITLEMENT_FORCE_RECONCILE_MIN_INTERVAL_MS = 60 * 1000;

export async function getUserEntitlementSummaryWithReconcile(
  userId: string,
  options?: { force?: boolean }
): Promise<UserEntitlementSummary> {
  // select 需扩展：lastReconciledAtMs 之外加 isActive、expiresAtMs（供自动 force 判定）
  const rows = await database
    .select({
      lastReconciledAtMs: userEntitlements.lastReconciledAtMs,
      isActive: userEntitlements.isActive,
      expiresAtMs: userEntitlements.expiresAtMs,
    })
    .from(userEntitlements)
    .where(supportedEntitlementWhere(userId));

  const lastReconciledAtMs = /* 现有 reduce 逻辑不变 */;
  const now = Date.now();
  const sinceLast = lastReconciledAtMs == null ? null : now - lastReconciledAtMs;

  // 判定是否回源 RC，三个条件任一命中（force/自动 force 受 60s 最小间隔约束，防抖动循环）：
  const minIntervalOk =
    sinceLast == null || sinceLast >= ENTITLEMENT_FORCE_RECONCILE_MIN_INTERVAL_MS;
  const staleReconcile =
    sinceLast == null || sinceLast >= ENTITLEMENT_RECONCILE_INTERVAL_MS; // 现有 24h
  // R3：投影仍标 active 但 expiresAtMs 已过（可能已自动续费、webhook 未达）→ 视同必要时刻。
  // reconcile 后：真到期 → isActive=false 落库，条件自清除；已续费 → expiresAtMs 前移，条件自清除。
  const expiredButActive = rows.some(
    (r) => r.isActive && r.expiresAtMs != null && r.expiresAtMs <= now
  );
  const shouldReconcile =
    staleReconcile || (minIntervalOk && (options?.force === true || expiredButActive));

  if (!shouldReconcile) {
    return getUserEntitlementSummary(userId); // 现有本地投影路径
  }
  // 以下与现有代码一致：try reconcileRevenueCatEntitlements(userId)，
  // 失败时若本地投影 isPremium 则保留本地结果，否则 rethrow。
}
```

**文件 2**：`fluency-frontend/apps/app/app/api/entitlements/route.ts`（GET handler，第 18–27 行附近）

```ts
const force = request.nextUrl.searchParams.get('force') === '1';
const summary = await getUserEntitlementSummaryWithReconcile(auth.user.id, { force });
```

**行为契约**：
- `force=1` 且距上次 reconcile ≥60s → 直接回源 RC（RC 服务端在成交时即知晓交易，**不依赖 webhook 到达**）。
- `force=1` 但 <60s → 静默退回普通路径（返回本地投影），**不是错误**。
- 无 force 时行为与现状一致，另加 `expiredButActive` 自动回源（修 R3）。
- **已知限制**：force 只回源 RC；Paddle 侧无回源 API，Paddle 的续费/退款新鲜度依赖 Paddle webhook（与现状 web 渠道行为一致，不回退）。

### 4.2 `EntitlementRepository.fetchRemote` 增 `force`

文件：`lib/features/subscription/services/entitlement_repository.dart`

- 抽象与两个实现（Stub / Backend）签名统一为：
  ```dart
  Future<Entitlement?> fetchRemote({
    required String userId,
    required String accessToken,
    bool force = false,
  });
  ```
- `BackendEntitlementRepository`：`force` 为 true 时请求 `'/api/entitlements'` 带 `queryParameters: {'force': '1'}`。错误策略不变（2xx→映射，`isPremium:false`→`Entitlement.free` 权威降级；网络/非 2xx/解析异常→null，绝不误降级）。日志补 `force=$force`。
- 文件头注释"该仓库只供 Web/direct 渠道使用"已过时，改为"全渠道唯一权威源"。

### 4.3 `SubscriptionController.refresh` / `_refreshOnline` —— 单一来源

文件：`lib/features/subscription/providers/subscription_controller.dart`

`refresh`（当前 112–115 行）：
```dart
/// 与后端权威源对账并刷新权益。集中状态变更入口之一。
/// [force] 让后端绕过节流回源 RC（成交收敛 / 用户主动刷新用）。
Future<void> refresh({bool force = false}) async {
  await _waitForIdentitySync();
  await _refreshOnline(force: force);
}
```

`_refreshOnline`（当前 129–236 行整段方法体替换）：
```dart
Future<void> _refreshOnline({bool force = false}) async {
  // 调试覆盖生效时跳过在线对账，保持人为设定的状态。
  final override = _debugOverride;
  if (override != null) {
    _setEntitlementState(_stateForOverride(override));
    return;
  }
  final generation = ++_generation;
  final identity = _identity;
  final userId = identity.userId;
  final accessToken = identity.accessToken;
  AppLogger.log(
    'Subscription',
    '权益刷新开始: generation=$generation force=$force '
        'channel=${_paymentChannel.name} userId=${userId ?? "匿名"} '
        'hasToken=${accessToken != null}',
  );

  final cached = await _readValidCache(userId);
  Entitlement? remote;
  if (userId != null && accessToken != null) {
    // 唯一权威源：后端 /api/entitlements（服务端已合并 RC + Paddle）。
    // fetchRemote 约定：成功有权益→premium；成功无权益→Entitlement.free（权威降级）；
    // 网络/超时/非2xx/解析异常→null（内部已捕获，不抛），交由 reconciler 走缓存兜底。
    remote = await _repository.fetchRemote(
      userId: userId,
      accessToken: accessToken,
      force: force,
    );
  } else if (userId == null) {
    // 匿名：无账号可绑定的权益，明确 free（购买/恢复均强制登录，不存在匿名会员）。
    remote = Entitlement.free;
  }
  // userId != null 但 token 未就绪：remote 保持 null → 缓存兜底，不误判 free。

  if (generation != _generation) return; // 竞态：被更新的对账/登录切换作废。

  final next = reconcileEntitlement(remote: remote, cached: cached, now: clock.now());
  _setEntitlementState(next);

  AppLogger.log(
    'Subscription',
    '对账完成: remote=${remote != null ? "isPremium=${remote.isPremium}" : "无"} '
        'cached=${cached != null ? "isPremium=${cached.entitlement.isPremium}" : "无"} '
        '→ status=${state.status.name} isStale=${state.isStale} '
        'source=${state.entitlement?.source.name ?? "none"} channel=${_paymentChannel.name}',
  );

  if (remote != null) await _writeCache(remote, userId);
}
```
**要点**：
- 删除 `_purchases.currentEntitlement()` 调用、web/native 双分支、native 回退补查块——三渠道同一条路径。
- 删除原 try/catch 与 `error` 变量：新方法体内无会抛异常的调用（`fetchRemote` 内部全捕获），失败原因已由 repository 日志记录，`isStale=true` 即离线信号。`_applyIdentityFailure`（identify 失败路径）保留现状不动，它仍用 `copyWith(error:)`。
- 所有既有触发点（冷启动 E1、身份变化 E2、RC 流 E3、到期 one-shot E5、resume、Paddle 轮询）调用 `refresh()` 不带 force，行为不变。

### 4.4 `purchase()` —— 成交后回源收敛（删除乐观解锁）

替换当前 239–266 行：
```dart
/// 发起购买。成交后不做本地裁决，统一回源后端收敛（单一来源）。
Future<void> purchase(String planId) async {
  AppLogger.log('Subscription',
      '发起购买: planId=$planId userId=${_identity.userId ?? "匿名"}');
  await _ensurePurchaseIdentity(); // fail-closed：未绑定 Supabase user_id 直接中止。
  final generation = _generation;  // 成交期间身份若变化，跳过收敛（新身份自有对账）。
  try {
    final entitlement = await _purchases.purchase(planId);
    AppLogger.log('Subscription',
        '购买成交: productId=${entitlement.productId} '
        'isPremium=${entitlement.isPremium}（结果仅记录，不作裁决）');
  } on PurchaseException catch (e) {
    AppLogger.log('Subscription',
        e.cancelled ? '购买取消: planId=$planId' : '购买失败: planId=$planId msg=${e.message}');
    rethrow;
  } catch (e) {
    AppLogger.log('Subscription', '购买异常: planId=$planId error=$e');
    rethrow;
  }
  if (generation != _generation) {
    AppLogger.log('Subscription', '购买期间身份已变化，跳过收敛刷新');
    return;
  }
  await _convergeAfterTransaction('purchase');
}
```

### 4.5 `restore()` —— 全渠道统一，商店 restore 仅作认领

替换当前 363–401 行：
```dart
/// 找回/刷新会员（全渠道统一语义）。
/// 1) 先回源后端（唯一权威，含 Paddle 与已同步的商店订阅），命中即结束；
/// 2) 仍非会员且是商店渠道 → RC restore 认领游离商店收据，认领后回源收敛。
Future<void> restore() async {
  AppLogger.log('Subscription',
      '恢复/刷新会员发起: channel=${_paymentChannel.name} '
      'source=${state.entitlement?.source.name ?? "none"} userId=${_identity.userId ?? "匿名"}');

  // 用户主动动作 → force 取最新权威（后端 60s 防刷兜底）。
  // 注意：_ensurePurchaseIdentity 在此步之后——RC identify 故障不得阻断纯后端刷新（修 R2）。
  await refresh(force: true);
  if (state.isActive) return; // 命中（含 Paddle 会员在商店包，修 Bug1：不调 RC restore）。

  final isStoreChannel = _paymentChannel == ClientPaymentChannel.appleStore ||
      _paymentChannel == ClientPaymentChannel.googlePlay;
  if (!isStoreChannel) return; // web/direct/unavailable：恢复=后端刷新，已完成。

  await _ensurePurchaseIdentity(); // fail-closed：仅 RC restore 需要。
  final generation = _generation;
  try {
    final result = await _purchases.restore();
    final entitlement = result.entitlement;
    final currentUserId = _identity.userId;
    final ownerUserId = result.originalAppUserId;
    if (entitlement.isActive(clock.now()) &&
        currentUserId != null && ownerUserId != null && ownerUserId != currentUserId) {
      AppLogger.log('Subscription',
          '恢复购买归属冲突: currentUserId=$currentUserId originalAppUserId=$ownerUserId');
      throw PurchaseException('此订阅已绑定到另一个 Echo Loop 账号。请登录原账号后重试。',
          ownershipConflict: true);
    }
    if (!entitlement.isActive(clock.now())) {
      AppLogger.log('Subscription', 'RC 无可恢复收据，保持后端对账结果'); // 修 Bug2：不降级。
      return;
    }
    AppLogger.log('Subscription', '商店收据认领成功: productId=${entitlement.productId}');
  } on PurchaseException catch (e) {
    if (e.receiptInUse) {
      // 收据属其他 RC 订阅者，但本账号可能已被后端判为会员：回源确认，不当"购买失败"（修 Bug1 兜底）。
      AppLogger.log('Subscription', 'RC 收据被占用，回源确认真实会员态');
      await refresh(force: true);
      return;
    }
    AppLogger.log('Subscription', '恢复购买失败: error=$e');
    rethrow;
  }
  if (generation != _generation) return; // 认领期间身份已变化，跳过收敛。
  await _convergeAfterTransaction('restore'); // 认领→RC 已知→force 回源即收敛，不依赖 webhook。
}
```

### 4.6 新增 `_convergeAfterTransaction` + 删除 `_applyEntitlement`

- **删除** `_applyEntitlement`（当前 447–463 行）——调用方已全部移除，属死代码。其 generation 校验本就恒 false（评审发现），一并消除。
- 新增：
```dart
/// 成交后回源收敛：force 绕过后端节流读取 RC 最新权益。
/// 短重试兜住瞬时网络失败（每次都完整走 refresh 的 generation 防竞态）；
/// 重试后仍未 active 只记日志——钱已成交，权益由后续触发点（E3/E5/resume）自然收敛，
/// UI 据 state 提示"同步中"，绝不报"购买失败"。
Future<void> _convergeAfterTransaction(String reason) async {
  const maxAttempts = 3;
  const interval = Duration(seconds: 2);
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    await refresh(force: true);
    if (state.isActive) {
      AppLogger.log('Subscription', '成交收敛完成: reason=$reason attempt=$attempt');
      return;
    }
    if (attempt < maxAttempts) await Future<void>.delayed(interval);
  }
  AppLogger.log('Subscription',
      '成交收敛未确认（等待后续触发点）: reason=$reason status=${state.status.name}');
}
```
- **R1 为什么被修复**：E3 抢跑的普通 `refresh()`（读到未收敛投影 free）会因 `_convergeAfterTransaction` 的 forced refresh 后启动、先 bump `_generation` 而被现有 generation 检查作废；forced refresh 命中后端回源 RC 的最新结果。无需任何新防护结构。

### 4.7 reconciler：离线宽限（修 R4）

文件：`lib/features/subscription/services/entitlement_reconciler.dart`

```dart
/// premium 缓存的离线宽限上限：超过 24h 未获在线确认时，仍在有效期内的
/// premium 缓存最长可沿用的时长（对齐 RC SDK "信任到 expiration" 的业界惯例；
/// 设上限防终身权益/时钟异常无限放权）。free 缓存不享受宽限。
/// 白嫖风险为零：付费能力由服务端 hasActiveEntitlement 在 AI 请求时实时判定。
const entitlementOfflineGraceCap = Duration(days: 30);
```
第 2 步（离线缓存分支）在现有"24h 新鲜"判定后追加：
```dart
// 24h 外的宽限：仅 premium 且按缓存自身 expiresAt 仍有效时适用。
if (!fresh && !age.isNegative && age <= entitlementOfflineGraceCap) {
  final entitlement = cached.entitlement;
  if (entitlement.isActive(now)) {
    return EntitlementState(
      status: EntitlementStatus.premium,
      entitlement: entitlement,
      isStale: true,
    );
  }
}
```
（实现时把现有 `fresh` 分支与本分支合并整理，保持函数 ≤50 行；文档注释同步更新。）

### 4.8 `PurchaseException` 增 `receiptInUse`

文件：`lib/features/subscription/services/purchase_service.dart`（第 13–33 行）
```dart
PurchaseException(this.message,
    {this.cancelled = false, this.ownershipConflict = false, this.receiptInUse = false});
/// 收据已被其他 RC 订阅者占用（receiptAlreadyInUseError）。
final bool receiptInUse;
// toString() 同步补充 receiptInUse。
```

### 4.9 RC 实现映射 `receiptAlreadyInUseError`

文件：`lib/features/subscription/services/revenuecat_purchase_service.dart`（`restore()` catch，第 164–171 行），在 `purchaseCancelledError` 特判后增加：
```dart
if (code == PurchasesErrorCode.receiptAlreadyInUseError) {
  throw PurchaseException(e.message ?? '收据已被占用', receiptInUse: true);
}
```

### 4.10 UI：去分流 + 来源感知文案 + 购买同步中提示

文件：`lib/features/subscription/screens/paywall_screen.dart`

- 恢复按钮（第 135–142 行）：删除 `webMode ? _refreshEntitlement : _restore` 分流，统一 `_restore`；文案按来源：
  ```dart
  final isPaddleMember =
      subState.entitlement?.source == EntitlementSource.paddle && isPremium;
  actions: [
    TextButton(
      onPressed: _busy ? null : _restore,
      child: Text(isPaddleMember ? l10n.premiumRefreshStatus : l10n.premiumRestore),
    ),
  ],
  ```
- `_purchase`（第 612–634 行）：成功返回后 `isActive` → `context.pop()`（现状）；**不 active 且无异常** → `_showMessage(l10n.premiumPurchasePendingSync)`（成交但收敛未确认，绝不显示"购买失败"）。
- `_restore`（第 636–661 行）：catch 保留 `ownershipConflict → premiumRestoreAccountMismatch`、其余 `premiumPurchaseFailed`；`receiptInUse` 已在 controller 消化不会抛到 UI。成功后按 `isActive` 提示 `premiumRestored`/`premiumRestoreNone`（现状不变）。
- 删除 `_refreshEntitlement`（第 525–547 行，唯一调用点即上面按钮，删后为死代码）。

### 4.11 l10n 新键

`lib/l10n/app_en.arb` / `app_zh.arb`（加在 `premiumRefresh` 之后）：
- `"premiumRefreshStatus": "Refresh membership"` / `"刷新会员状态"`
- `"premiumPurchasePendingSync": "Purchase successful. Your membership is syncing and will activate shortly."` / `"购买成功，会员权益同步中，稍后自动生效。"`

随后运行 `flutter gen-l10n`。

---

## 5. 边界情况总表（输入 → 输出）

刷新（`_refreshOnline`，全渠道同一）：
| 输入 | 输出 |
|---|---|
| 匿名（任意渠道） | remote=`Entitlement.free` → status=free |
| userId 有、token 无 | remote=null → 缓存兜底 / unknown，不误判 free |
| 后端 premium（source 任意） | premium，isStale=false，写缓存 |
| 后端明确 free + 缓存 premium | **free**（权威降级，含退款/退订；Bug3b） |
| 后端不可达 + ≤24h 缓存 premium | premium，isStale=true（Bug3 修复） |
| 后端不可达 + >24h 且 ≤30d 缓存 premium 未到期 | premium，isStale=true（离线宽限 R4） |
| 后端不可达 + 缓存 free >24h / premium 已到期 / >30d | unknown，isStale=true |
| 并发 refresh / 登录切换 | generation 后者胜，先者作废 |

恢复（`restore()`）：
| 输入 | 输出 |
|---|---|
| Paddle 会员 + appleStore 包 | forced refresh 命中 premium → return，**不调 RC restore**（Bug1） |
| 商店会员重装、后端已知 | forced refresh 命中 → return |
| 商店会员重装、后端未知 | refresh free → RC 认领 active（归属己方）→ 收敛 premium |
| RC restore 无收据 | 保持后端结果，不降级（Bug2） |
| RC `receiptAlreadyInUse` | 转 forced refresh，不报"购买失败" |
| 认领结果归属其他账号 | 抛 `ownershipConflict` → UI 提示换账号 |
| RC identify 故障 + Paddle 会员 | forced refresh 已在 identify 前命中 → 正常返回（R2） |
| restore/purchase await 期间登出/切号 | generation 检查跳过收敛，不污染新身份 state |

购买（`purchase()`）：
| 输入 | 输出 |
|---|---|
| 成交 + 后端收敛成功 | ≤2s 内 premium（force 回源 RC，不等 webhook；R1） |
| 成交 + E3 抢跑读到旧投影 | 抢跑结果被 generation 作废，forced 结果落定 |
| 成交 + 后端三次收敛均失败 | state 维持原样 + UI 提示"同步中"，后续触发点收敛；**不报购买失败** |
| 用户取消 | `cancelled` 异常，UI 静默回到 Paywall（现状） |

后端：
| 输入 | 输出 |
|---|---|
| `force=1` 且距上次 reconcile ≥60s | 回源 RC 重建投影 |
| `force=1` 且 <60s | 静默走本地投影（防刷） |
| 投影 active 但 expiresAtMs 已过（无 force） | 自动回源（续费边界 R3；结果落库后条件自清除） |
| 回源 RC 失败 + 本地投影 premium | 保留本地 premium（现状） |
| 纯 Paddle 用户首次请求（无 userEntitlements 行） | 触发一次 RC 建档回源（预期，之后节流） |

已知限制（记录，不处理）：
- force 只回源 RC；**Paddle 的续费/退款新鲜度依赖 Paddle webhook**（与现状一致）。
- **历史匿名 RC 购买**（fail-closed 门禁之前成交的）在单一来源下不可见，需登录后 restore 认领。

---

## 6. 刷新事件模型（P1，可在 P0 后单独做）

原则不变：不轮询，只在"状态已变"或"检测到分歧"时刷新。**顺序为 E7 → E6 → E8**（E6 未上线前撤 resume 盲查会削弱 Paddle 退款兜底，故 E8 最后做）。

- A 组（P0 沿用）：E1 冷启动、E2 身份变化、E3 RC `entitlementStream → refresh()`（单一来源下仅是触发器）、E4 成交收敛（本版为 forced refresh）、E5 到期 one-shot（`_rescheduleExpiryRefresh`）。
- **E7（已实现 2026-07-23）**：`SubscriptionController.reconcileOnServerQuotaRejection` + 可 override 的 `entitlementQuotaDivergenceHandlerProvider`；两个 402 触发点接入（sentence AI `onBackendQuotaRejected` 回调、转录 402 分支）。纯客户端。
- **E6（已实现 2026-07-23，实现与原方案的偏差）**：信号头定为 **`x-entitlement-active: 1|0`**（服务端当前权益视图布尔值），而非 epoch 计数——客户端本就是"与当前 state 比对"，布尔直接可比、无需持久化 last-seen epoch；active↔active 的变化（续费/换 plan）无需即时信号，由其它触发点覆盖。**信号头零额外查询**：`authorizeAiUsage` 仅在配额链路本来就查询了权益（开关开启且 client 受限）时把 `entitlementActive` 带回返回值，guard 据此下发信号头；开关关闭 / client 不受限的旁路路径不查询、不带头——不为发信号扩大 DB 故障面（DB 故障不会让本应放行的请求失败）。放行时由各路由把 `entitlementHeaders` 附到流式/JSON 响应，402 响应直接带头（403 在权益查询前拒绝，无头）；客户端 `EntitlementSignalInterceptor`（`createBackendDio` 统一安装，静态回调由 controller 注册）读头转发（无头零动作），controller 侧比对分歧 → in-flight 去重后 refresh，跳过 `/api/entitlements` 自身。
- **E8（已实现 2026-07-23）**：resume 改调 `refreshIfStale()`——仅 unknown/isStale/距上次在线确认超 5 分钟/越过 expiresAt 才回源；main.dart 注释已按单一来源语义改写。
- E9（可选，未实现）：Supabase Realtime 推送，给 Paddle 秒级降级/升级。

状态码契约（`authorizeMeteredAiRequest`，客户端分别反应）：
- **401** token 缺失/失效 → 客户端映射 `AiFeatureAuthRequiredException`（登录引导，不重试）；
- **402** quota_exceeded（附 quota 明细）→ `AiFeatureQuotaExceededException`（订阅引导）+ E7 收敛；
- **403** invalid_client → 通用失败；
- `x-entitlement-active` 信号头（E6）仅在配额链路查过权益时下发（成功与 402 响应）；
  401/403 与旁路放行（开关关闭 / client 不受限）不带，客户端对无头响应零动作。

---

## 7. 降级（取消/退款）新鲜度说明（设计依据，非改动项）

- 后端 DB 秒级新鲜：RC webhook（`processRevenueCatWebhookEvent`）/ Paddle webhook 均立即落库，不经节流。
- Apple/Google 退款近实时（E3 RC 流触发）；Paddle 退款等 resume/E6/E9；取消续费不紧急（到期自然降级）。
- 续费边界由后端 `expiredButActive` 自动回源兜住（§4.1）。
- 正确性兜底：付费能力由服务端 `hasActiveEntitlement`（`fluency-frontend/packages/payments/libs/entitlements.ts:129`）在 AI 请求时实时判定；客户端 UI 滞后仅观感，不产生白嫖——离线宽限（§4.7）同理。

---

## 8. 分期交付

- **P0 —— 全平台统一单一来源 + forceReconcile 收敛 + 三 bug/四缺口根除**：§4 全部（含后端两文件小改）。可独立上线。
- **P1 —— 智能刷新**：E7（纯客户端）→ E6（后端 epoch 头 + 拦截器）→ E8（去盲查）。
- **P2 —— 可选**：E9 Realtime 推送；商店渠道乐观解锁（§2 扩展点）。

---

## 9. 逐文件改动清单（P0）

后端（`fluency-frontend`）：
1. `packages/payments/libs/entitlements.ts`：`getUserEntitlementSummaryWithReconcile` 增 `options.force`、60s 防刷、`expiredButActive` 自动回源（§4.1）。
2. `apps/app/app/api/entitlements/route.ts`：解析 `?force=1` 透传（§4.1）。

客户端（`fluency`）：
3. `lib/features/subscription/services/entitlement_repository.dart`：`fetchRemote(force:)`（抽象 + Stub + Backend），头注释更新（§4.2）。
4. `lib/features/subscription/providers/subscription_controller.dart`：`refresh(force:)`、`_refreshOnline` 替换、`purchase()` 重写、`restore()` 重写、删 `_applyEntitlement`、增 `_convergeAfterTransaction`（§4.3–4.6）。
5. `lib/features/subscription/services/entitlement_reconciler.dart`：离线宽限（§4.7）。
6. `lib/features/subscription/services/purchase_service.dart`：`receiptInUse`（§4.8）。
7. `lib/features/subscription/services/revenuecat_purchase_service.dart`：错误码映射（§4.9）。
8. `lib/features/subscription/screens/paywall_screen.dart`：按钮去分流、`_purchase`/`_restore` 调整、删 `_refreshEntitlement`（§4.10）。
9. `lib/l10n/app_en.arb` / `app_zh.arb` + `flutter gen-l10n`（§4.11）。

---

## 10. 测试（test-first；`test/features/subscription/`）

### 10.1 测试替身调整
- `FakeEntitlementRepository`：记录每次调用的 `(userId, force)`（现有 `calls` 扩展或新增 `forceCalls`）；支持**按调用顺序出队的结果序列**（成交收敛用例需要"第一次 free、force 后 premium"）。
- `FakePurchaseService`：`restore()` 增可注入异常（`Object? restoreError`）。

### 10.2 需更新的现有用例（`subscription_controller_test.dart`）
- `native 登录冷启动 → 跳过后端,直接采用 RevenueCat active`（:749）：改为断言读后端——repo 返回 premium、`repo.calls` 含 u1、`purchases.currentCalls == 0`。
- `native 登录冷启动 → identify 完成前不读取权益`（:770）、`native 快速切换身份 → 等待最新 identify`（:834）：`currentCalls` 断言改为 `repo.calls`。
- `匿名对账后 → free（RevenueCat 返回无购买）`（:345）：语义改为"匿名 → 明确 free，不调 repo 也不调 currentEntitlement"。
- `purchase 成功 → 立即本地解锁`（:723）：改为 **`purchase 成功 → forced 回源收敛 premium`**——repo 队列 [free(冷启动), premium(force)]，断言最终 premium、`repo` 收到 `force=true` 调用、缓存为后端返回的 premium。
- `restore active → 直接应用平台返回权益,不调用后端`（:882）：语义改为"后端 free → RC 认领 active → forced 收敛 premium"——repo 队列 [free, premium]，断言 `restoreCalls>=1`、最终 premium 来自后端结果。
- `restore active 且归属为当前用户 → 应用权益`（:909）：同上改为收敛语义。
- `restore free 且存在其他 originalAppUserId → 不触发归属冲突`（:973）：repo 恒 free，最终 free。
- 保持不变（应仍通过）：`restore active 但归属不是当前用户 → 抛 ownershipConflict`（:936）、`Web 渠道 restore → 不调底层恢复`（:999，断言改为仍调了 repo 且 force=true）、`fail-closed 身份未绑定 → restore 报错`（:1128，注意现在先 refresh 后才 fail-closed——断言 repo 被调过一次）、离线/退款/登出/切换/generation/到期 timer 等用例。

### 10.3 新增用例（锁死 bug 与评审缺口）
- **Bug3**：appleStore + repo null + 新鲜 Paddle premium 缓存 → premium、isStale=true。
- **Bug3b**：appleStore + repo `Entitlement.free` + premium 缓存 → free（权威降级）。
- **Bug1**：repo 返回 paddle premium + appleStore → `restore()` → premium、`restoreCalls==0`。
- **R1**：purchase 成交后 repo 第一次返回 free（模拟旧投影）、force 调用返回 premium → 最终 premium（收敛重试生效）。
- **R2**：`ensureIdentified` 恒 false + repo 返回 paddle premium → `restore()` 正常返回 premium，**不抛异常**。
- **receiptInUse**：`restoreError = PurchaseException(receiptInUse: true)` + repo free → 不 rethrow、最终 free、repo 至少两次调用。
- **切号竞态**：purchase 成交 await 期间触发身份变化（generation bump）→ 不执行收敛、state 归新身份对账结果。
- **收敛失败**：repo 恒 null + purchase 成交 → 三次尝试后 state 保持缓存/unknown、不抛异常。
- **reconciler 宽限**（`entitlement_reconciler_test.dart`）：缓存 premium、age=3 天、expiresAt 未到 → premium+isStale；expiresAt 已过 → unknown；age=31 天 → unknown；缓存 free、age=3 天 → unknown。
- **RC 映射单测**（`revenuecat_purchase_service_test.dart`）：`PlatformException(receiptAlreadyInUseError)` → `receiptInUse == true`。
- **repository 单测**：`force: true` → 请求带 `?force=1`；默认不带。

### 10.4 Widget 测试（`paywall_screen_test.dart`）
- `source=paddle` premium：按钮文案 = `premiumRefreshStatus`，点击调用统一 `restore()`（无 `webMode` 分支）。
- 购买成功但未收敛（mock controller purchase 后 state 仍 free）：出现 `premiumPurchasePendingSync`，不出现 `premiumPurchaseFailed`。

### 10.5 后端测试（vitest，`packages/payments` 现有套件旁）
- `force=true` 且距上次 ≥60s → 调 reconcile；<60s → 走本地投影。
- 无 force、投影 `isActive && expiresAtMs <= now` → 自动 reconcile；reconcile 后条件自清除。
- 现有 24h 节流行为不回归。

---

## 11. 验证命令

```bash
# 客户端
cd /Volumes/SamsungT7/workspace/fluency/fluency
flutter gen-l10n          # 改了 arb 后
flutter analyze
flutter test test/features/subscription/

# 后端
cd /Users/shibo/t7/workspace/fluency/fluency-frontend
pnpm lint && pnpm test    # 按仓库实际 test 命令执行（vitest）
```

手动回归（Paddle 生产账号登录 App Store 包）：
1. 点"刷新会员状态" → 日志无 `RC restorePurchases 发起` / `receiptAlreadyInUseError` / "购买失败"。
2. 断网点刷新 → `remote=无 cached=isPremium=true → status=premium isStale=true`（不再 `→ status=free`）。
3. 联网 → `对账完成: remote=isPremium=true ... source=paddle → status=premium`。
4. App Store 沙盒新购买 → 3 秒内会员态生效，全程无 free 闪降；后端日志见 force reconcile。

---

## 12. 风险与注意

- **防竞态骨架不动**：`_generation`、`_waitForIdentitySync` 保留；本版在 purchase/restore 的平台 await 前后新增 generation 快照校验（§4.4/§4.5），修复原先 `_applyEntitlement` 恒-false 校验的漏洞。
- **成交收敛依赖后端可用性**：三次重试失败时用户暂看不到会员（UI 提示同步中），由 E3/E5/resume 自然收敛；服务端权益已生效，无资损。
- **force 防刷**：客户端只在用户主动动作（restore）与成交后调用 force；后端 60s 防刷是硬保障，客户端无需再做去重。
- **实现顺序建议**：后端（§4.1）→ repository（§4.2）→ reconciler（§4.7）→ controller（§4.3–4.6）→ UI/l10n（§4.10–4.11），每步跑对应测试再进下一步。
