import 'dart:async';
import 'dart:convert';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/chat_event.dart';
import '../models/message.dart';

/// Creates an isolated Socket.IO connection. Primarily useful for testing.
typedef ChatSocketFactory = io.Socket Function(
  String url,
  Map<String, dynamic> options,
);

/// Socket.IO transport for legacy chat and authenticated v2 visitor sessions.
class ChatSocketService {
  io.Socket? _socket;
  String? _currentBrowserKey;
  String? _token;
  String _apiKey = '';
  String? _connectionUrl;
  Map<String, dynamic>? _connectionOptions;
  String? _path;
  bool _isV2 = false;
  bool _disposed = false;
  bool _hasConnected = false;
  final bool _enableLogging;
  final ChatSocketFactory _socketFactory;
  final Set<String> _subscriptions = {};

  final _connectionController = StreamController<bool>.broadcast();
  final _messageController = StreamController<SocketMessage>.broadcast();
  final _eventController = StreamController<ChatEvent>.broadcast();
  final _typingController = StreamController<bool>.broadcast();
  final _browserKeyController = StreamController<String>.broadcast();
  final _reconnectController = StreamController<void>.broadcast();
  final _authErrorController = StreamController<String>.broadcast();

  Stream<bool> get onConnectionChange => _connectionController.stream;
  Stream<SocketMessage> get onMessage => _messageController.stream;

  /// Durable v2 events, including their recovery cursor.
  Stream<ChatEvent> get onEvent => _eventController.stream;
  Stream<bool> get onTyping => _typingController.stream;
  Stream<String> get onBrowserKeyUpdate => _browserKeyController.stream;

  /// Every successful connection after the first, including token rotation.
  Stream<void> get onReconnect => _reconnectController.stream;

  /// Rejected or expired credentials; session renewal belongs to the caller.
  Stream<String> get onAuthError => _authErrorController.stream;
  bool get isConnected => _socket?.connected ?? false;
  String? get currentBrowserKey => _currentBrowserKey;
  bool get isV2 => _isV2;

  ChatSocketService({
    bool enableLogging = false,
    ChatSocketFactory? socketFactory,
  })  : _enableLogging = enableLogging,
        _socketFactory = socketFactory ?? io.io;

  void _log(String message) {
    if (_enableLogging) {
      // ignore: avoid_print
      print('[FCRM Socket] $message');
    }
  }

  /// Connect using an API key for legacy chat, or a visitor [token] for v2.
  /// V2 defaults to namespace `/v2` and transport path `/v2/socket.io`.
  void connect({
    required String socketUrl,
    String apiKey = '',
    String? browserKey,
    String? token,
    String? namespace,
    String? path,
    Duration timeout = const Duration(seconds: 20),
  }) {
    _ensureAlive();
    final v2 = token != null;
    if (v2 && token.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Must not be empty');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
    }
    final url = _withNamespace(socketUrl, namespace ?? (v2 ? '/v2' : null));
    final socketPath = path ?? (v2 ? '/v2/socket.io' : '/socket.io');

    if (_socket != null &&
        _connectionUrl == url &&
        _path == socketPath &&
        _isV2 == v2 &&
        _apiKey == apiKey) {
      if (!v2 && browserKey != null) updateBrowserKey(browserKey);
      if (v2 && _token != token) {
        updateToken(token);
      } else if (!_socket!.connected) {
        _socket!.connect();
      }
      return;
    }

    _releaseSocket();
    _isV2 = v2;
    _token = token;
    _apiKey = apiKey;
    _currentBrowserKey = browserKey;
    _connectionUrl = url;
    _path = socketPath;
    _hasConnected = false;

    _connectionOptions = io.OptionBuilder()
        // A shared cached Manager can retain another SDK instance's auth.
        .enableForceNew()
        .disableMultiplex()
        .disableAutoConnect()
        .setTransports(['websocket', 'polling'])
        .enableReconnection()
        .setReconnectionAttempts(double.infinity)
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(10000)
        .setTimeout(timeout.inMilliseconds)
        .setPath(socketPath)
        .setAuthFn((callback) => callback(_authData()))
        .build();

    _openSocket();
  }

