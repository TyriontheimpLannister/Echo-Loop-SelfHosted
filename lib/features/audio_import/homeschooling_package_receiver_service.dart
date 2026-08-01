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

/// HomeSchooling 父端任务列表中的一项。
class HomeSchoolingTask {
  const HomeSchoolingTask({
    required this.id,
    required this.name,
    required this.childId,
    required this.status,
    required this.totalItems,
    this.createdAt,
    this.archivedAt,
  });

  final int id;
  final String name;
  final int? childId;
  final String status;
  final int totalItems;
  final DateTime? createdAt;
  final DateTime? archivedAt;

  bool get canImport => status == 'done' && totalItems > 0;
  bool get isArchived => archivedAt != null;
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
    String? childSlug,
    int? childId,
  }) async {
    final tasks = await loadTasks(
      password: password,
      childSlug: childSlug,
      childId: childId,
    );
    final importableTasks = tasks
        .where((task) => task.status == 'done')
        .toList();
    if (importableTasks.isEmpty) {
      throw const HomeSchoolingPackageReceiveException('当前孩子还没有已完成的听写任务。');
    }
    return receiveTaskPackage(
      taskId: importableTasks.first.id,
      password: password,
      contentMode: contentMode,
      childSlug: childSlug,
    );
  }

  /// 读取当前孩子的全部任务；未完成任务也返回给 UI，但不可选择导入。
  Future<List<HomeSchoolingTask>> loadTasks({
    required String password,
    String? childSlug,
    int? childId,
  }) async {
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
    final tasks = <HomeSchoolingTask>[];
    for (final entry in taskResponse.data as List) {
      if (entry is! Map<String, dynamic>) continue;
      final id = (entry['id'] as num?)?.toInt();
      if (id == null) continue;
      // HomeSchooling 当前父端任务列表只返回 child_id；slug 仅保留给旧接口兼容。
      final taskChildId = (entry['child_id'] as num?)?.toInt();
      if (childId != null) {
        if (taskChildId != childId) continue;
      } else if (childSlug != null) {
        final taskChild =
            entry['child_slug'] ?? entry['child'] ?? entry['childSlug'];
        if (taskChild is! String || taskChild != childSlug) continue;
      }
      tasks.add(
        HomeSchoolingTask(
          id: id,
          name: _taskName(entry, id),
          childId: taskChildId,
          status: entry['status'] is String
              ? (entry['status'] as String).trim()
              : 'unknown',
          totalItems: (entry['total_items'] as num?)?.toInt() ?? 0,
          createdAt: _parseDate(entry['created_at']),
          archivedAt: _parseDate(entry['archived_at']),
        ),
      );
    }
    tasks.sort((a, b) => b.id.compareTo(a.id));
    return tasks;
  }

  /// 拉取用户明确选择的单个任务包。
  Future<HomeSchoolingPackageReceiveResult> receiveTaskPackage({
    required int taskId,
    required String password,
    required String contentMode,
    String? childSlug,
  }) async {
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
    if (childSlug != null && package.childSlug != childSlug) {
      throw const HomeSchoolingPackageReceiveException('收到的任务不属于当前学习者，已停止导入。');
    }
    if (package.items.isEmpty) {
      throw const HomeSchoolingPackageReceiveException('这个任务还没有可导入的句子音频。');
    }
    return HomeSchoolingPackageReceiveResult(package: package);
  }

  static String _taskName(Map<String, dynamic> entry, int id) {
    final name = entry['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    return '听写任务 $id';
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
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
