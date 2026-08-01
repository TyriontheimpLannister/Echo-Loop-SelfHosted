import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'homeschooling_package.dart';

const homeSchoolingBaseUrl = String.fromEnvironment(
  'HOMESCHOOLING_BASE_URL',
  defaultValue: 'http://192.168.123.187:18002',
);

const echoLoopApiBaseUrl = String.fromEnvironment(
  'ECHOLOOP_API_BASE',
  defaultValue: 'http://192.168.123.187:8000',
);

/// HomeSchooling 中可接收听写任务的孩子。
class HomeSchoolingChild {
  const HomeSchoolingChild({required this.slug, required this.name, this.id});

  final String slug;
  final String name;
  final int? id;
}

/// HomeSchooling 成功导入听写包后的摘要。
class HomeSchoolingTransferResult {
  const HomeSchoolingTransferResult({
    required this.taskName,
    required this.itemCount,
  });

  final String taskName;
  final int itemCount;
}

/// 可直接展示给用户的 HomeSchooling 传输错误。
class HomeSchoolingTransferException implements Exception {
  const HomeSchoolingTransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 通过家庭局域网把听写包直接写入 HomeSchooling 父端。
///
/// 家长密码仅作为本次请求头发送，不在 Echo Loop 中持久化。
class HomeSchoolingTransferService {
  HomeSchoolingTransferService({Dio? dio, String? baseUrl})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? homeSchoolingBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 60),
            ),
          );

  final Dio _dio;

  Future<List<HomeSchoolingChild>> loadChildren(String password) async {
    final response = await _request(
      () => _dio.get<dynamic>(
        '/parent/dictation/api/children',
        options: _authOptions(password),
      ),
    );
    final data = response.data;
    if (data is! List) {
      throw const HomeSchoolingTransferException('HomeSchooling 返回的孩子列表无法识别。');
    }
    final children = <HomeSchoolingChild>[];
    for (final entry in data) {
      if (entry is! Map) continue;
      final slug = entry['slug'];
      final name = entry['name'];
      if (slug is String &&
          slug.trim().isNotEmpty &&
          name is String &&
          name.trim().isNotEmpty) {
        children.add(
          HomeSchoolingChild(
            slug: slug.trim(),
            name: name.trim(),
            id: (entry['id'] as num?)?.toInt(),
          ),
        );
      }
    }
    if (children.isEmpty) {
      throw const HomeSchoolingTransferException('HomeSchooling 没有可用的孩子档案。');
    }
    return children;
  }

  Future<HomeSchoolingTransferResult> sendPackage({
    required HomeschoolingPackage package,
    required String password,
    required String childSlug,
  }) async {
    final response = await _request(
      () => _dio.post<dynamic>(
        '/parent/dictation/api/import-echo-loop',
        options: _authOptions(password),
        data: {
          'title': package.title,
          'child': childSlug,
          'lang': package.lang == 'zh' ? 'zh' : 'en',
          'voice': package.voice,
          'speed': package.speed,
          'items': package.items
              .map(
                (item) => {
                  'text': item.text,
                  'audio_format': item.audioFormat,
                  'audio_b64': item.audioBase64,
                },
              )
              .toList(growable: false),
        },
      ),
    );
    final data = response.data;
    if (data is! Map) {
      throw const HomeSchoolingTransferException('HomeSchooling 没有返回导入结果。');
    }
    final taskName = data['title'] ?? data['name'];
    final itemCount = data['items_count'];
    return HomeSchoolingTransferResult(
      taskName: taskName is String && taskName.trim().isNotEmpty
          ? taskName.trim()
          : package.title,
      itemCount: itemCount is int ? itemCount : package.items.length,
    );
  }

  Options _authOptions(String password) => Options(
    headers: {'X-Parent-Password': password},
    contentType: Headers.jsonContentType,
  );

  Future<Response<dynamic>> _request(
    Future<Response<dynamic>> Function() send,
  ) async {
    try {
      return await send();
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const HomeSchoolingTransferException('家长密码不正确。');
      }
      final detail = error.response?.data;
      if (detail is Map && detail['detail'] is String) {
        final message = (detail['detail'] as String).trim();
        if (message.isNotEmpty) {
          throw HomeSchoolingTransferException(message);
        }
      }
      throw const HomeSchoolingTransferException(
        '无法连接 HomeSchooling，请确认学习机和服务器在同一家庭网络。',
      );
    }
  }
}

final homeSchoolingTransferServiceProvider =
    Provider<HomeSchoolingTransferService>(
      (ref) => HomeSchoolingTransferService(),
    );
