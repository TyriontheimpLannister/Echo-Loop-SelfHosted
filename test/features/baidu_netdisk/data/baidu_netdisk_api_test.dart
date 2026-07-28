import 'package:dio/dio.dart';
import 'package:echo_loop/features/baidu_netdisk/data/baidu_netdisk_api.dart';
import 'package:echo_loop/features/baidu_netdisk/models/cloud_drive_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockDio metadataDio;
  late _MockDio downloadDio;
  late DefaultBaiduNetdiskApi api;

  setUp(() {
    metadataDio = _MockDio();
    downloadDio = _MockDio();
    api = DefaultBaiduNetdiskApi(
      metadataDio: metadataDio,
      downloadDio: downloadDio,
    );
  });

  Response<Object?> jsonResponse(Object? data) => Response<Object?>(
    requestOptions: RequestOptions(path: '/'),
    statusCode: 200,
    data: data,
  );

  group('DefaultBaiduNetdiskApi', () {
    test('listDirectory 调用百度列表接口并解析目录/文件', () async {
      when(
        () => metadataDio.get<Object?>(
          '/rest/2.0/xpan/file',
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => jsonResponse({
          'errno': 0,
          'list': [
            {
              'fs_id': 1,
              'server_filename': 'Folder',
              'path': '/Folder',
              'isdir': 1,
              'size': 0,
              'server_mtime': 1784361000,
            },
            {
              'fs_id': '2',
              'server_filename': 'lesson.mp3',
              'path': '/Folder/lesson.mp3',
              'isdir': 0,
              'size': '123',
            },
          ],
        }),
      );

      final page = await api.listDirectory(
        accessToken: 'access-token',
        dir: '/Folder',
        start: 5,
        limit: 2,
      );

      expect(page.entries, hasLength(2));
      expect(page.entries.first.isDirectory, isTrue);
      expect(page.entries[1].name, 'lesson.mp3');
      expect(page.entries[1].extension, 'mp3');
      expect(page.nextStart, 7);
      expect(page.hasMore, isTrue);

      final query =
          verify(
                () => metadataDio.get<Object?>(
                  '/rest/2.0/xpan/file',
                  queryParameters: captureAny(named: 'queryParameters'),
                  options: any(named: 'options'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(query['method'], 'list');
      expect(query['access_token'], 'access-token');
      expect(query['dir'], '/Folder');
      expect(query['start'], 5);
      expect(query['limit'], 2);
    });

    test('fetchDownloadLink 调用 filemetas 并解析 dlink', () async {
      when(
        () => metadataDio.get<Object?>(
          '/rest/2.0/xpan/multimedia',
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => jsonResponse({
          'errno': 0,
          'list': [
            {
              'fs_id': 42,
              'server_filename': 'lesson.m4a',
              'size': 456,
              'dlink': 'https://d.pcs.baidu.com/file/lesson',
            },
          ],
        }),
      );

      final link = await api.fetchDownloadLink(
        accessToken: 'access-token',
        fsId: 42,
      );

      expect(link.fsId, 42);
      expect(link.dlink, 'https://d.pcs.baidu.com/file/lesson');
      expect(link.size, 456);

      final query =
          verify(
                () => metadataDio.get<Object?>(
                  '/rest/2.0/xpan/multimedia',
                  queryParameters: captureAny(named: 'queryParameters'),
                  options: any(named: 'options'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(query['fsids'], '[42]');
      expect(query['dlink'], 1);
    });

    test('百度 errno -6 映射为 unauthorized', () async {
      when(
        () => metadataDio.get<Object?>(
          '/rest/2.0/xpan/file',
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async =>
            jsonResponse({'errno': -6, 'errmsg': 'invalid access token'}),
      );

      expect(
        api.listDirectory(accessToken: 'bad'),
        throwsA(
          isA<BaiduNetdiskFileException>().having(
            (error) => error.kind,
            'kind',
            BaiduNetdiskFileErrorKind.unauthorized,
          ),
        ),
      );
    });

    test('downloadToFile 给 dlink 补 access_token 并带百度 UA', () async {
      when(
        () => downloadDio.download(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
          options: any(named: 'options'),
          onReceiveProgress: any(named: 'onReceiveProgress'),
        ),
      ).thenAnswer(
        (_) async => Response<void>(requestOptions: RequestOptions()),
      );

      await api.downloadToFile(
        accessToken: 'access-token',
        dlink: 'https://d.pcs.baidu.com/file/lesson?x=1',
        savePath: '/tmp/lesson.mp3',
      );

      final captured = verify(
        () => downloadDio.download(
          captureAny(),
          '/tmp/lesson.mp3',
          cancelToken: any(named: 'cancelToken'),
          options: captureAny(named: 'options'),
          onReceiveProgress: any(named: 'onReceiveProgress'),
        ),
      ).captured;
      final uri = Uri.parse(captured[0] as String);
      final options = captured[1] as Options;
      expect(uri.queryParameters['x'], '1');
      expect(uri.queryParameters['access_token'], 'access-token');
      expect(options.headers?['User-Agent'], 'pan.baidu.com');
    });
  });
}
