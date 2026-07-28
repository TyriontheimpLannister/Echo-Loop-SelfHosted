// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discover_podcasts_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$discoverPodcastsHash() => r'e4bf8420956ece74457643a40e18b9e4904e53b5';

/// Discover 页的精选 Podcast 列表。
///
/// 与官方合集共用同一份 catalog 缓存；返回 null 表示 catalog 尚未初始化，
/// 返回空 list 表示已初始化但后端暂无精选 Podcast。
///
/// Copied from [discoverPodcasts].
@ProviderFor(discoverPodcasts)
final discoverPodcastsProvider = Provider<List<CatalogPodcast>?>.internal(
  discoverPodcasts,
  name: r'discoverPodcastsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$discoverPodcastsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DiscoverPodcastsRef = ProviderRef<List<CatalogPodcast>?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