  void _openSocket() {
    final url = _connectionUrl!;
    _log('Connecting to: $url');
    final socket =
        _socketFactory(url, Map<String, dynamic>.from(_connectionOptions!));
    _socket = socket;
    _setupListeners(socket);
    // Register every listener before the first handshake can complete.
    socket.connect();
  }

  Map<String, dynamic> _authData() => _isV2
      ? {'token': _token}
      : {
          'key': _apiKey,
          if (_currentBrowserKey != null) 'browser_key': _currentBrowserKey,
        };

  static String _withNamespace(String socketUrl, String? namespace) {
    final uri = Uri.parse(socketUrl);
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(
          socketUrl, 'socketUrl', 'An absolute URL is required');
    }
    if (namespace == null || namespace.isEmpty) return socketUrl;
    final normalized = namespace.startsWith('/') ? namespace : '/$namespace';
    return uri.replace(path: normalized).toString();
  }

  bool _isCurrent(io.Socket socket) => !_disposed && identical(socket, _socket);

  void _setupListeners(io.Socket socket) {
    socket.onConnect((_) {
      if (!_isCurrent(socket)) return;
      _log('Connected');
      if (!_isV2) {
        if (_currentBrowserKey != null) {
          socket.emit('join', 'private-chat_$_currentBrowserKey');
        }
        for (final channel in _subscriptions) {
          if (channel != 'private-chat_$_currentBrowserKey') {
            socket.emit('join', channel);
          }
        }
      }
      _connectionController.add(true);
      if (_hasConnected) _reconnectController.add(null);
      _hasConnected = true;
    });

    void handleError(dynamic error) {
      if (!_isCurrent(socket)) return;
      _log('Connection error');
      _connectionController.add(false);
      final text = error.toString();
      final lower = text.toLowerCase();
      if (lower.contains('unauthorized') ||
          lower.contains('authentication') ||
          lower.contains('invalid token') ||
          lower.contains('token expired')) {
        _authErrorController.add(text);
      }
    }

    socket.onConnectError(handleError);
    // socket_io_client 2.x maps a server CONNECT_ERROR packet to `error`.
    socket.on('error', handleError);
    socket.onDisconnect((reason) {
      if (!_isCurrent(socket)) return;
      _log('Disconnected: $reason');
      _connectionController.add(false);
      if (_isV2 && reason == 'io server disconnect') {
        // V2 intentionally disconnects at access-token expiry. Do not retry
        // the stale credential; let the session owner refresh/resume first.
        _authErrorController.add('unauthorized');
      } else if (!_isV2 && reason == 'io server disconnect') {
        _releaseSocket();
        _openSocket();
      }
    });

    // Reconnect events are emitted by the Manager, not the namespace Socket.
    socket.io.on('reconnect_attempt', _onReconnectAttempt);

    if (_isV2) {
      for (final event in ['message.created', 'message.updated']) {
        socket.on(event, (data) {
          if (!_isCurrent(socket)) return;
          _receiveV2(event, data);
        });
      }
      return;
    }

    for (final group in ['Chat', 'Telegram']) {
      for (final action in ['MessageEvent', 'MessageEditedEvent']) {
        for (final event in [
          'App:Events:$group:$action',
          'App\\Events\\$group\\$action',
        ]) {
          socket.on(event, (data) {
            if (!_isCurrent(socket)) return;
            _receiveLegacy(event, data);
          });
        }
      }
    }

    socket.on('typing', (data) {
      if (!_isCurrent(socket)) return;
      final payload = _asMap(data);
      if (payload == null) return;
      _typingController.add(payload['isTyping'] == true);
    });
    socket.on('auth-error', (data) {
      if (_isCurrent(socket)) _authErrorController.add(data.toString());
    });
    socket.on('browser-key-updated', (data) {
      if (!_isCurrent(socket)) return;
      final payload = _asMap(data);
      final key = payload?['browser_key']?.toString();
      if (key == null || key.isEmpty) return;
      updateBrowserKey(key);
      _browserKeyController.add(key);
    });
  }

  void _onReconnectAttempt(dynamic attempt) {
    if (!_disposed) _log('Reconnection attempt: $attempt');
  }

  static Map<String, dynamic>? _asMap(dynamic data) {
    if (data is String) {
      try {
        data = jsonDecode(data);
      } on FormatException {
        return null;
      }
    }
    if (data is! Map || data.keys.any((key) => key is! String)) return null;
    return Map<String, dynamic>.from(data);
  }

  void _receiveLegacy(String event, dynamic data) {
    final payload = _asMap(data);
    if (payload == null) return;
    final message = _asMap(payload['message'] ?? payload);
    if (message == null || message['id'] == null) return;
    try {
      _messageController.add(SocketMessage.fromJson({
        ...payload,
        'event': event,
        'message': message,
      }));
    } catch (_) {
      _log('Ignoring malformed message event');
    }
  }

  void _receiveV2(String event, dynamic data) {
    final payload = _asMap(data);
    if (payload == null || payload['id'] == null) return;
    try {
      final parsed = ChatEvent.fromJson({
        'cursor': payload['cursor'] ?? 0,
        'eventId': payload['eventId'],
        'event': event,
        'type': event,
        'data': payload,
        'message': payload,
      });
      _eventController.add(parsed);
      final message = parsed.message;
      if (message != null) {
        _messageController.add(SocketMessage(event: event, message: message));
      }
    } catch (_) {
      _log('Ignoring malformed v2 event');
    }
  }

  /// Adopt a renewed token. Reconnect so the server replaces its expiry timer.
  void updateToken(String token, {bool reconnect = true}) {
    _ensureAlive();
    if (!_isV2) throw StateError('The socket is not using a v2 session');
    if (token.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Must not be empty');
    }
    _token = token;
    final socket = _socket;
    if (socket == null) return;
    if (reconnect) {
      // Client 2.x closes its engine asynchronously. Reopening the same
      // Manager can let its previous engine close the replacement transport.
      // A fresh Manager also gives this session its own server expiry timer.
      _releaseSocket();
      _connectionController.add(false);
      _openSocket();
    }
  }

  /// Select the legacy visitor room. V2 rooms are derived by the server.
  void joinChatRoom(String browserKey) {
    if (_disposed || _isV2) return;
    if (_currentBrowserKey != browserKey) {
      updateBrowserKey(browserKey);
      return;
    }
    if (isConnected) _socket!.emit('join', 'private-chat_$browserKey');
  }

  void leaveChatRoom(String browserKey) {
    if (_disposed || _isV2) return;
    if (isConnected) _socket!.emit('leave', 'private-chat_$browserKey');
    if (_currentBrowserKey == browserKey) _currentBrowserKey = null;
  }

  /// Legacy typing only; v2 currently exposes no typing event.
  void sendTyping(String browserKey, bool isTyping) {
    if (_disposed || _isV2 || !isConnected) return;
    _socket!.emit('typing', {'browser_key': browserKey, 'isTyping': isTyping});
  }

  void updateBrowserKey(String browserKey) {
    if (_disposed || _isV2 || browserKey == _currentBrowserKey) return;
    if (_currentBrowserKey != null && isConnected) {
      _socket!.emit('leave', 'private-chat_$_currentBrowserKey');
    }
    _currentBrowserKey = browserKey;
    if (isConnected) _socket!.emit('join', 'private-chat_$browserKey');
  }

  /// Save a desired legacy subscription, including while disconnected.
  void subscribe(String channel) {
    if (_disposed || _isV2) return;
    if (_subscriptions.add(channel) && isConnected) {
      _socket!.emit('join', channel);
    }
  }

  void unsubscribe(String channel) {
    if (_disposed || _isV2) return;
    _subscriptions.remove(channel);
    if (isConnected) _socket!.emit('leave', channel);
  }

  void _releaseSocket() {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    socket.io.off('reconnect_attempt', _onReconnectAttempt);
    socket.dispose();
  }

  void disconnect() {
    if (_disposed) return;
    _releaseSocket();
    _currentBrowserKey = null;
    _token = null;
    _subscriptions.clear();
    _connectionUrl = null;
    _connectionOptions = null;
    _path = null;
    _hasConnected = false;
    _connectionController.add(false);
  }

  void dispose() {
    if (_disposed) return;
    disconnect();
    _disposed = true;
    _connectionController.close();
    _messageController.close();
    _eventController.close();
    _typingController.close();
    _browserKeyController.close();
    _reconnectController.close();
    _authErrorController.close();
  }

  void _ensureAlive() {
    if (_disposed) throw StateError('ChatSocketService has been disposed');
  }
}
