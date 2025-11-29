import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/message.dart';

/// Socket.IO service for real-time chat messaging
class ChatSocketService {
  io.Socket? _socket;
  String? _currentBrowserKey;
  final bool _enableLogging;

  // Stream controllers
  final _connectionController = StreamController<bool>.broadcast();
  final _messageController = StreamController<SocketMessage>.broadcast();
  final _typingController = StreamController<bool>.broadcast();
  final _browserKeyController = StreamController<String>.broadcast();

  /// Stream of connection status
  Stream<bool> get onConnectionChange => _connectionController.stream;

  /// Stream of incoming messages
  Stream<SocketMessage> get onMessage => _messageController.stream;

  /// Stream of typing indicators
  Stream<bool> get onTyping => _typingController.stream;

  /// Stream of browser key updates
  Stream<String> get onBrowserKeyUpdate => _browserKeyController.stream;

  /// Current connection status
  bool get isConnected => _socket?.connected ?? false;

  /// Current browser key
  String? get currentBrowserKey => _currentBrowserKey;

  ChatSocketService({bool enableLogging = false})
      : _enableLogging = enableLogging;

  void _log(String message) {
    if (_enableLogging) {
      print('[FCRM Socket] $message');
    }
  }

  /// Connect to socket server
  void connect({
    required String socketUrl,
    required String apiKey,
    String? browserKey,
  }) {
    if (_socket?.connected == true) {
      _log('Already connected');
      return;
    }

    _log('Connecting to: $socketUrl');

    final authData = <String, dynamic>{
      'key': apiKey,
    };

    if (browserKey != null) {
      authData['browser_key'] = browserKey;
      _currentBrowserKey = browserKey;
    }

    _socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(1000)
          .setTimeout(20000)
          .setAuth(authData)
          .build(),
    );

