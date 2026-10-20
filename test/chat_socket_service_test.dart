import 'package:fcrm_chat_sdk/src/services/chat_socket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:socket_io_client/src/manager.dart';

class FakeSocket extends io.Socket {
  final List<MapEntry<String, dynamic>> sent = [];
  int connects = 0;
  int disconnects = 0;
  int disposals = 0;

  FakeSocket(String namespace)
      : super(
          Manager(
              uri: 'https://socket.example', options: {'autoConnect': false}),
          namespace,
          {'autoConnect': false},
        );

  @override
  io.Socket connect() {
    connects++;
    return this;
  }

  @override
  void emit(String event, [dynamic data]) => sent.add(MapEntry(event, data));

  void receive(String event, [dynamic data]) {
    // onevent dispatches to registered listeners without sending over a wire.
    connected = true;
    onevent({
      'data': [event, data]
    });
    if (event == 'disconnect') connected = false;
  }

  @override
  io.Socket disconnect() {
    disconnects++;
    if (connected) receive('disconnect', 'io client disconnect');
    connected = false;
    return this;
  }

  @override
  void dispose() {
    disposals++;
    disconnect();
    clearListeners();
  }
}

Map<String, dynamic> v2Message({int cursor = 7}) => {
      'id': 'opaque-message',
      'seq': 12,
      'clientMessageId': null,
      'sender': 'agent',
      'senderName': 'Operator',
      'kind': 'audio',
      'imageUrl': null,
      'audioUrl': 'https://files.example/voice.ogg',
      'durationMs': 1200,
      'content': '',
      'edited': false,
      'read': false,
      'ratable': false,
      'rating': null,
      'allowLinks': true,
      'createdAt': '2026-10-20T09:00:00Z',
      'eventId': 'event-$cursor',
      'cursor': cursor,
    };

Future<void> flushStreams() => Future<void>.delayed(Duration.zero);

