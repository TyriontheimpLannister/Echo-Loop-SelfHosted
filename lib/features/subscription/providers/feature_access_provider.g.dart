// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'feature_access_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$featureAccessHash() => r'8e8907be031be64d4ce32c74c9ee00af4cfe1b3d';

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

/// 某 [feature] 当前是否对用户可用。
///
/// Copied from [featureAccess].
@ProviderFor(featureAccess)
const featureAccessProvider = FeatureAccessFamily();

/// 某 [feature] 当前是否对用户可用。
///
/// Copied from [featureAccess].
class FeatureAccessFamily extends Family<bool> {
  /// 某 [feature] 当前是否对用户可用。
  ///
  /// Copied from [featureAccess].
  const FeatureAccessFamily();

  /// 某 [feature] 当前是否对用户可用。
  ///
  /// Copied from [featureAccess].
  FeatureAccessProvider call(PremiumFeature feature) {
    return FeatureAccessProvider(feature);
  }

  @override
  FeatureAccessProvider getProviderOverride(
    covariant FeatureAccessProvider provider,
  ) {
    return call(provider.feature);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'featureAccessProvider';
}

/// 某 [feature] 当前是否对用户可用。
///
/// Copied from [featureAccess].
class FeatureAccessProvider extends AutoDisposeProvider<bool> {
  /// 某 [feature] 当前是否对用户可用。
  ///
  /// Copied from [featureAccess].
  FeatureAccessProvider(PremiumFeature feature)
    : this._internal(
        (ref) => featureAccess(ref as FeatureAccessRef, feature),
        from: featureAccessProvider,
        name: r'featureAccessProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$featureAccessHash,
        dependencies: FeatureAccessFamily._dependencies,
        allTransitiveDependencies:
            FeatureAccessFamily._allTransitiveDependencies,
        feature: feature,
      );

  FeatureAccessProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.feature,
  }) : super.internal();

  final PremiumFeature feature;

  @override
  Override overrideWith(bool Function(FeatureAccessRef provider) create) {
    return ProviderOverride(
      origin: this,
      override: FeatureAccessProvider._internal(
        (ref) => create(ref as FeatureAccessRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        feature: feature,
      ),
    );
  }

  @override
  AutoDisposeProviderElement<bool> createElement() {
    return _FeatureAccessProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is FeatureAccessProvider && other.feature == feature;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, feature.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin FeatureAccessRef on AutoDisposeProviderRef<bool> {
  /// The parameter `feature` of this provider.
  PremiumFeature get feature;
}

class _FeatureAccessProviderElement extends AutoDisposeProviderElement<bool>
    with FeatureAccessRef {
  _FeatureAccessProviderElement(super.provider);

  @override
  PremiumFeature get feature => (origin as FeatureAccessProvider).feature;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