    _setupListeners();
  }

  /// Setup socket event listeners
  void _setupListeners() {
    if (_socket == null) return;

    // Remove any existing listeners to prevent duplicates
    _socket!.off('App:Events:Chat:MessageEvent');
    _socket!.off('App\\Events\\Chat\\MessageEvent');
    _socket!.off('App:Events:Telegram:MessageEvent');
    _socket!.off('App\\Events\\Telegram\\MessageEvent');
    _socket!.off('App:Events:Chat:MessageEditedEvent');
    _socket!.off('typing');
    _socket!.off('user-joined');
    _socket!.off('user-left');
    _socket!.off('auth-error');
    _socket!.off('browser-key-updated');
    _socket!.off('reconnect_attempt');
    _socket!.off('reconnect');

    // Connection established
    _socket!.onConnect((_) {
      _log('Connected: ${_socket!.id}');
      _connectionController.add(true);

      // Join chat room if browser key exists
      if (_currentBrowserKey != null) {
        joinChatRoom(_currentBrowserKey!);
      }
    });

    // Connection error
    _socket!.onConnectError((error) {
      _log('Connection error: $error');
      _connectionController.add(false);
    });

    // Disconnected
    _socket!.onDisconnect((reason) {
      _log('Disconnected: $reason');
      _connectionController.add(false);
    });

    // Reconnection attempt
    _socket!.on('reconnect_attempt', (attemptNumber) {
      _log('Reconnection attempt: $attemptNumber');
    });

    // Reconnected
    _socket!.on('reconnect', (attemptNumber) {
      _log('Reconnected after $attemptNumber attempts');
      _connectionController.add(true);

      // Rejoin chat room
      if (_currentBrowserKey != null) {
        joinChatRoom(_currentBrowserKey!);
      }
    });

    // Laravel broadcast messages (Chat App)
    // Listen for both formats: colons (from backend) and backslashes (legacy)
    _socket!.on('App:Events:Chat:MessageEvent', (data) {
      _log('Message received (colon format): $data');
      try {
        final socketMessage = SocketMessage.fromJson(
          data is Map<String, dynamic> ? data : {'message': data},
        );
        _messageController.add(socketMessage);
      } catch (e) {
        _log('Error parsing message: $e');
      }
    });

    // Legacy backslash format (for backward compatibility)
    _socket!.on('App\\Events\\Chat\\MessageEvent', (data) {
      _log('Message received (backslash format): $data');
      try {
        final socketMessage = SocketMessage.fromJson(
          data is Map<String, dynamic> ? data : {'message': data},
        );
        _messageController.add(socketMessage);
      } catch (e) {
        _log('Error parsing message: $e');
      }
    });

    // Telegram messages (colon format from backend)
    _socket!.on('App:Events:Telegram:MessageEvent', (data) {
      _log('Telegram message received (colon format): $data');
      try {
        final socketMessage = SocketMessage.fromJson(
          data is Map<String, dynamic> ? data : {'message': data},
        );
        _messageController.add(socketMessage);
      } catch (e) {
        _log('Error parsing telegram message: $e');
      }
    });

    // Telegram messages (legacy backslash format)
    _socket!.on('App\\Events\\Telegram\\MessageEvent', (data) {
      _log('Telegram message received (backslash format): $data');
      try {
        final socketMessage = SocketMessage.fromJson(
          data is Map<String, dynamic> ? data : {'message': data},
        );
        _messageController.add(socketMessage);
      } catch (e) {
        _log('Error parsing telegram message: $e');
      }
    });

    // Typing indicator
    _socket!.on('typing', (data) {
      final isTyping = data is Map ? data['isTyping'] == true : false;
      _log('Typing: $isTyping');
      _typingController.add(isTyping);
    });

    // User joined
    _socket!.on('user-joined', (data) {
      _log('User joined: $data');
    });

    // User left
    _socket!.on('user-left', (data) {
      _log('User left: $data');
    });

    // Authentication error
    _socket!.on('auth-error', (data) {
      _log('Auth error: $data');
    });

    // Browser key updated
    _socket!.on('browser-key-updated', (data) {
      if (data is Map && data['browser_key'] != null) {
        final newKey = data['browser_key'].toString();
        _log('Browser key updated: $newKey');
        _currentBrowserKey = newKey;
        _browserKeyController.add(newKey);
      }
    });
  }

  /// Join a chat room
  void joinChatRoom(String browserKey) {
    if (_socket?.connected != true) {
      _log('Cannot join room - not connected');
      return;
    }

    // Use underscore format to match backend channel naming
    final roomName = 'private-chat_$browserKey';
    _socket!.emit('join', roomName);
    _currentBrowserKey = browserKey;
    _log('Joined room: $roomName');
  }

  /// Leave a chat room
  void leaveChatRoom(String browserKey) {
    if (_socket?.connected != true) return;

    // Use underscore format to match backend channel naming
    final roomName = 'private-chat_$browserKey';
    _socket!.emit('leave', roomName);
    _log('Left room: $roomName');
  }

  /// Send typing indicator
  void sendTyping(String browserKey, bool isTyping) {
    if (_socket?.connected != true) return;

    _socket!.emit('typing', {
      'browser_key': browserKey,
      'isTyping': isTyping,
    });
  }

  /// Update browser key and rejoin room
  void updateBrowserKey(String browserKey) {
    if (browserKey == _currentBrowserKey) return;

    // Leave old room
    if (_currentBrowserKey != null && _socket?.connected == true) {
      leaveChatRoom(_currentBrowserKey!);
    }

    _currentBrowserKey = browserKey;

    // Join new room
    if (_socket?.connected == true) {
      joinChatRoom(browserKey);
    }
  }

  /// Subscribe to a channel
  void subscribe(String channel) {
    if (_socket?.connected != true) {
      _log('Cannot subscribe - not connected');
      return;
    }

    _socket!.emit('join', channel);
    _log('Subscribed to: $channel');
  }

  /// Unsubscribe from a channel
  void unsubscribe(String channel) {
    if (_socket?.connected != true) return;

    _socket!.emit('leave', channel);
    _log('Unsubscribed from: $channel');
  }

  /// Disconnect socket
  void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _currentBrowserKey = null;
      _connectionController.add(false);
      _log('Disconnected');
    }
  }

  /// Dispose all resources
  void dispose() {
    disconnect();
    _connectionController.close();
    _messageController.close();
    _typingController.close();
    _browserKeyController.close();
  }
}