void main() {
  late ChatSocketService service;
  late List<FakeSocket> sockets;
  late List<String> urls;
  late List<Map<String, dynamic>> options;

  setUp(() {
    sockets = [];
    urls = [];
    options = [];
    service = ChatSocketService(socketFactory: (url, opts) {
      urls.add(url);
      options.add(opts);
      final socket = FakeSocket(Uri.parse(url).path);
      sockets.add(socket);
      return socket;
    });
  });

  tearDown(() => service.dispose());

  test(
      'v2 uses its namespace/path and never sends legacy room or typing events',
      () {
    service.connect(socketUrl: 'https://chat.example', token: 'visitor-token');
    final socket = sockets.single;
    expect(urls.single, 'https://chat.example/v2');
    expect(options.single['path'], '/v2/socket.io');
    expect(options.single['autoConnect'], false);
    expect(options.single['forceNew'], true);
    expect(options.single['reconnectionAttempts'], double.infinity);
    Map? auth;
    (options.single['auth'] as Function)((Map value) => auth = value);
    expect(auth, {'token': 'visitor-token'});

    socket.receive('connect');
    service.joinChatRoom('other-browser');
    service.subscribe('other-room');
    service.sendTyping('other-browser', true);
    expect(socket.sent, isEmpty);
  });

  test('v2 created and repeated updated events retain durable recovery cursors',
      () async {
    final events = [];
    final messages = [];
    service.onEvent.listen(events.add);
    service.onMessage.listen(messages.add);
    service.connect(socketUrl: 'https://chat.example', token: 'visitor-token');
    final socket = sockets.single;
    socket.receive('message.created', v2Message());
    socket.receive('message.updated', v2Message(cursor: 8));
    socket.receive('message.updated', v2Message(cursor: 9));
    await flushStreams();

    expect(events.length, 3);
    expect(events.map((event) => event.cursor), [7, 8, 9]);
    expect(events.map((event) => event.event),
        ['message.created', 'message.updated', 'message.updated']);
    expect(messages.length, 3);
    expect(messages.last.message.content, '');
    expect(messages.last.message.publicId, 'opaque-message');
  });

  test(
      'token rotation reconnects using a fresh Manager and current credentials',
      () async {
    final reconnects = [];
    service.onReconnect.listen(reconnects.add);
    service.connect(socketUrl: 'https://chat.example', token: 'old-token');
    final socket = sockets.single;
    socket.receive('connect');
    service.updateToken('new-token');
    expect(socket.disconnects, 1);
    expect(socket.disposals, 1);
    expect(socket.connects, 1);
    expect(socket.io.hasListeners('reconnect_attempt'), false);
    final replacement = sockets.last;
    expect(replacement.connects, 1);
    Map? auth;
    (options.last['auth'] as Function)((Map value) => auth = value);
    expect(auth, {'token': 'new-token'});
    replacement.receive('connect');
    // The asynchronously closing old engine cannot affect this session.
    socket.receive('disconnect', 'forced close');
    await flushStreams();
    expect(reconnects.length, 1);
    expect(sockets.length, 2);
  });

  test('v2 server expiry and rejected auth request session renewal', () async {
    final errors = [];
    service.onAuthError.listen(errors.add);
    service.connect(socketUrl: 'https://chat.example', token: 'visitor-token');
    final socket = sockets.single;
    socket.receive('disconnect', 'io server disconnect');
    socket.receive('error', {'message': 'unauthorized'});
    await flushStreams();
    expect(errors.length, 2);
    // Expired-token reconnect is deferred until the caller renews the token.
    expect(socket.connects, 1);
  });

  test('legacy rooms and desired subscriptions replay with current credentials',
      () async {
    service.subscribe('private-other');
    service.connect(
      socketUrl: 'https://socket.example',
      apiKey: 'app-key',
      browserKey: 'old-browser',
    );
    final socket = sockets.single;
    socket.receive('connect');
    expect(socket.sent.map((event) => event.value),
        ['private-chat_old-browser', 'private-other']);

    socket.receive('disconnect', 'transport close');
    service.updateBrowserKey('new-browser');
    service.unsubscribe('private-other');
    service.subscribe('private-new');
    socket.sent.clear();
    socket.receive('connect');
    expect(socket.sent.map((event) => event.value),
        ['private-chat_new-browser', 'private-new']);
    Map? auth;
    (options.single['auth'] as Function)((Map value) => auth = value);
    expect(auth, {'key': 'app-key', 'browser_key': 'new-browser'});
  });

  test(
      'legacy edits in both event formats are emitted and malformed events ignored',
      () async {
    final messages = [];
    service.onMessage.listen(messages.add);
    service.connect(socketUrl: 'https://socket.example', apiKey: 'app-key');
    final socket = sockets.single;
    final message = {
      'id': 4,
      'chat_id': 2,
      'content': 'Updated',
      'type': 'admin',
      'created_at': '2026-10-20T09:00:00Z',
    };
    socket.receive('App:Events:Chat:MessageEditedEvent', {'message': message});
    socket.receive(
        'App\\Events\\Telegram\\MessageEditedEvent', {'message': message});
    socket.receive('App:Events:Chat:MessageEvent', null);
    socket.receive('App:Events:Chat:MessageEvent', {'message': 'broken'});
    socket.receive('App:Events:Chat:MessageEvent', 'not json');
    await flushStreams();
    expect(messages.length, 2);
    expect(messages.first.event, 'App:Events:Chat:MessageEditedEvent');
    expect(messages.last.event, 'App\\Events\\Telegram\\MessageEditedEvent');
  });

  test('replacement and disposal remove stale listeners and are idempotent',
      () async {
    service.connect(socketUrl: 'https://one.example', apiKey: 'one');
    final first = sockets.single;
    expect(first.io.hasListeners('reconnect_attempt'), true);
    service.connect(socketUrl: 'https://two.example', apiKey: 'two');
    expect(first.disposals, 1);
    expect(first.io.hasListeners('reconnect_attempt'), false);
    expect(first.hasListeners('connect'), false);
    final current = sockets.last;
    service.dispose();
    service.dispose();
    expect(current.disposals, 1);
    expect(current.io.hasListeners('reconnect_attempt'), false);
    expect(() => service.connect(socketUrl: 'https://chat.example'),
        throwsStateError);
  });
}
