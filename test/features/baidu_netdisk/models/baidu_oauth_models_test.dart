import 'dart:convert';

import 'package:echo_loop/features/baidu_netdisk/models/baidu_credential_bundle.dart';
import 'package:echo_loop/features/baidu_netdisk/models/baidu_netdisk_error.dart';
import 'package:echo_loop/features/baidu_netdisk/models/baidu_oauth_session.dart';
import 'package:echo_loop/features/baidu_netdisk/models/baidu_oauth_session_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Baidu OAuth DTO', () {
    test('BaiduOAuthSession 正常解析', () {
      final session = BaiduOAuthSession.fromJson({
        'sessionId': 'sid',
        'pollToken': 'poll',
        'authorizationUrl': 'https://openapi.baidu.com/oauth/2.0/authorize',
        'expiresAt': '2026-07-18T12:00:00Z',
        'pollIntervalSeconds': 2,
      });

      expect(session.sessionId, 'sid');
      expect(session.pollToken, 'poll');
      expect(session.authorizationUri.host, 'openapi.baidu.com');
      expect(session.expiresAt, DateTime.utc(2026, 7, 18, 12));
      expect(session.pollInterval, const Duration(seconds: 2));
    });

    test('BaiduOAuthSession 畸形 JSON 抛 FormatException', () {
      expect(
        () => BaiduOAuthSession.fromJson({
          'sessionId': 'sid',
          'pollToken': 'poll',
          'authorizationUrl': 'not a uri',
          'expiresAt': '2026-07-18T12:00:00Z',
          'pollIntervalSeconds': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => BaiduOAuthSession.fromJson(<String, Object?>{
          'sessionId': 'sid',
          'pollToken': '',
          'authorizationUrl': 'https://example.com',
          'expiresAt': 'bad',
          'pollIntervalSeconds': 0,
        }),
        throwsFormatException,
      );
    });

    test('BaiduCredentialBundle 正常解析并提前 5 分钟视为过期', () {
      final credential = BaiduCredentialBundle.fromJson({
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'expiresAt': '2026-07-18T12:10:00Z',
        'scope': 'basic,netdisk',
      });

      expect(credential.accessToken, 'access');
      expect(
        credential.isAccessTokenUsable(DateTime.utc(2026, 7, 18, 12, 4)),
        isTrue,
      );
      expect(
        credential.isAccessTokenUsable(DateTime.utc(2026, 7, 18, 12, 5)),
        isFalse,
      );
      expect(
        BaiduCredentialBundle.decode(jsonEncode(credential.toJson())).scope,
        'basic,netdisk',
      );
    });

    test('BaiduOAuthSessionStatus completed 必须带 credential', () {
      final status = BaiduOAuthSessionStatus.fromJson({
        'status': 'completed',
        'credential': {
          'accessToken': 'access',
          'refreshToken': 'refresh',
          'expiresAt': '2026-08-17T12:00:00Z',
          'scope': 'basic,netdisk',
        },
      });

      expect(status.phase, BaiduOAuthSessionPhase.completed);
      expect(status.credential?.refreshToken, 'refresh');
      expect(() {
        BaiduOAuthSessionStatus.fromJson({'status': 'completed'});
      }, throwsFormatException);
    });

    test('错误体映射稳定错误码，未知码降级 unknown', () {
      final status = BaiduOAuthSessionStatus.fromJson({
        'status': 'failed',
        'error': {'code': 'scope_missing', 'message': 'Scope missing.'},
      });

      expect(status.phase, BaiduOAuthSessionPhase.failed);
      expect(status.error?.code, BaiduNetdiskOAuthErrorCode.scopeMissing);
      expect(
        BaiduNetdiskOAuthErrorCode.fromWireName('new_error'),
        BaiduNetdiskOAuthErrorCode.unknown,
      );
    });
  });
}
