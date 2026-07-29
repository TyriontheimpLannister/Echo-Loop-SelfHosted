// 从 HomeSchooling 父端在线拉取听写包。
//
// 两端仍保持独立，这里只做「拿包 + 转 Echo Loop 可导入结构」的薄适配，
// 不把 HomeSchooling 数据库或账号体系引入 Echo Loop。
library;

import 'package:dio/dio.dart';
import 'homeschooling_package.dart';
import 'homeschooling_transfer_service.dart';

class EchoLoopPackageReceiveResult {
  const EchoLoopPackageReceiveResult({required this.package});

  final HomeschoolingPackage package;
}

class EchoLoopPackageReceiveException implements Exception {
  const EchoLoopPackageReceiveException(this.message);
  final String message;
  @override
  String toString() => message;
}

class HomeSchoolingPackageReceiveResult {
  const HomeSchoolingPackageReceiveResult({
    required this.package,
    this.filePath,
  });

  final HomeschoolingPackage package;
  final String? filePath;
}

class HomeSchoolingPackageReceiveException implements Exception {
  const HomeSchoolingPackageReceiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HomeSchoolingPackageReceiverService {
  HomeSchoolingPackageReceiverService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: homeSchoolingBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 60),
            ),
          );

  static const String _exportPath =
      '/parent/dictation/api/tasks/{task_id}/export-echo-loop';

  final Dio _dio;

  Future<EchoLoopPackageReceiveResult> receiveFromEchoLoopBackend() async {
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '/api/v1/homeschooling/package/latest',
        options: Options(headers: {'Accept': 'application/json'}),
      ),
    );
    final data = response.data;
    if (data is! Map<String, dynamic> ||
        data['package'] is! Map<String, dynamic>) {
      throw const EchoLoopPackageReceiveException('Echo Loop 返回的听写包格式无法识别。');
    }
    final package = HomeschoolingPackage.tryParse(
      data['package'] as Map<String, dynamic>,
    );
    if (package == null) {
      throw const EchoLoopPackageReceiveException('Echo Loop 返回了未知版本的听写包。');
    }
    if (package.items.isEmpty) {
      throw const EchoLoopPackageReceiveException('当前还没有可导入的听写包。');
    }
    return EchoLoopPackageReceiveResult(package: package);
  }

  Future<HomeSchoolingPackageReceiveResult> receiveLatestPackage({
    required String password,
    required String contentMode,
  }) async {
    final taskId = await _pickLatestFinishedTaskId(password);
    final escapedTaskId = Uri.encodeComponent(taskId.toString());
    final path = _exportPath.replaceAll('{task_id}', escapedTaskId);
    final response = await _request(
      () => _dio.get<dynamic>(
        path,
        options: Options(headers: {'X-Parent-Password': password}),
        queryParameters: {'content_mode': contentMode},
      ),
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const HomeSchoolingPackageReceiveException(
        'HomeSchooling 返回的听写包格式无法识别。',
      );
    }
    final package = HomeschoolingPackage.tryParse(data);
    if (package == null) {
      throw const HomeSchoolingPackageReceiveException(
        'HomeSchooling 返回了未知版本的听写包。',
      );
    }
    if (package.items.isEmpty) {
      throw const HomeSchoolingPackageReceiveException('这个任务还没有可导入的句子音频。');
    }
    return HomeSchoolingPackageReceiveResult(package: package);
  }

  Future<int> _pickLatestFinishedTaskId(String password) async {
    final taskResponse = await _request(
      () => _dio.get<dynamic>(
        '/parent/dictation/api/tasks',
        options: Options(headers: {'X-Parent-Password': password}),
      ),
    );
    if (taskResponse.data is! List) {
      throw const HomeSchoolingPackageReceiveException(
        'HomeSchooling 返回的任务列表无法识别。',
      );
    }
    final tasks = <Map<String, dynamic>>[];
    for (final entry in taskResponse.data as List) {
      if (entry is Map<String, dynamic> && entry['status'] == 'done') {
        tasks.add(entry);
      }
    }
    tasks.sort(
      (a, b) => ((b['id'] as num?)?.toInt() ?? 0).compareTo(
        (a['id'] as num?)?.toInt() ?? 0,
      ),
    );
    if (tasks.isEmpty) {
      throw const HomeSchoolingPackageReceiveException('当前孩子还没有已完成的听写任务。');
    }
    return (tasks.first['id'] as num).toInt();
  }

  Future<Response<dynamic>> _request(
    Future<Response<dynamic>> Function() send,
  ) async {
    try {
      return await send();
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const HomeSchoolingPackageReceiveException('家长密码不正确。');
      }
      final detail = error.response?.data;
      if (detail is Map && detail['detail'] is String) {
        final message = (detail['detail'] as String).trim();
        if (message.isNotEmpty) {
          throw HomeSchoolingPackageReceiveException(message);
        }
      }
      throw const HomeSchoolingPackageReceiveException(
        '无法连接 HomeSchooling，请确认学习机和服务器在同一家庭网络。',
      );
    }
  }
}
