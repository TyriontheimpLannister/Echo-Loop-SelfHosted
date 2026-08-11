import 'package:dio/dio.dart';
import 'package:echo_loop/features/audio_import/homeschooling_package.dart';
import 'package:echo_loop/features/audio_import/homeschooling_transfer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads children with the parent password header', () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'http://homeschooling.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: [
                {'id': 1, 'slug': 'learner-a', 'name': 'Learner A'},
                {'id': 2, 'slug': 'learner-b', 'name': 'Learner B'},
              ],
            ),
          );
        },
      ),
    );

    final children = await HomeSchoolingTransferService(
      dio: dio,
    ).loadChildren('parent-password');

    expect(captured.path, '/parent/dictation/api/children');
    expect(captured.headers['X-Parent-Password'], 'parent-password');
    expect(children.map((child) => child.slug), ['learner-a', 'learner-b']);
    expect(children.map((child) => child.id), [1, 2]);
  });

  test('sends the generated package directly to the selected child', () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'http://homeschooling.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'name': 'Lesson', 'items_count': 1},
            ),
          );
        },
      ),
    );
    final package = HomeschoolingPackage(
      version: 1,
      sourceApp: 'echoloop',
      sourceId: 'audio:a1',
      title: 'Lesson',
      childSlug: '',
      lang: 'en',
      voice: '',
      speed: 1,
      items: const [
        HomeschoolingPackageItem(
          text: 'Hello.',
          audioFormat: 'm4a',
          audioBase64: 'aGVsbG8=',
          transcriptVerified: true,
          source: 'echoloop_a1',
          order: 0,
        ),
      ],
    );

    final result = await HomeSchoolingTransferService(dio: dio).sendPackage(
      package: package,
      password: 'parent-password',
      childSlug: 'learner-a',
    );

    final body = captured.data as Map<String, dynamic>;
    final items = body['items'] as List<dynamic>;
    final item = items.single as Map<String, dynamic>;
    expect(captured.path, '/parent/dictation/api/import-echo-loop');
    expect(captured.method, 'POST');
    expect(body['child'], 'learner-a');
    expect(item['audio_format'], 'm4a');
    expect(item['audio_b64'], 'aGVsbG8=');
    expect(result.taskName, 'Lesson');
    expect(result.itemCount, 1);
  });

  test('maps a rejected parent password to an actionable message', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://homeschooling.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 401,
                data: {'detail': '家长密码不正确。'},
              ),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );

    expect(
      () => HomeSchoolingTransferService(dio: dio).loadChildren('wrong'),
      throwsA(
        isA<HomeSchoolingTransferException>().having(
          (error) => error.message,
          'message',
          '家长密码不正确。',
        ),
      ),
    );
  });

  test('maps a missing import endpoint to a local actionable message', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://homeschooling.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 404,
                data: {'detail': 'Not Found'},
              ),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );

    expect(
      () => HomeSchoolingTransferService(dio: dio).loadChildren('parent-password'),
      throwsA(
        isA<HomeSchoolingTransferException>().having(
          (error) => error.message,
          'message',
          'HomeSchooling 听写接口不存在，请确认 HomeSchooling 服务地址正确且为最新版本。',
        ),
      ),
    );
  });
}
