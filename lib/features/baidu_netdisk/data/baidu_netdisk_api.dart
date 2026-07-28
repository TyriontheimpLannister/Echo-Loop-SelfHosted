/// 百度网盘文件 API 客户端。
///
/// 只访问百度开放平台域名，不复用自家后端 Dio。请求统一把 access_token 放在
/// query 中，并由 ApiLogInterceptor 脱敏，避免凭据进入开发者日志。
library;

import 'package:dio/dio.dart';

import '../../../services/api_log_interceptor.dart';
import '../models/cloud_drive_models.dart';

/// 百度网盘文件 API 抽象。
abstract interface class BaiduNetdiskApi {
  /// 列出目录。
  Future<CloudDriveListPage> listDirectory({
    required String accessToken,
    String dir = '/',
    int start = 0,
    int limit = 100,
  });

  /// 获取文件下载 dlink。
  Future<BaiduDownloadLink> fetchDownloadLink({
    required String accessToken,
    required int fsId,
  });

  /// 下载 dlink 到本地文件。
  Future<void> downloadToFile({
    required String accessToken,
    required String dlink,
    required String savePath,
    int? expectedSize,
    CancelToken? cancelToken,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  });
}

/// 默认百度网盘文件 API 实现。
class DefaultBaiduNetdiskApi implements BaiduNetdiskApi {
  /// 构造默认实现。
  DefaultBaiduNetdiskApi({Dio? metadataDio, Dio? downloadDio})
    : _metadataDio = metadataDio ?? _createMetadataDio(),
      _downloadDio = downloadDio ?? _createDownloadDio();

  final Dio _metadataDio;
  final Dio _downloadDio;

  static Dio _createMetadataDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://pan.baidu.com',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {'User-Agent': _baiduUserAgent},
      ),
    );
    dio.interceptors.add(ApiLogInterceptor(tag: 'BAIDU-NETDISK'));
    return dio;
  }

  static Dio _createDownloadDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 10),
        headers: const {'User-Agent': _baiduUserAgent},
      ),
    );
    dio.interceptors.add(ApiLogInterceptor(tag: 'BAIDU-DOWNLOAD'));
    return dio;
  }

  @override
  Future<CloudDriveListPage> listDirectory({
    required String accessToken,
    String dir = '/',
    int start = 0,
    int limit = 100,
  }) async {
    final normalizedLimit = limit.clamp(1, 1000);
    final data = await _getJson(
      '/rest/2.0/xpan/file',
      queryParameters: <String, Object?>{
        'method': 'list',
        'access_token': accessToken,
        'dir': dir.isEmpty ? '/' : dir,
        'order': 'name',
        'start': start < 0 ? 0 : start,
        'limit': normalizedLimit,
        'web': 1,
        'folder': 0,
        'desc': 0,
      },
    );
    final list = data['list'];
    if (list is! List) {
      throw const BaiduNetdiskFileException(
        kind: BaiduNetdiskFileErrorKind.unknown,
        message: 'Baidu list response is missing file list.',
      );
    }
    final entries = list
        .whereType<Map>()
        .map(CloudDriveEntry.fromBaiduJson)
        .toList(growable: false);
    return CloudDriveListPage(
      entries: entries,
      nextStart: (start < 0 ? 0 : start) + entries.length,
      hasMore: entries.length >= normalizedLimit,
    );
  }

  @override
  Future<BaiduDownloadLink> fetchDownloadLink({
    required String accessToken,
    required int fsId,
  }) async {
    final data = await _getJson(
      '/rest/2.0/xpan/multimedia',
      queryParameters: <String, Object?>{
        'method': 'filemetas',
        'access_token': accessToken,
        'fsids': '[$fsId]',
        'dlink': 1,
      },
    );
    final list = data['list'];
    if (list is! List || list.isEmpty || list.first is! Map) {
      throw const BaiduNetdiskFileException(
        kind: BaiduNetdiskFileErrorKind.notFound,
        message: 'Baidu download link is unavailable.',
      );
    }
    final link = BaiduDownloadLink.fromBaiduJson(list.first as Map);
    if (link.dlink.isEmpty) {
      throw const BaiduNetdiskFileException(
        kind: BaiduNetdiskFileErrorKind.notFound,
        message: 'Baidu download link is empty.',
      );
    }
    return link;
  }

  @override
  Future<void> downloadToFile({
    required String accessToken,
    required String dlink,
    required String savePath,
    int? expectedSize,
    CancelToken? cancelToken,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final uri = Uri.parse(dlink);
    final downloadUri = uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        'access_token': accessToken,
      },
    );
    try {
      await _downloadDio.download(
        downloadUri.toString(),
        savePath,
        cancelToken: cancelToken,
        options: Options(
          followRedirects: true,
          headers: const {'User-Agent': _baiduUserAgent},
        ),
        onReceiveProgress: (received, total) {
          onProgress?.call(received, total > 0 ? total : expectedSize);
        },
      );
    } on DioException catch (error) {
      throw _mapDioException(error, fallbackMessage: 'Baidu download failed.');
    }
  }

  Future<Map<dynamic, dynamic>> _getJson(
    String path, {
    required Map<String, Object?> queryParameters,
  }) async {
    try {
      final response = await _metadataDio.get<Object?>(
        path,
        queryParameters: queryParameters,
        options: Options(validateStatus: (_) => true),
      );
      final data = response.data;
      if (data is! Map) {
        throw const BaiduNetdiskFileException(
          kind: BaiduNetdiskFileErrorKind.unknown,
          message: 'Baidu response is not a JSON object.',
        );
      }
      _throwIfBaiduError(data);
      return data;
    } on DioException catch (error) {
      throw _mapDioException(error, fallbackMessage: 'Baidu request failed.');
    }
  }

  void _throwIfBaiduError(Map<dynamic, dynamic> data) {
    final errno = _errnoOf(data['errno']);
    if (errno == null || errno == 0) return;
    final message =
        data['errmsg'] as String? ??
        data['error_msg'] as String? ??
        data['error_description'] as String? ??
        'Baidu request failed.';
    throw BaiduNetdiskFileException(
      kind: _kindForErrno(errno),
      message: message,
      errno: errno,
    );
  }

  BaiduNetdiskFileException _mapDioException(
    DioException error, {
    required String fallbackMessage,
  }) {
    if (CancelToken.isCancel(error)) {
      return const BaiduNetdiskFileException(
        kind: BaiduNetdiskFileErrorKind.canceled,
        message: 'Baidu request canceled.',
      );
    }
    final statusCode = error.response?.statusCode;
    final kind = switch (statusCode) {
      401 || 403 => BaiduNetdiskFileErrorKind.unauthorized,
      404 => BaiduNetdiskFileErrorKind.notFound,
      429 => BaiduNetdiskFileErrorKind.rateLimited,
      _ => BaiduNetdiskFileErrorKind.network,
    };
    return BaiduNetdiskFileException(
      kind: kind,
      message: fallbackMessage,
      cause: error,
    );
  }

  int? _errnoOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  BaiduNetdiskFileErrorKind _kindForErrno(int errno) {
    return switch (errno) {
      -6 || 111 || 110 => BaiduNetdiskFileErrorKind.unauthorized,
      -9 || 31066 => BaiduNetdiskFileErrorKind.notFound,
      31045 || 31046 || 31061 => BaiduNetdiskFileErrorKind.rateLimited,
      2 || 31023 => BaiduNetdiskFileErrorKind.badRequest,
      _ => BaiduNetdiskFileErrorKind.unknown,
    };
  }
}

const _baiduUserAgent = 'pan.baidu.com';
