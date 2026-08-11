#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Echo Loop 客户端「自用去锁」补丁脚本。

作用：让 fork 后的 Echo Loop App 在「不登录、不订阅」的情况下，
解锁全部 Premium AI 功能（翻译/解析/意群/词典/转录），
并把 AI 请求指向你自己的后端（由 API_BASE_URL 决定，见部署手册）。

特点：
- 基于「内容匹配」做字符串替换，不依赖行号，对官方任意小版本都稳健。
- 幂等：已应用过的改动会自动跳过，可重复运行。

用法（在你的 Echo-Loop 仓库根目录执行）：
    python3 apply_unlock.py

注意：本脚本只改下列自托管适配点，不重构订阅、支付或聊天 UI：
权益/认证闸门、AI 请求的 local token 回退、Android LAN HTTP，以及句子聊天。
改完仍需按部署手册配置 API_BASE_URL 并 flutter build。
"""
import os
import sys

ROOT = os.getcwd()
APPLIED = []


def read(rel):
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p):
        return None
    with open(p, encoding="utf-8") as f:
        return f.read()


def write(rel, s):
    with open(os.path.join(ROOT, rel), "w", encoding="utf-8") as f:
        f.write(s)


def patch_once(rel, old, new, marker=None):
    s = read(rel)
    if s is None:
        print(f"[跳过] 未找到 {rel}（请在 Echo-Loop 仓库根目录运行）")
        return
    if marker and marker in s:
        print(f"[已应用] {rel}")
        return
    if old not in s:
        print(f"[警告] {rel} 未匹配到预期内容，请确认是否为官方源码")
        return
    s = s.replace(old, new, 1)
    write(rel, s)
    APPLIED.append(rel)
    print(f"[已修改] {rel}")


def patch_all_occurrences(rel, old, new, marker=None):
    s = read(rel)
    if s is None:
        print(f"[跳过] 未找到 {rel}")
        return
    if marker and marker in s:
        print(f"[已应用] {rel}")
        return
    if old not in s:
        print(f"[警告] {rel} 未匹配到 '{old}'")
        return
    s = s.replace(old, new)
    write(rel, s)
    APPLIED.append(rel)
    print(f"[已修改] {rel}")


# ── 1. 付费墙：featureAccess 永远解锁 ──
patch_once(
    "lib/features/subscription/providers/feature_access_provider.dart",
    """bool featureAccess(Ref ref, PremiumFeature feature) {
  // 第一层：未登录禁用一切高级功能（连免费额度也不发放，须先登录）。
  if (!ref.watch(isAuthenticatedProvider)) return false;
  // 第二层：已确认 Premium → 无限解锁。
  final entitlement = ref.watch(subscriptionControllerProvider);
  if (entitlement.isActive) return true;
  // 第三层：已登录的免费用户 → 由免费额度策略决定（有限次数）。
  return ref.watch(freeAllowancePolicyProvider).allows(feature);
}""",
    """bool featureAccess(Ref ref, PremiumFeature feature) {
  // [自用补丁] 本地解锁全部 Premium 功能，无需订阅/登录。
  return true;
}""",
    marker="[自用补丁]",
)

# ── 2. 伪登录：isAuthenticated 永远为真（绕过"需登录"拦截）──
patch_once(
    "lib/features/auth/providers/auth_providers.dart",
    """final isAuthenticatedProvider = Provider<bool>((ref) {
  final session = ref.watch(supabaseSessionProvider).valueOrNull;
  return session != null;
});""",
    """final isAuthenticatedProvider = Provider<bool>((ref) {
  // [自用补丁] 本地伪登录，绕过"需登录"拦截（ref 保留以兼容 import）。
  return true;
});""",
    marker="[自用补丁]",
)

# ── 3. 句子聊天：保留官方登录模式的真实 token；自托管模式空 session 用 local ──
patch_once(
    "lib/features/chatbot/providers/chat_session_controller.dart",
    """    final accessToken = ref
        .read(supabaseSessionProvider)
        .valueOrNull
        ?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      state = state.copyWith(gate: ChatGate.authRequired);
      return;
    }
