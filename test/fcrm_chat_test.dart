import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fcrm_chat_sdk/fcrm_chat_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestSocket extends ChatSocketService {
  final events = StreamController<ChatEvent>.broadcast();
  final connections = StreamController<bool>.broadcast();
  final authErrors = StreamController<String>.broadcast();
  final tokens = <String?>[];
  bool connected = false;

  @override
  Stream<ChatEvent> get onEvent => events.stream;
  @override
  Stream<bool> get onConnectionChange => connections.stream;
  @override
  Stream<String> get onAuthError => authErrors.stream;
  @override
  bool get isConnected => connected;

  @override
  void connect({
    required String socketUrl,
    String apiKey = '',
    String? browserKey,
    String? token,
    String? namespace,
    String? path,
    Duration timeout = const Duration(seconds: 20),
  }) {
    tokens.add(token);
  }

  @override
  void disconnect() => connected = false;

  @override
  void dispose() {
    events.close();
    connections.close();
    authErrors.close();
    super.dispose();
  }
}

ChatConfig config({bool enableV2 = true}) => ChatConfig(
      baseUrl: 'https://api.example',
      companyToken: 'company',
      appKey: 'public-app-key',
      appSecret: 'app-secret',
      enableV2: enableV2,
    );

Map<String, dynamic> remote({bool v2 = true}) => {
      'is_active': true,
      'required_fields': ['name'],
      'settings': [],
      'socket_url': 'https://legacy.example',
      'socket_api_key': 'legacy-key',
      if (v2)
        'v2': {
          'base_url': 'https://chat.example',
          'app_key': 'public-app-key',
          'socket_namespace': '/v2',
          'socket_path': '/v2/socket.io',
        },
    };

Map<String, dynamic> session(String token, {String? resume}) => {
      'access_token': token,
      'expires_in': 600,
      if (resume != null) 'resume_token': resume,
      'visitor': {'id': 42},
    };

Map<String, dynamic> message(String id, int seq, {String content = 'Hello'}) =>
    {
      'id': id,
      'seq': seq,
      'sender': 'agent',
      'kind': 'text',
      'content': content,
      'createdAt': '2026-10-20T12:00:00Z',
    };

