/// 平台订阅管理入口。
///
/// 按订阅**实际来源**（Apple / Google / Paddle）决定管理页，与 App 当前运行平台解耦：
/// 当前平台恰为来源平台时优先系统原生入口（iOS 系统订阅管理页 / Android Play 深链），
/// 跨平台则回退对应商店的网页管理页。Paddle 走动态 Customer Portal，由上层处理。
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/client_distribution.dart';
import '../../../config/revenuecat_config.dart';
import '../../../services/app_logger.dart';
import '../models/entitlement_source.dart';

/// URL 打开函数，供测试注入。
typedef SubscriptionUrlLauncher =
    Future<bool> Function(Uri uri, LaunchMode mode);

/// 当前可用的订阅管理入口。
class SubscriptionManagementLauncher {
  SubscriptionManagementLauncher({
    SubscriptionUrlLauncher? launchUrl,
    MethodChannel? channel,
    Future<PackageInfo> Function()? packageInfoLoader,
  }) : _launchUrl = launchUrl ?? _defaultLaunchUrl,
       _channel = channel ?? _defaultChannel,
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  static const _defaultChannel = MethodChannel(
    'top.echo-loop/subscription_management',
  );

  final SubscriptionUrlLauncher _launchUrl;
  final MethodChannel _channel;
  final Future<PackageInfo> Function() _packageInfoLoader;

  /// 按订阅**实际来源**打开对应平台的管理页，与 App 当前运行平台解耦。
  ///
  /// - [EntitlementSource.apple]：当前 iOS 优先系统原生管理页，其它平台（含 Android /
  ///   桌面）回退 Apple 网页订阅管理页；
  /// - [EntitlementSource.google]：当前 Android 优先 Play 深链，其它平台回退 Play 网页；
  /// - [EntitlementSource.paddle]：Paddle 走动态 Customer Portal，URL 由上层经
  ///   controller 获取，本入口不处理，返回 false 让上层改走 Portal；
  /// - [EntitlementSource.unknown]：来源未知（老缓存 / 后端未返回），回退到按当前平台渠道。
  ///
  /// 返回 false 表示没有可用入口或全部打开失败；调用方负责显示失败提示。
  Future<bool> open({
    required EntitlementSource source,
    String? productId,
  }) async {
    return switch (source) {
      EntitlementSource.apple => _openApple(),
      EntitlementSource.google => _openGooglePlay(productId),
      EntitlementSource.paddle => Future<bool>.value(false),
      EntitlementSource.unknown => _openByChannel(
        clientPaymentChannel,
        productId,
      ),
    };
  }

  /// 按当前平台渠道打开管理页（来源未知时的回退路径，保持旧行为）。
  Future<bool> _openByChannel(ClientPaymentChannel channel, String? productId) {
    return switch (channel) {
      ClientPaymentChannel.appleStore => _openApple(),
      ClientPaymentChannel.googlePlay => _openGooglePlay(productId),
      ClientPaymentChannel.web => _openWebManage(),
      ClientPaymentChannel.unavailable => Future<bool>.value(false),
    };
  }

  Future<bool> _openApple() async {
    if (!kIsWeb && Platform.isIOS) {
      try {
        final opened = await _channel.invokeMethod<bool>(
          'openManageSubscriptions',
        );
        if (opened == true) return true;
      } catch (e) {
        AppLogger.log('Subscription', 'Apple 原生订阅管理页打开失败，回退 URL: $e');
      }
    }
    final url = manageSubscriptionsUrlForChannel(
      ClientPaymentChannel.appleStore,
      webManageUrl: '',
    );
    return _openUri(url == null ? null : Uri.parse(url));
  }

  Future<bool> _openGooglePlay(String? productId) async {
    // 非 Android（iOS / macOS / 桌面）无法用 market:// 深链，直接打开 Play 网页管理页。
    // 这是「Google 订阅在非 Android 平台登录同账号」的管理入口。
    if (kIsWeb || !Platform.isAndroid) {
      return _openUri(
        Uri.parse('https://play.google.com/store/account/subscriptions'),
      );
    }
    final packageName = (await _packageInfoLoader()).packageName;
    final uris = googlePlaySubscriptionManagementUris(
      packageName: packageName,
      productId: productId,
    );
    for (final uri in uris) {
      if (await _openUri(uri)) return true;
    }
    return false;
  }

  Future<bool> _openWebManage() async {
    final url = manageSubscriptionsUrlForChannel(
      ClientPaymentChannel.web,
      webManageUrl: webManageUrl,
    );
    return _openUri(url == null ? null : Uri.parse(url));
  }

  Future<bool> _openUri(Uri? uri) async {
    if (uri == null) return false;
    try {
      return await _launchUrl(uri, LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.log('Subscription', '订阅管理 URL 打开失败: uri=$uri error=$e');
      return false;
    }
  }
}

Future<bool> _defaultLaunchUrl(Uri uri, LaunchMode mode) {
  return launchUrl(uri, mode: mode);
}

/// Google Play 订阅管理入口候选 URL。
///
/// 有商品 ID 时优先打开当前订阅详情；没有商品 ID 时打开订阅列表。
@visibleForTesting
List<Uri> googlePlaySubscriptionManagementUris({
  required String packageName,
  String? productId,
}) {
  final hasProduct = productId != null && productId.isNotEmpty;
  if (!hasProduct) {
    return [
      Uri.parse('market://subscriptions'),
      Uri.parse('https://play.google.com/store/account/subscriptions'),
    ];
  }
  final query = {'sku': productId, 'package': packageName};
  return [
    Uri(scheme: 'market', host: 'subscriptions', queryParameters: query),
    Uri.https('play.google.com', '/store/account/subscriptions', query),
  ];
}