""",
    """    // [自用补丁:local-chat] 官方 session 有 token 时照常使用；自托管
    // 未配置 Supabase 时使用 local 占位，由局域网后端接收。
    final sessionAccessToken = ref
        .read(supabaseSessionProvider)
        .valueOrNull
        ?.accessToken;
    final accessToken = sessionAccessToken == null || sessionAccessToken.isEmpty
        ? 'local'
        : sessionAccessToken;
""",
    marker="[自用补丁:local-chat]",
)

patch_once(
    "lib/features/chatbot/services/chat_api_client.dart",
    """        headers: {'Authorization': 'Bearer $accessToken'},""",
    """        headers: {
          'Authorization':
              'Bearer ${accessToken.isNotEmpty ? accessToken : 'local'}',
        },""",
    marker="accessToken.isNotEmpty ? accessToken : 'local'",
)

# ── 4. AI 客户端：空 token 兜底为 'local'（后端忽略鉴权）──
patch_all_occurrences(
    "lib/services/sentence_ai_api_client.dart",
    "'Bearer $accessToken'",
    "'Bearer ${accessToken.isNotEmpty ? accessToken : 'local'}'",
    marker="accessToken.isNotEmpty ? accessToken : 'local'",
)

patch_all_occurrences(
    "lib/services/transcription_api_client.dart",
    "'Bearer $accessToken'",
    "'Bearer ${accessToken.isNotEmpty ? accessToken : 'local'}'",
    marker="accessToken.isNotEmpty ? accessToken : 'local'",
)

# ── 5. 自托管后端：空 token 不在业务层拦截，交给 API client 使用 'local' ──
patch_once(
    "lib/providers/sentence_ai_provider.dart",
    """    if (accessToken == null || accessToken.isEmpty) {
      AppLogger.log('SentenceAI', '翻译 L3 需要登录，未发现 Supabase access token');
      throw const AiFeatureAuthRequiredException();
    }
""",
    """    // [自用补丁:local-translation] 自托管后端不要求 Supabase token。
""",
    marker="[自用补丁:local-translation]",
)
patch_once(
    "lib/providers/sentence_ai_provider.dart",
    """    if (accessToken == null || accessToken.isEmpty) {
      AppLogger.log('SentenceAI', '解析 L3 需要登录，未发现 Supabase access token');
      throw const AiFeatureAuthRequiredException();
    }
""",
    """    // [自用补丁:local-analysis] 自托管后端不要求 Supabase token。
""",
    marker="[自用补丁:local-analysis]",
)
patch_once(
    "lib/providers/sentence_ai_provider.dart",
    """    if (accessToken == null || accessToken.isEmpty) {
      AppLogger.log('SenseGroup', 'L3 需要登录，未发现 Supabase access token');
      throw const AiFeatureAuthRequiredException();
    }
""",
    """    // [自用补丁:local-sense-group] 自托管后端不要求 Supabase token。
""",
    marker="[自用补丁:local-sense-group]",
)
patch_once(
    "lib/services/dictionary/ai_dictionary_source.dart",
    """    final token = request.accessToken;
    if (token == null || token.isEmpty) {
      throw const DictionaryAuthRequiredException();
    }
""",
    """    // 自托管后端不校验 Supabase token；空 token 由 API client 转为 `local`。
    final token = request.accessToken ?? '';
""",
    marker="自托管后端不校验 Supabase token",
)
patch_all_occurrences(
    "lib/providers/sentence_ai_provider.dart",
    "accessToken: accessToken,",
    "accessToken: accessToken ?? '',",
    marker="accessToken: accessToken ?? ''",
)

# ── 6. Android 允许明文 HTTP（学习机访问局域网 http:// 后端必需）──
patch_once(
    "android/app/src/main/AndroidManifest.xml",
    """    <application
        android:label="@string/app_name"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">""",
    """    <application
        android:label="@string/app_name"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true">""",
    marker='android:usesCleartextTraffic="true"',
)

print("\n==== 本次改动文件：", APPLIED if APPLIED else "无（均已应用或文件不匹配）")
print("下一步：按《部署手册》配置 API_BASE_URL 并 flutter build apk。")
