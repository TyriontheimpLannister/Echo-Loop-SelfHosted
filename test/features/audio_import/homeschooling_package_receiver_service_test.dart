import 'package:dio/dio.dart';
import 'package:echo_loop/features/audio_import/homeschooling_package_receiver_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'receives the latest completed HomeSchooling task with parent auth',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://homeschooling.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            final data = options.path == '/parent/dictation/api/tasks'
                ? [
                    {
                      'id': 7,
                      'name': 'Older task',
                      'status': 'done',
                      'total_items': 1,
                    },
                    {
                      'id': 9,
                      'name': 'Latest task',
                      'status': 'done',
                      'total_items': 1,
                    },
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
          (request) =>
              request.headers['X-Parent-Password'] == 'parent-password',
        ),
        isTrue,
      );
      expect(requests.last.queryParameters['content_mode'], 'sentences');
      expect(result.package.title, 'Latest task');
    },
  );

  test('filters completed tasks to the selected HomeSchooling child', () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://homeschooling.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          final data = options.path == '/parent/dictation/api/tasks'
              ? [
                  {'id': 8, 'status': 'done', 'child_id': 2},
                  {'id': 9, 'status': 'done', 'child_id': 1},
                ]
              : {
                  'version': 1,
                  'source_app': 'homeschooling',
                  'source_id': 'task:9',
                  'title': 'Naomi task',
                  'child_slug': 'learner-a',
                  'lang': 'en',
                  'items': [
                    {
                      'text': 'Hello.',
                      'audio_format': 'mp3',
                      'audio_b64': 'aGVsbG8=',
                      'transcript_verified': true,
                    },
                  ],
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
          childSlug: 'learner-a',
          childId: 1,
        );

    expect(
      requests.last.path,
      '/parent/dictation/api/tasks/9/export-echo-loop',
    );
    expect(result.package.childSlug, 'learner-a');
  });

  test(
    'loads all selected-child tasks and marks only ready tasks importable',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://homeschooling.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: [
                  {
                    'id': 12,
                    'name': 'Ready lesson',
                    'child_id': 1,
                    'status': 'done',
                    'total_items': 4,
                    'created_at': '2026-07-31T10:00:00',
                  },
                  {
                    'id': 11,
                    'name': 'Generating lesson',
                    'child_id': 1,
                    'status': 'pending',
                    'total_items': 4,
                    'archived_at': '2026-07-31T11:00:00',
                  },
                  {
                    'id': 10,
                    'name': 'Other child',
                    'child_id': 2,
                    'status': 'done',
                    'total_items': 2,
                  },
                ],
              ),
            );
          },
        ),
      );

      final tasks = await HomeSchoolingPackageReceiverService(
        dio: dio,
      ).loadTasks(password: 'parent-password', childId: 1);

      expect(tasks.map((task) => task.name), [
        'Ready lesson',
        'Generating lesson',
      ]);
      expect(tasks.first.canImport, isTrue);
      expect(tasks.last.canImport, isFalse);
      expect(tasks.last.isArchived, isTrue);
    },
  );
}
