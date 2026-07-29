import 'package:dio/dio.dart';
import 'package:echo_loop/features/audio_import/homeschooling_package_receiver_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('receives the latest completed HomeSchooling task with parent auth',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://homeschooling.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          final data = options.path == '/parent/dictation/api/tasks'
              ? [
                  {'id': 7, 'status': 'done'},
                  {'id': 9, 'status': 'done'},
                ]
              : {
                  'version': 1,
                  'source_app': 'homeschooling',
                  'source_id': 'task:9',
                  'title': 'Latest task',
                  'child_slug': 'learner-a',
                  'lang': 'en',
                  'voice': '',
                  'speed': 1.0,
                  'content_mode': 'sentences',
                  'items': [
                    {
                      'text': 'Hello.',
                      'audio_format': 'mp3',
                      'audio_b64': 'aGVsbG8=',
                      'transcript_verified': true,
                      'source': 'tts',
                      'order': 0,
                    },
                  ],
                  'skipped_count': 0,
                };
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );

    final result = await HomeSchoolingPackageReceiverService(dio: dio)
        .receiveLatestPackage(
      password: 'parent-password',
      contentMode: 'sentences',
    );

    expect(requests.map((request) => request.path), [
      '/parent/dictation/api/tasks',
      '/parent/dictation/api/tasks/9/export-echo-loop',
    ]);
    expect(
      requests.every(
        (request) => request.headers['X-Parent-Password'] == 'parent-password',
      ),
      isTrue,
    );
    expect(requests.last.queryParameters['content_mode'], 'sentences');
    expect(result.package.title, 'Latest task');
  });
}
