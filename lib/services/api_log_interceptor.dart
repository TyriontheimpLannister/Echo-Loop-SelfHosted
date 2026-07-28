/// Dio 拦截器：打印完整的 API 请求/响应/错误日志
///
/// 默认的 [LogInterceptor] 在 `responseBody: false` 时不会打印服务器返回的
/// 响应体，且无法体现耗时，导致 AI 转录/解析等接口排查困难。
///
/// 此拦截器对每个请求输出三类日志：
/// - [onRequest]：`→ 方法 URL`（携带请求体摘要）
/// - [onResponse]：`← 方法 URL 状态码 (耗时 ms)`（携带响应体摘要）
/// - [onError]：完整诊断信息（状态码、错误类型、**服务器响应体**、耗时）
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'app_logger.dart';

/// API 全链路日志拦截器
///
/// [tag] 用于区分不同客户端的日志来源（如 `DIO`、`AI-API`），由 [AppLogger]
/// 统一加在每条日志前并写入环形缓冲区（开发者选项的日志页可查看）。
/// [logPrint] 日志输出函数，默认走 [AppLogger.log]；测试中可注入收集器。
class ApiLogInterceptor extends Interceptor {
  /// 日志标签
  final String tag;

  /// 日志输出函数（接收已格式化的消息体，不含 tag 前缀）
  final void Function(String message) logPrint;

  /// 记录请求起始时间的 extra key（用于计算耗时）
  static const _startTimeKey = '_apiLogStartMs';

  ApiLogInterceptor({
    required this.tag,
    void Function(String message)? logPrint,
  }) : logPrint = logPrint ?? ((message) => AppLogger.log(tag, message));

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startTimeKey] = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer()
      ..writeln('→ ${options.method} ${_sanitizeUri(options.uri)}');
    if (options.data != null) {
      buffer.writeln('  请求体: ${_stringifyBody(options.data)}');
    }
    logPrint(buffer.toString().trimRight());
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final request = response.requestOptions;
    final buffer = StringBuffer()
      ..writeln(
        '← ${request.method} ${_sanitizeUri(request.uri)} '
        '${response.statusCode}${_elapsedSuffix(request)}'
        '${_httpVersionSuffix(response.extra)}',
      );
    // 流式响应体是未消费的 ResponseBody，序列化它会破坏流；只记状态行。
    if (request.responseType == ResponseType.stream) {
      buffer.writeln('  响应体: (流式，略)');
    } else {
      buffer.writeln('  响应体: ${_stringifyBody(response.data)}');
    }
    logPrint(buffer.toString().trimRight());
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 取消请求不算错误，无需打印
    if (CancelToken.isCancel(err)) {
      handler.next(err);
      return;
    }

    final request = err.requestOptions;
    final response = err.response;
    final buffer = StringBuffer()
      ..writeln('❌ 请求失败${_elapsedSuffix(request)}')
      ..writeln('  ${request.method} ${_sanitizeUri(request.uri)}')
      ..writeln('  错误类型: ${err.type}')
      ..writeln('  错误消息: ${err.message ?? err.error}');

    if (response != null) {
      buffer.writeln(
        '  状态码: ${response.statusCode} ${response.statusMessage ?? ''}',
      );
      if (request.responseType == ResponseType.stream) {
        buffer.writeln('  响应体: (流式，略)');
      } else {
        buffer.writeln('  响应体: ${_stringifyBody(response.data)}');
      }
    } else {
      // 无响应：连接超时、DNS 失败、断网等
      buffer.writeln('  无响应（连接/超时/网络层错误）');
      if (err.error != null) {
        buffer.writeln('  底层异常: ${err.error}');
      }
    }

    logPrint(buffer.toString().trimRight());
    handler.next(err);
  }

  /// 根据 [onRequest] 记录的起始时间计算耗时后缀，如 ` (123ms)`
  String _elapsedSuffix(RequestOptions options) {
    final start = options.extra[_startTimeKey];
    if (start is! int) return '';
    final elapsed = DateTime.now().millisecondsSinceEpoch - start;
    return ' (${elapsed}ms)';
  }

  /// 记录底层 adapter 回填的实际 HTTP 协议版本。
  ///
  /// Dio 默认 IO adapter 与 HTTP/2 adapter 都会尽量写入该字段；没有取到时不打印，
  /// 避免 mock 或特殊平台下产生误导。
  String _httpVersionSuffix(Map<String, dynamic> extra) {
    final version = extra[HttpClientAdapter.extraKeyHttpVersion];
    return version is String && version.isNotEmpty ? ' HTTP/$version' : '';
  }

  /// 将请求/响应体安全地转为字符串，截断过长内容避免日志爆炸
  String _stringifyBody(Object? data) {
    if (data == null) return '(空)';
    String text;
    try {
      text = data is String ? data : jsonEncode(_sanitize(data));
    } catch (_) {
      text = data.toString();
    }
    const maxLength = 2000;
    if (text.length > maxLength) {
      return '${text.substring(0, maxLength)}…（已截断，共 ${text.length} 字符）';
    }
    return text;
  }

  /// 遮蔽 URI query 中的敏感字段，避免完整授权 URL、token 或 dlink 进入日志。
  String _sanitizeUri(Uri uri) {
    if (!uri.hasQuery) return uri.toString();
    final redactedQuery = uri.queryParametersAll.entries
        .map((entry) {
          final key = entry.key;
          if (_isSensitiveKey(key)) {
            return '$key=***';
          }
          return entry.value.map((value) => '$key=$value').join('&');
        })
        .where((part) => part.isNotEmpty)
        .join('&');
    return uri.replace(query: redactedQuery).toString();
  }

  /// 递归遮蔽凭据、用户标识和预签名上传地址，日志只保留字段存在性。
  Object? _sanitize(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _isSensitiveKey(entry.key.toString())
              ? '***'
              : _sanitize(entry.value),
      };
    }
    if (value is Iterable) return value.map(_sanitize).toList();
    return value;
  }

  bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[_-]'), '');
    return normalized.contains('authorization') ||
        normalized.contains('accesstoken') ||
        normalized.contains('refreshtoken') ||
        normalized.contains('polltoken') ||
        normalized.contains('sessionid') ||
        normalized.contains('clientsecret') ||
        normalized == 'code' ||
        normalized == 'state' ||
        normalized == 'dlink' ||
        normalized == 'token' ||
        normalized.contains('userid') ||
        normalized.contains('appuserid') ||
        normalized.contains('uploadurl') ||
        normalized.contains('presignedurl');
  }
}
