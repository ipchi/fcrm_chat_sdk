import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fcrm_chat_sdk/src/config/chat_config.dart';
import 'package:fcrm_chat_sdk/src/services/chat_api_service.dart';
import 'package:fcrm_chat_sdk/src/services/chat_v2_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ChatConfig _config({int timeout = 1000}) => ChatConfig(
      baseUrl: 'https://legacy.example',
      companyToken: 'tenant',
      appKey: 'legacy-app',
      appSecret: 'legacy-secret',
      connectionTimeout: timeout,
    );

ChatV2ApiService _service(http.Client client, {int timeout = 1000}) =>
    ChatV2ApiService(
      config: _config(timeout: timeout),
      baseUrl: 'https://chat.example/',
      appKey: 'public-app',
      client: client,
    );

http.StreamedResponse _response(Map<String, dynamic> data,
        [int status = 200]) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(data))), status,
        headers: {'content-type': 'application/json'});

class _Client extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) onSend;
  bool closed = false;

  _Client(this.onSend);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      onSend(request);

  @override
  void close() => closed = true;
}

void main() {
  test('uses the advertised v2 routes, visitor tokens and sequence cursors',
      () async {
    final requests = <http.Request>[];
    final api = _service(MockClient((request) async {
      requests.add(request);
      return http.Response(
          '{"updated":3}', request.url.path.endsWith('/sessions') ? 201 : 200);
    }));
    addTearDown(api.dispose);

    await api.getConfig();
    await api.startSession(userData: {'name': 'Ali'}, endpoint: 'support');
    await api.resumeSession(resumeToken: 'resume-secret');
    await api.refreshSession(accessToken: 'visitor-token');
    await api.sendMessage(
        accessToken: 'visitor-token',
        content: 'Assalomu alaykum',
        clientMessageId: 'client-msg-001',
        endpoint: 'support');
    await api.getMessages(accessToken: 'visitor-token', before: 31, limit: 20);
    await api.getEvents(accessToken: 'visitor-token', after: 47);
    expect(await api.markRead(accessToken: 'visitor-token', upToSeq: 32), 3);

    expect(requests.map((r) => '${r.method} ${r.url.path}'), [
      'GET /v1/widget/config',
      'POST /v1/widget/sessions',
      'POST /v1/widget/sessions/resume',
      'POST /v1/widget/sessions/refresh',
      'POST /v1/widget/messages',
      'GET /v1/widget/messages',
      'GET /v1/widget/events',
      'PUT /v1/widget/read',
    ]);
    expect(requests.every((r) => r.url.host == 'chat.example'), isTrue);
    expect(requests.first.url.queryParameters, {'app_key': 'public-app'});
    expect(jsonDecode(requests[1].body), {
      'app_key': 'public-app',
      'user_data': {'name': 'Ali'},
      'endpoint': 'support',
    });
    expect(jsonDecode(requests[2].body), {
      'app_key': 'public-app',
      'resume_token': 'resume-secret',
    });
    expect(jsonDecode(requests[4].body), {
      'client_message_id': 'client-msg-001',
      'content': 'Assalomu alaykum',
      'endpoint': 'support',
    });
    expect(requests[5].url.queryParameters, {'before': '31', 'limit': '20'});
    expect(requests[6].url.queryParameters, {'after': '47'});
    expect(jsonDecode(requests[7].body), {'up_to_seq': 32});
    for (final request in requests.take(3)) {
      expect(request.headers.containsKey('authorization'), isFalse);
    }
    for (final request in requests.skip(3)) {
      expect(request.headers['authorization'], 'Bearer visitor-token');
    }
    for (final request in requests) {
      expect(request.headers.containsKey('x-chat-signature'), isFalse);
      expect(request.body, isNot(contains('legacy-secret')));
    }
  });

  test('streams voice files with the server field name, MIME and progress',
      () async {
    final directory = await Directory.systemTemp.createTemp('fcrm-v2-audio-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/voice.m4a');
    final bytes = List.filled(256 * 1024, 65);
    await file.writeAsBytes(bytes);
    final progress = <List<int>>[];
    final api = _service(_Client((request) async {
      expect(request, isA<http.AbortableMultipartRequest>());
      expect(request.url.path, '/v1/widget/attachments');
      expect(request.headers['Authorization'], 'Bearer visitor-token');
      final payload = await request.finalize().toBytes();
      expect(payload.length, request.contentLength);
      final body = utf8.decode(payload);
      expect(request.headers['content-type'],
          startsWith('multipart/form-data; boundary='));
      expect(body, contains('name="image"; filename="voice.m4a"'));
      expect(body, contains('content-type: audio/mp4'));
      expect(body, contains('name="kind"\r\n\r\naudio\r\n'));
      expect(body, contains('name="duration_ms"\r\n\r\n4200\r\n'));
      expect(body, contains('name="client_message_id"\r\n\r\nvoice-id-001'));
      expect(body, contains('name="endpoint"\r\n\r\nsupport'));
      return _response({
        'message': {
          'id': 'public-id',
          'kind': 'audio',
          'audioUrl': 'https://files.example/voice.m4a',
          'durationMs': 4200,
        },
        'duplicate': false,
      }, 201);
    }));
    addTearDown(api.dispose);

    final result = await api.uploadAttachment(
      accessToken: 'visitor-token',
      file: file,
      kind: 'audio',
      clientMessageId: 'voice-id-001',
      durationMs: 4200,
      endpoint: 'support',
      onSendProgress: (sent, total) => progress.add([sent, total]),
    );
    expect(result['message']['kind'], 'audio');
    expect(progress.first, [0, bytes.length]);
    expect(progress.last, [bytes.length, bytes.length]);
    expect(progress.length, greaterThan(2));
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i][0], greaterThanOrEqualTo(progress[i - 1][0]));
    }
  });

  test('cancellation aborts the upload without closing its injected client',
      () async {
    final directory = await Directory.systemTemp.createTemp('fcrm-v2-cancel-');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/voice.webm').writeAsString('audio');
    final started = Completer<void>();
    final aborted = Completer<void>();
    final client = _Client((request) async {
      if (request.url.path.endsWith('/config')) {
        return _response({});
      }
      final abortable = request as http.Abortable;
      started.complete();
      await abortable.abortTrigger;
      aborted.complete();
      throw http.RequestAbortedException(request.url);
    });
    final api = _service(client);
    addTearDown(api.dispose);
    final cancel = CancelToken();
    final upload = api.uploadAttachment(
        accessToken: 'token',
        file: file,
        kind: 'audio',
        clientMessageId: 'voice-id-001',
        cancelToken: cancel);
    final expectation =
        expectLater(upload, throwsA(isA<UploadCancelledException>()));
    await started.future;
    cancel.cancel();
    await expectation;
    await aborted.future;
    expect(client.closed, isFalse);
    expect(await api.getConfig(), isEmpty);
  });

  test('timeout aborts a stalled request even when a cancel token is provided',
      () async {
    final directory = await Directory.systemTemp.createTemp('fcrm-v2-timeout-');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/voice.webm').writeAsString('audio');
    final aborted = Completer<void>();
    final api = _service(_Client((request) async {
      await (request as http.Abortable).abortTrigger;
      aborted.complete();
      throw http.RequestAbortedException(request.url);
    }), timeout: 30);
    addTearDown(api.dispose);

    await expectLater(
        api.uploadAttachment(
            accessToken: 'token',
            file: file,
            kind: 'audio',
            clientMessageId: 'voice-id-001',
            cancelToken: CancelToken()),
        throwsA(isA<TimeoutException>()));
    await aborted.future;
  });

  test('keeps auth and proxy HTTP errors actionable, accepts duplicate sends',
      () async {
    var attempt = 0;
    final api = _service(MockClient((request) async {
      attempt++;
      if (attempt == 1) return http.Response('{"error":"Unauthorized"}', 401);
      if (attempt == 2) {
        return http.Response('<html>upstream failed</html>', 502);
      }
      return http.Response('{"duplicate":true,"message":{"seq":1}}', 200);
    }));
    addTearDown(api.dispose);

    Future<Map<String, dynamic>> send() => api.sendMessage(
        accessToken: 'token',
        content: 'Salom',
        clientMessageId: 'client-msg-001');
    await expectLater(
        send(),
        throwsA(isA<ChatApiException>()
            .having((e) => e.statusCode, 'status', 401)));
    await expectLater(
        send(),
        throwsA(isA<ChatApiException>()
            .having((e) => e.statusCode, 'status', 502)));
    expect((await send())['duplicate'], isTrue);
  });
}
