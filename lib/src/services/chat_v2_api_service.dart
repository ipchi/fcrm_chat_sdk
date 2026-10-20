import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;

import '../config/chat_config.dart';
import 'chat_api_service.dart';

/// HTTP transport for the v2 visitor API advertised by the mobile config.
///
/// Access-token renewal and persistence of the rotating resume credential are
/// managed by the caller. Every upload uses the same injected client as JSON
/// requests and can be aborted without closing that client's other requests.
class ChatV2ApiService {
  final ChatConfig config;
  final String baseUrl;
  final String appKey;
  final http.Client _client;
  final bool _ownsClient;

  ChatV2ApiService({
    required this.config,
    required String baseUrl,
    required this.appKey,
    http.Client? client,
  })  : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _ownsClient = client == null,
        _client = client ?? http.Client();

  Future<Map<String, dynamic>> getConfig() => _json(
        'GET',
        '/config',
        query: {'app_key': appKey},
      );

  Future<Map<String, dynamic>> startSession({
    required Map<String, dynamic> userData,
    String? endpoint,
  }) =>
      _json('POST', '/sessions', body: {
        'app_key': appKey,
        'user_data': userData,
        if (endpoint != null) 'endpoint': endpoint,
      });

  Future<Map<String, dynamic>> resumeSession({
    required String resumeToken,
  }) =>
      _json('POST', '/sessions/resume', body: {
        'app_key': appKey,
        'resume_token': resumeToken,
      });

  Future<Map<String, dynamic>> refreshSession({
    required String accessToken,
  }) =>
      _json('POST', '/sessions/refresh', accessToken: accessToken, body: {});

  Future<Map<String, dynamic>> sendMessage({
    required String accessToken,
    required String content,
    required String clientMessageId,
    String? endpoint,
  }) =>
      _json('POST', '/messages', accessToken: accessToken, body: {
        'client_message_id': clientMessageId,
        'content': content,
        'endpoint': endpoint,
      });

