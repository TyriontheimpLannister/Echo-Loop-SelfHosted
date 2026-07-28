// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'podcast_preview_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$podcastPreviewDioHash() => r'd8157347c67dc475ff8a48aa09ff8e383fc1becd';

/// See also [podcastPreviewDio].
@ProviderFor(podcastPreviewDio)
final podcastPreviewDioProvider = Provider<Dio>.internal(
  podcastPreviewDio,
  name: r'podcastPreviewDioProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$podcastPreviewDioHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PodcastPreviewDioRef = ProviderRef<Dio>;
String _$podcastPreviewServiceHash() =>
    r'210ca30412d93b2b7114e967a28c229c4ee304be';

/// See also [podcastPreviewService].
@ProviderFor(podcastPreviewService)
final podcastPreviewServiceProvider = Provider<PodcastPreviewService>.internal(
  podcastPreviewService,
  name: r'podcastPreviewServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$podcastPreviewServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PodcastPreviewServiceRef = ProviderRef<PodcastPreviewService>;
String _$podcastPreviewHash() => r'da4544329963232118faedcadcfadc7904702d0d';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// 由订阅输入 URL 拉取单个 Podcast 的 RSS 预览。
///
/// [inputUrl] 为 RSS 或 Apple Podcasts 链接，同时用作 family key，
/// 天然按来源缓存并防竞态。
///
/// Copied from [podcastPreview].
@ProviderFor(podcastPreview)
const podcastPreviewProvider = PodcastPreviewFamily();

/// 由订阅输入 URL 拉取单个 Podcast 的 RSS 预览。
///
/// [inputUrl] 为 RSS 或 Apple Podcasts 链接，同时用作 family key，
/// 天然按来源缓存并防竞态。
///
/// Copied from [podcastPreview].
class PodcastPreviewFamily extends Family<AsyncValue<PodcastPreviewData>> {
  /// 由订阅输入 URL 拉取单个 Podcast 的 RSS 预览。
  ///
  /// [inputUrl] 为 RSS 或 Apple Podcasts 链接，同时用作 family key，
  /// 天然按来源缓存并防竞态。
  ///
  /// Copied from [podcastPreview].
  const PodcastPreviewFamily();

  /// 由订阅输入 URL 拉取单个 Podcast 的 RSS 预览。
  ///
  /// [inputUrl] 为 RSS 或 Apple Podcasts 链接，同时用作 family key，
  /// 天然按来源缓存并防竞态。
  ///
  /// Copied from [podcastPreview].
  PodcastPreviewProvider call(String inputUrl) {
    return PodcastPreviewProvider(inputUrl);
  }

  @override
  PodcastPreviewProvider getProviderOverride(
    covariant PodcastPreviewProvider provider,
  ) {
    return call(provider.inputUrl);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'podcastPreviewProvider';
}

/// 由订阅输入 URL 拉取单个 Podcast 的 RSS 预览。
///
/// [inputUrl] 为 RSS 或 Apple Podcasts 链接，同时用作 family key，
/// 天然按来源缓存并防竞态。
///
/// Copied from [podcastPreview].
class PodcastPreviewProvider
    extends AutoDisposeFutureProvider<PodcastPreviewData> {
  /// 由订阅输入 URL 拉取单个 Podcast 的 RSS 预览。
  ///
  /// [inputUrl] 为 RSS 或 Apple Podcasts 链接，同时用作 family key，
  /// 天然按来源缓存并防竞态。
  ///
  /// Copied from [podcastPreview].
  PodcastPreviewProvider(String inputUrl)
    : this._internal(
        (ref) => podcastPreview(ref as PodcastPreviewRef, inputUrl),
        from: podcastPreviewProvider,
        name: r'podcastPreviewProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$podcastPreviewHash,
        dependencies: PodcastPreviewFamily._dependencies,
        allTransitiveDependencies:
            PodcastPreviewFamily._allTransitiveDependencies,
        inputUrl: inputUrl,
      );

  PodcastPreviewProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.inputUrl,
  }) : super.internal();

  final String inputUrl;

  @override
  Override overrideWith(
    FutureOr<PodcastPreviewData> Function(PodcastPreviewRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PodcastPreviewProvider._internal(
        (ref) => create(ref as PodcastPreviewRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        inputUrl: inputUrl,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<PodcastPreviewData> createElement() {
    return _PodcastPreviewProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PodcastPreviewProvider && other.inputUrl == inputUrl;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, inputUrl.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PodcastPreviewRef on AutoDisposeFutureProviderRef<PodcastPreviewData> {
  /// The parameter `inputUrl` of this provider.
  String get inputUrl;
}

class _PodcastPreviewProviderElement
    extends AutoDisposeFutureProviderElement<PodcastPreviewData>
    with PodcastPreviewRef {
  _PodcastPreviewProviderElement(super.provider);

  @override
  String get inputUrl => (origin as PodcastPreviewProvider).inputUrl;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