http.Response reply(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status,
        headers: {'content-type': 'application/json'});

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('negotiates v2 and resumes a rotated session across SDK instances',
      () async {
    var starts = 0;
    var resumes = 0;
    final bodies = <Map<String, dynamic>>[];
    Future<http.Response> handle(http.Request request) async {
      if (request.url.path.endsWith('/config')) {
        expect(request.headers['X-Chat-Sdk-Protocol'], '2');
        return reply(remote());
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      bodies.add(body);
      if (request.url.path.endsWith('/resume')) {
        resumes++;
        expect(body['resume_token'], 'resume-1');
        return reply(session('token-2', resume: 'resume-2'));
      }
      starts++;
      return reply(session('token-1', resume: 'resume-1'), 201);
    }

    final first = FcrmChat(
        config: config(),
        httpClient: MockClient(handle),
        socketService: TestSocket());
    await first.initialize();
    expect(first.isV2, true);
    expect(await first.isRegistered(), false);
    final userData = {'name': 'Client'};
    await first.register(userData: userData);
    expect(userData, {'name': 'Client'});
    expect(first.browserKey, isNull);
    expect(first.visitorId, 42);
    first.dispose();

    final socket = TestSocket();
    final second = FcrmChat(
        config: config(),
        httpClient: MockClient(handle),
        socketService: socket);
    addTearDown(second.dispose);
    await Future.wait([second.initialize(), second.initialize()]);
    expect(starts, 1);
    expect(resumes, 1);
    expect(await second.isRegistered(), true);
    expect(socket.tokens, ['token-2']);
    expect((await second.getUserData())?['name'], 'Client');
    expect(bodies.every((body) => !body.containsKey('browser_key')), true);
  });

  test('legacy negotiation and explicit opt-out preserve signed requests',
      () async {
    for (final enabled in [true, false]) {
      final chat = FcrmChat(
        config: config(enableV2: enabled),
        socketService: TestSocket(),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/config')) {
            expect(
                request.headers['X-Chat-Sdk-Protocol'], enabled ? '2' : isNull);
            return reply(remote(v2: !enabled));
          }
          expect(request.url.host, 'api.example');
          expect(request.headers['X-Chat-Signature'],
              config().generateSignature());
          if (request.url.path.endsWith('/register-browser')) {
            return reply(
                {'success': true, 'browser_key': 'browser', 'chat_id': 5});
          }
          return reply({'success': true, 'user_message_id': 9, 'chat_id': 5});
        }),
      );
      await chat.initialize();
      expect(chat.isV2, false);
      await chat.register(userData: {'name': 'Client'});
      expect((await chat.sendMessage('Hello')).userMessageId, 9);
      chat.dispose();
    }
  });

  test('401 refresh/resume retries with the same idempotency key', () async {
    final sentIds = <String>[];
    final socket = TestSocket();
    var refreshes = 0;
    final chat = FcrmChat(
      config: config(),
      socketService: socket,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/config')) return reply(remote());
        if (path.endsWith('/sessions')) {
          return reply(session('old', resume: 'resume-old'), 201);
        }
        if (path.endsWith('/refresh')) {
          refreshes++;
          return reply({'error': 'Unauthorized'}, 401);
        }
        if (path.endsWith('/resume')) {
          return reply(session('new', resume: 'resume-new'));
        }
        sentIds.add(
            (jsonDecode(request.body) as Map)['client_message_id'] as String);
        if (request.headers['Authorization'] == 'Bearer old') {
          return reply({'error': 'Unauthorized'}, 401);
        }
        expect(request.headers['Authorization'], 'Bearer new');
        return reply({
          'message': message('public-id', 10),
          'duplicate': true,
          'aiPending': false
        });
      }),
    );
    addTearDown(chat.dispose);
    await chat.initialize();
    await chat.register(userData: {'name': 'Client'});
    final sent =
        await chat.sendMessage('Hello', clientMessageId: 'retry-key-123');
    expect(sentIds, ['retry-key-123', 'retry-key-123']);
    expect(refreshes, 1);
    expect(sent.message?.publicId, 'public-id');
    expect(sent.duplicate, true);
    expect(socket.tokens, ['old', 'new']);
  });

  test('concurrent unauthorized requests share one token refresh', () async {
    var refreshes = 0;
    final gate = Completer<void>();
    final refreshStarted = Completer<void>();
    final chat = FcrmChat(
      config: config(),
      socketService: TestSocket(),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/config')) return reply(remote());
        if (path.endsWith('/sessions')) {
          return reply(session('old', resume: 'resume'), 201);
        }
        if (path.endsWith('/refresh')) {
          refreshes++;
          if (!refreshStarted.isCompleted) refreshStarted.complete();
          await gate.future;
          return reply(session('new'));
        }
        if (request.headers['Authorization'] == 'Bearer old') {
          return reply({'error': 'Unauthorized'}, 401);
        }
        return reply({'message': message('sent', 12)});
      }),
    );
    addTearDown(chat.dispose);
    await chat.initialize();
    await chat.register(userData: {'name': 'Client'});
    final sends =
        Future.wait([chat.sendMessage('One'), chat.sendMessage('Two')]);
    await refreshStarted.future;
    await flush();
    expect(refreshes, 1);
    gate.complete();
    await sends;
  });

  test(
      'recovery drains pages, deduplicates live events and skips stale updates',
      () async {
    final socket = TestSocket();
    final afters = <String?>[];
    final received = <ChatMessage>[];
    final chat = FcrmChat(
      config: config(),
      socketService: socket,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/config')) return reply(remote());
        if (request.url.path.endsWith('/sessions')) {
          return reply(session('token', resume: 'resume'), 201);
        }
        final after = request.url.queryParameters['after'];
        afters.add(after);
        if (after == '0') {
          return reply({
            'events': [
              {
                'cursor': 7,
                'eventId': 'e7',
                'type': 'message.created',
                'data': message('same', 10, content: 'Old')
              },
              {
                'cursor': 8,
                'eventId': 'e8',
                'type': 'message.created',
                'data': message('other', 11)
              },
              {
                'cursor': 9,
                'eventId': 'e9',
                'type': 'message.updated',
                'data': message('same', 10, content: 'New')
              },
            ],
            'nextCursor': 9
          });
        }
        if (after == '9') {
          return reply({
            'events': [
              {
                'cursor': 12,
                'eventId': 'e12',
                'type': 'message.created',
                'data': message('last', 13)
              },
            ],
            'nextCursor': 12
          });
        }
        return reply({'events': [], 'nextCursor': 12});
      }),
    );
    addTearDown(chat.dispose);
    chat.onMessage.listen(received.add);
    await chat.initialize();
    await chat.register(userData: {'name': 'Client'});
    socket.events.add(ChatEvent.fromJson({
      'cursor': 9,
      'eventId': 'e9',
      'type': 'message.updated',
      'data': message('same', 10, content: 'New')
    }));
    await flush();
    await Future.wait([chat.syncEvents(), chat.syncEvents()]);
    await flush();
    expect(afters, ['0', '9', '12']);
    expect(received.map((m) => m.publicId), ['same', 'other', 'last']);
    expect(received.first.content, 'New');
    expect(chat.eventCursor, 12);
    socket.events.add(ChatEvent.fromJson({
      'cursor': 8,
      'eventId': 'e8',
      'type': 'message.created',
      'data': message('other', 11)
    }));
    await flush();
    expect(received.length, 3);
  });

  test('v2 cursor history backs page API without inventing exact totals',
      () async {
    final before = <String?>[];
    final chat = FcrmChat(
      config: config(),
      socketService: TestSocket(),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/config')) return reply(remote());
        if (request.url.path.endsWith('/sessions')) {
          return reply(session('token', resume: 'resume'), 201);
        }
        before.add(request.url.queryParameters['before']);
        return reply(before.last == null
            ? {
                'messages': [message('three', 3), message('four', 4)],
                'hasMore': true
              }
            : {
                'messages': [message('one', 1), message('two', 2)],
                'hasMore': false
              });
      }),
    );
    addTearDown(chat.dispose);
    await chat.initialize();
    await chat.register(userData: {'name': 'Client'});
    final page = await chat.getMessages(page: 2, perPage: 2);
    expect(before, [null, '3']);
    expect(page.messages.map((m) => m.seq), [1, 2]);
    expect(page.hasExactTotal, false);
    expect(page.hasMore, false);
  });

  test('reset prevents a pending refresh from restoring old credentials',
      () async {
    final gate = Completer<http.Response>();
    final started = Completer<void>();
    final socket = TestSocket();
    final chat = FcrmChat(
      config: config(),
      socketService: socket,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/config')) return reply(remote());
        if (request.url.path.endsWith('/sessions')) {
          return reply(session('old', resume: 'resume-old'), 201);
        }
        if (request.url.path.endsWith('/refresh')) {
          started.complete();
          return gate.future;
        }
        return reply({'error': 'Unauthorized'}, 401);
      }),
    );
    addTearDown(chat.dispose);
    await chat.initialize();
    await chat.register(userData: {'name': 'Client'});
    final sending = chat.sendMessage('Hello');
    final assertion = expectLater(sending, throwsA(isA<ChatException>()));
    await started.future;
    await chat.reset();
    gate.complete(reply(session('new', resume: 'resume-new')));
    await assertion;
    expect(await chat.isRegistered(), false);
    expect(socket.tokens, ['old']);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('v2 guards unsupported operations before issuing requests', () async {
    var calls = 0;
    final chat = FcrmChat(
      config: config(),
      socketService: TestSocket(),
      httpClient: MockClient((request) async {
        calls++;
        if (request.url.path.endsWith('/config')) return reply(remote());
        return reply(session('token', resume: 'resume'), 201);
      }),
    );
    addTearDown(chat.dispose);
    await chat.initialize();
    await chat.register(userData: {'name': 'Client'});
    await expectLater(
        chat.updateName('New name'), throwsA(isA<ChatException>()));
    await expectLater(chat.editMessage(messageId: 1, content: 'New'),
        throwsA(isA<ChatException>()));
    await expectLater(chat.rateMessage(publicMessageId: 'id', rating: 5),
        throwsA(isA<ChatException>()));
    await expectLater(
        chat.registerPushDevice(token: 'fcm', platform: 'android'),
        throwsA(isA<ChatException>()));
    expect(calls, 2);
  });

  test('dispose during initialization rejects without writing closed streams',
      () async {
    final gate = Completer<http.Response>();
    final chat = FcrmChat(
        config: config(),
        socketService: TestSocket(),
        httpClient: MockClient((_) => gate.future));
    final pending = chat.initialize();
    final assertion = expectLater(pending, throwsA(isA<ChatException>()));
    chat.dispose();
    gate.complete(reply(remote()));
    await assertion;
  });

  test('failed initialization can renegotiate from v2 to legacy', () async {
    final cfg = config();
    final storage = ChatStorageService(
      appKey: 'v2_${Uri.encodeComponent(cfg.apiUrl)}_${cfg.appKey}',
    );
    await storage.saveResumeToken('resume-before-outage');
    var configCalls = 0;
    final socket = TestSocket();
    final chat = FcrmChat(
      config: cfg,
      socketService: socket,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/config')) {
          return reply(remote(v2: ++configCalls == 1));
        }
        return reply({'error': 'Unavailable'}, 502);
      }),
    );
    addTearDown(chat.dispose);
    await expectLater(chat.initialize(), throwsA(isA<ChatApiException>()));
    await chat.initialize();
    expect(chat.isInitialized, true);
    expect(chat.isV2, false);
    expect(socket.tokens, [null]);
    expect(await storage.getResumeToken(), 'resume-before-outage');
  });

  test('invalid v2 resume is cleared without using a legacy browser credential',
      () async {
    final cfg = config();
    final storage = ChatStorageService(
      appKey: 'v2_${Uri.encodeComponent(cfg.apiUrl)}_${cfg.appKey}',
    );
    await storage.saveResumeToken('spent-resume');
    await ChatStorageService(appKey: cfg.appKey)
        .saveBrowserKey('legacy-browser');
    final socket = TestSocket();
    final chat = FcrmChat(
      config: cfg,
      socketService: socket,
      httpClient: MockClient((request) async =>
          request.url.path.endsWith('/config')
              ? reply(remote())
              : reply({'error': 'Not found'}, 404)),
    );
    addTearDown(chat.dispose);
    await chat.initialize();
    expect(chat.isV2, true);
    expect(await chat.isRegistered(), false);
    expect(await storage.getResumeToken(), isNull);
    expect(chat.browserKey, isNull);
    expect(socket.tokens, isEmpty);
  });

  test('queued events cannot emit an old message after reset', () async {
    final socket = TestSocket();
    final received = <ChatMessage>[];
    final chat = FcrmChat(
      config: config(),
      socketService: socket,
      httpClient: MockClient((request) async =>
          request.url.path.endsWith('/config')
              ? reply(remote())
              : reply(session('token', resume: 'resume'), 201)),
    );
    addTearDown(chat.dispose);
    chat.onMessage.listen(received.add);
    await chat.initialize();
    await chat.register(userData: {'name': 'Client'});
    socket.events.add(ChatEvent.fromJson({
      'cursor': 1,
      'type': 'message.created',
      'data': message('old', 1),
    }));
    await chat.reset();
    await flush();
    expect(received, isEmpty);
  });

  test('sendAudio routes recording, duration and retry key through v2 upload',
      () async {
    final directory = await Directory.systemTemp.createTemp('fcrm-audio-');
    addTearDown(() => directory.delete(recursive: true));
    final recording = await File('${directory.path}/voice.m4a')
        .writeAsBytes(List.filled(16, 0));
    final progress = <int>[];
    final chat = FcrmChat(
      config: config(),
      socketService: TestSocket(),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/config')) return reply(remote());
        if (request.url.path.endsWith('/sessions')) {
          return reply(session('token', resume: 'resume'), 201);
        }
        expect(request.url.path, '/v1/widget/attachments');
        expect(request.headers['Authorization'], 'Bearer token');
        expect(request.body, contains('name="kind"\r\n\r\naudio'));
        expect(request.body, contains('name="duration_ms"\r\n\r\n3200'));
        expect(request.body, contains('audio-retry-key'));
        expect(request.body, contains('content-type: audio/mp4'));
        return reply({
          'message': {
            ...message('audio-id', 5),
            'kind': 'audio',
            'content': '',
            'audioUrl': 'https://files.example/voice.m4a',
            'durationMs': 3200,
          },
          'duplicate': false
        }, 201);
      }),
    );
    addTearDown(chat.dispose);
    await chat.initialize();
    await chat.register(userData: {'name': 'Client'});
    final result = await chat.sendAudio(recording,
        durationMs: 3200,
        clientMessageId: 'audio-retry-key',
        onSendProgress: (sent, _) => progress.add(sent));
    final audio =
        ChatMessage.fromJson(Map<String, dynamic>.from(result['message']));
    expect(audio.isAudio, true);
    expect(audio.durationMs, 3200);
    expect(progress.first, 0);
    expect(progress.last, 16);
  });

  test('large live backlogs retain newest snapshots until replay catches up',
      () async {
    final socket = TestSocket();
    final received = <ChatMessage>[];
    final chat = FcrmChat(
      config: config(),
      socketService: socket,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/config')) return reply(remote());
        if (request.url.path.endsWith('/sessions')) {
          return reply(session('token', resume: 'resume'), 201);
        }
        if (request.url.queryParameters['after'] != '0') {
          return reply({'events': [], 'nextCursor': 3000});
        }
        return reply({
          'events': [
            {
              'cursor': 1,
              'eventId': 'old-first',
              'type': 'message.created',
              'data': message('first', 1, content: 'Old')
            },
            {
              'cursor': 3000,
              'eventId': 'latest-first',
              'type': 'message.updated',
              'data': message('first', 1, content: 'New')
            },
          ],
          'nextCursor': 3000
        });
      }),
    );
    addTearDown(chat.dispose);
    chat.onMessage.listen(received.add);
    await chat.initialize();
    await chat.register(userData: {'name': 'Client'});
    socket.events.add(ChatEvent.fromJson({
      'cursor': 3000,
      'eventId': 'latest-first',
      'type': 'message.updated',
      'data': message('first', 1, content: 'New'),
    }));
    for (var i = 1; i <= 2050; i++) {
      socket.events.add(ChatEvent.fromJson({
        'cursor': 3000 + i,
        'eventId': 'live-$i',
        'type': 'message.created',
        'data': message('other-$i', i + 1),
      }));
    }
    await flush();
    await chat.syncEvents();
    await flush();
    expect(received.length, 2051);
    expect(received.where((m) => m.publicId == 'first').single.content, 'New');
  });
}
