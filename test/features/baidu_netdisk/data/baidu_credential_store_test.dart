import 'package:echo_loop/features/baidu_netdisk/data/baidu_credential_store.dart';
import 'package:echo_loop/features/baidu_netdisk/models/baidu_credential_bundle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockSecureStorage storage;
  late SecureBaiduCredentialStore store;

  BaiduCredentialBundle credential() => BaiduCredentialBundle(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: DateTime.utc(2026, 8, 17, 12),
    scope: 'basic,netdisk',
  );

  setUp(() {
    storage = _MockSecureStorage();
    store = SecureBaiduCredentialStore(
      storage: storage,
      platform: TargetPlatform.macOS,
    );
  });

  group('SecureBaiduCredentialStore', () {
    test('write 后 read 往返完整 bundle', () async {
      String? saved;
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((invocation) async {
        final raw = invocation.namedArguments[const Symbol('value')];
        if (raw is String) saved = raw;
      });
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => saved);

      await store.write(credential());
      final restored = await store.read();

      expect(restored?.accessToken, 'access');
      expect(restored?.refreshToken, 'refresh');
      expect(restored?.expiresAt, DateTime.utc(2026, 8, 17, 12));
    });

    test('无缓存返回 null', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => null);

      expect(await store.read(), isNull);
    });

    test('缓存损坏抛 parseFailed，避免继续使用坏凭证', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => '{bad');

      expect(
        store.read(),
        throwsA(
          isA<BaiduCredentialStoreException>().having(
            (error) => error.kind,
            'kind',
            BaiduCredentialStoreErrorKind.parseFailed,
          ),
        ),
      );
    });

    test('Linux secure storage 不可用时返回明确 unavailable，不明文降级', () async {
      store = SecureBaiduCredentialStore(
        storage: storage,
        platform: TargetPlatform.linux,
      );
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenThrow(PlatformException(code: 'SecretServiceNotAvailable'));

      expect(
        store.write(credential()),
        throwsA(
          isA<BaiduCredentialStoreException>().having(
            (error) => error.kind,
            'kind',
            BaiduCredentialStoreErrorKind.unavailable,
          ),
        ),
      );
    });

    test('clear 调用 secure storage delete', () async {
      when(
        () => storage.delete(key: any(named: 'key')),
      ).thenAnswer((_) async {});

      await store.clear();

      verify(() => storage.delete(key: any(named: 'key'))).called(1);
    });
  });
}