  /// Returns the newest page in chronological order; [before] is a sequence,
  /// never a page number or an opaque public message ID.
  Future<Map<String, dynamic>> getMessages({
    required String accessToken,
    int? before,
    int limit = 30,
  }) {
    if (limit < 1 || limit > 50) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 50');
    }
    if (before != null && before < 1) {
      throw ArgumentError.value(before, 'before', 'Must be positive');
    }
    return _json('GET', '/messages', accessToken: accessToken, query: {
      'limit': '$limit',
      if (before != null) 'before': '$before',
    });
  }

  Future<Map<String, dynamic>> getEvents({
    required String accessToken,
    int after = 0,
  }) {
    if (after < 0) {
      throw ArgumentError.value(after, 'after', 'Must not be negative');
    }
    return _json('GET', '/events',
        accessToken: accessToken, query: {'after': '$after'});
  }

  Future<int> markRead({
    required String accessToken,
    required int upToSeq,
  }) async {
    if (upToSeq < 1) {
      throw ArgumentError.value(upToSeq, 'upToSeq', 'Must be positive');
    }
    final result = await _json('PUT', '/read',
        accessToken: accessToken, body: {'up_to_seq': upToSeq});
    return (result['updated'] as num?)?.toInt() ?? 0;
  }

  /// Uploads and sends one image or voice message. Retain [clientMessageId]
  /// when retrying so a completed upload is not sent twice.
  ///
  /// The server intentionally calls the file field `image` for both kinds.
  /// [onSendProgress] counts file bytes, excluding multipart headers.
  Future<Map<String, dynamic>> uploadAttachment({
    required String accessToken,
    required File file,
    required String kind,
    required String clientMessageId,
    int? durationMs,
    String? endpoint,
    SendProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      throw UploadCancelledException();
    }
    if (kind != 'image' && kind != 'audio') {
      throw ArgumentError.value(kind, 'kind', 'Must be image or audio');
    }
    if (durationMs != null && (durationMs < 0 || durationMs > 600000)) {
      throw ArgumentError.value(
          durationMs, 'durationMs', 'Must be between 0 and 600000');
    }

    final size = await file.length();
    final maximum = (kind == 'audio' ? 10 : 5) * 1024 * 1024;
    if (size > maximum) {
      throw ChatApiException('File is too large', 413);
    }
    final handle = await file.open();
    late final List<int> header;
    try {
      header = await handle.read(32);
    } finally {
      await handle.close();
    }
    final mime = _mimeType(file.path, kind, header);

    return _send((abortTrigger) {
      var sent = 0;
      final request = http.AbortableMultipartRequest(
        'POST',
        _uri('/attachments'),
        abortTrigger: abortTrigger,
      )
        ..headers.addAll(_headers(accessToken))
        ..fields.addAll({
          'client_message_id': clientMessageId,
          'kind': kind,
          if (durationMs != null) 'duration_ms': '$durationMs',
          if (endpoint != null) 'endpoint': endpoint,
        });
      request.files.add(http.MultipartFile(
        'image',
        file.openRead().map((chunk) {
          if (cancelToken?.isCancelled == true) {
            throw UploadCancelledException();
          }
          sent += chunk.length;
          onSendProgress?.call(sent, size);
          return chunk;
        }),
        size,
        filename: path.basename(file.path),
        contentType: MediaType.parse(mime),
      ));
      onSendProgress?.call(0, size);
      return request;
    }, cancelToken: cancelToken);
  }

  String _mimeType(String filename, String kind, List<int> header) {
    final detected = lookupMimeType(filename, headerBytes: header);
    if (kind == 'audio') {
      // Recorders use several names for the same supported container.
      switch (path.extension(filename).toLowerCase()) {
        case '.m4a':
        case '.mp4':
          return 'audio/mp4';
        case '.webm':
          return 'audio/webm';
        case '.ogg':
        case '.oga':
        case '.opus':
          return 'audio/ogg';
        case '.wav':
          return 'audio/wav';
        case '.mp3':
          return 'audio/mpeg';
        case '.aac':
          return 'audio/aac';
      }
      if (detected == 'audio/x-wav') return 'audio/wav';
      if (detected == 'audio/x-m4a') return 'audio/mp4';
    }
    return detected ?? 'application/octet-stream';
  }

  Uri _uri(String route, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl/v1/widget$route').replace(queryParameters: query);

  Map<String, String> _headers(String? accessToken) => {
        'Accept': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  Future<Map<String, dynamic>> _json(
    String method,
    String route, {
    String? accessToken,
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) =>
      _send((abortTrigger) {
        final request = http.AbortableRequest(method, _uri(route, query),
            abortTrigger: abortTrigger)
          ..headers.addAll(_headers(accessToken));
        if (body != null) {
          request.headers['Content-Type'] = 'application/json';
          request.body = jsonEncode(body);
        }
        return request;
      });

  Future<Map<String, dynamic>> _send(
    http.BaseRequest Function(Future<void> abortTrigger) build, {
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      throw UploadCancelledException();
    }
    final abort = Completer<void>();
    var timedOut = false;
    void abortRequest() {
      if (!abort.isCompleted) abort.complete();
    }

    final timeout = Duration(milliseconds: config.connectionTimeout);
    final timer = Timer(timeout, () {
      timedOut = true;
      abortRequest();
    });
    final cancellation =
        cancelToken?.whenCancelled.asStream().listen((_) => abortRequest());
    try {
      final request = build(abort.future);
      final response = await Future.any<http.Response>([
        _client.send(request).then(http.Response.fromStream),
        abort.future.then((_) {
          if (timedOut) {
            throw TimeoutException('Chat request timed out', timeout);
          }
          throw UploadCancelledException();
        }),
      ]);
      if (cancelToken?.isCancelled == true) {
        throw UploadCancelledException();
      }
      return _decode(response);
    } on http.RequestAbortedException {
      if (timedOut) {
        throw TimeoutException('Chat request timed out', timeout);
      }
      throw UploadCancelledException();
    } finally {
      timer.cancel();
      await cancellation?.cancel();
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } on FormatException {
      // A proxy error page must still report the original HTTP status.
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = data?['error'] ?? data?['message'];
      throw ChatApiException(
        error?.toString() ??
            'Request failed with status ${response.statusCode}',
        response.statusCode,
      );
    }
    if (data == null) {
      throw ChatApiException(
          'Invalid response from chat service', response.statusCode);
    }
    return data;
  }

  /// An injected client remains owned by the caller and may be shared.
  void dispose() {
    if (_ownsClient) _client.close();
  }
}
