import 'dart:async';
import 'dart:io';

import 'config/chat_config.dart';
import 'models/chat_app_config.dart';
import 'models/browser.dart';
import 'models/message.dart';
import 'models/paginated_messages.dart';
import 'services/chat_api_service.dart' show ChatApiService, SendProgressCallback;
import 'services/chat_socket_service.dart';
import 'services/chat_storage_service.dart';

/// Main FCRM Chat SDK class
///
/// Use this class to integrate FCRM Chat into your Flutter application.
///
/// Example:
/// ```dart
/// final chat = FcrmChat(
///   config: ChatConfig(
///     baseUrl: 'https://api.yourcompany.com',
///     appKey: 'your-app-key',
///     appSecret: 'your-app-secret',
///   ),
/// );
///
/// await chat.initialize();
/// await chat.register(userData: {'name': 'John', 'phone': '+1234567890'});
/// await chat.sendMessage('Hello!');
/// ```
class FcrmChat {
  final ChatConfig config;

  late final ChatApiService _apiService;
  late final ChatSocketService _socketService;
  late final ChatStorageService _storageService;

  ChatAppRemoteConfig? _remoteConfig;
  String? _browserKey;
  int? _chatId;
  bool _isInitialized = false;

  // Stream controllers
  final _messageController = StreamController<ChatMessage>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _typingController = StreamController<bool>.broadcast();
  final _readyController = StreamController<bool>.broadcast();

  /// Stream of incoming messages
  Stream<ChatMessage> get onMessage => _messageController.stream;

  /// Stream of connection status changes
  Stream<bool> get onConnectionChange => _connectionController.stream;

  /// Stream of typing indicator changes
  Stream<bool> get onTyping => _typingController.stream;

  /// Stream emitted when chat is ready
  Stream<bool> get onReady => _readyController.stream;

  /// Current remote configuration
  ChatAppRemoteConfig? get remoteConfig => _remoteConfig;

  /// Current browser key
  String? get browserKey => _browserKey;

  /// Current chat ID
  int? get chatId => _chatId;

  /// Whether SDK is initialized
  bool get isInitialized => _isInitialized;

  /// Whether socket is connected
  bool get isConnected => _socketService.isConnected;

  /// Whether chat app is active
  bool get isActive => _remoteConfig?.isActive ?? false;

  FcrmChat({required this.config}) {
    _apiService = ChatApiService(config: config);
    _socketService = ChatSocketService(enableLogging: config.enableLogging);
    _storageService = ChatStorageService(appKey: config.appKey);

    // Forward socket events
    _socketService.onMessage.listen((socketMessage) {
      _messageController.add(socketMessage.message);
    });
    _socketService.onConnectionChange.listen((connected) {
      _connectionController.add(connected);
    });
    _socketService.onTyping.listen((typing) {
      _typingController.add(typing);
    });
    _socketService.onBrowserKeyUpdate.listen((key) async {
      _browserKey = key;
      await _storageService.saveBrowserKey(key);
    });
  }

  /// Initialize the chat SDK
  ///
  /// Fetches remote configuration and establishes socket connection.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Get remote configuration
      _remoteConfig = await _apiService.getConfig();

      if (!_remoteConfig!.isActive) {
        throw ChatException('Chat app is not active');
      }

      // Get stored browser key
      _browserKey = await _storageService.getBrowserKey();

      // Connect to socket
      _socketService.connect(
        socketUrl: config.socketUrl ?? _remoteConfig!.socketUrl,
        apiKey: _remoteConfig!.socketApiKey,
        browserKey: _browserKey,
      );

      _isInitialized = true;
      _readyController.add(true);
    } catch (e) {
      _readyController.add(false);
      rethrow;
    }
  }

  /// Register a new browser/device
  ///
  /// [userData] - User information (name, phone, email, etc.)
  /// [endpoint] - Optional endpoint/screen name
  Future<void> register({
    required Map<String, dynamic> userData,
    String? endpoint,
  }) async {
    _ensureInitialized();

    // Validate required fields
    final requiredFields = _remoteConfig!.requiredFields;
    for (final entry in requiredFields.entries) {
      if (userData[entry.key] == null ||
          userData[entry.key].toString().isEmpty) {
        throw ChatException('Missing required field: ${entry.value}');
      }
    }

    // Register browser
    final response = await _apiService.registerBrowser(
      userData: userData,
      endpoint: endpoint,
    );

    _browserKey = response.browserKey;
    _chatId = response.chatId;

    // Save to storage
    await _storageService.saveBrowserKey(_browserKey!);
    userData['registered'] = true;
    userData['registrationDate'] = DateTime.now().toIso8601String();
    await _storageService.saveUserData(userData);

    // Update socket connection
    _socketService.updateBrowserKey(_browserKey!);
  }

  /// Update browser/device information
  ///
  /// [userData] - Updated user information
  Future<List<ChatMessage>> updateBrowser({
    required Map<String, dynamic> userData,
  }) async {
    _ensureInitialized();
    _ensureBrowserKey();

    final response = await _apiService.updateBrowser(
      browserKey: _browserKey!,
      userData: userData,
    );

    _chatId = response.chatId;

    // Parse last messages
    final messages = <ChatMessage>[];
    if (response.lastMessages != null) {
      for (final m in response.lastMessages!) {
        if (m is Map<String, dynamic>) {
          messages.add(ChatMessage.fromJson(m));
        }
      }
    }

    // Update storage
    await _storageService.saveUserData(userData);

    return messages;
  }

  /// Send a text message
  ///
  /// [message] - Message content
  /// [endpoint] - Optional endpoint/screen name
  Future<SendMessageResponse> sendMessage(
    String message, {
    String? endpoint,
  }) async {
    _ensureInitialized();
    _ensureBrowserKey();

    return await _apiService.sendMessage(
      browserKey: _browserKey!,
      message: message,
      endpoint: endpoint,
    );
  }

  /// Upload and send an image
  ///
  /// [imageFile] - Image file to upload
  /// [endpoint] - Optional endpoint/screen name
  /// [onSendProgress] - Optional callback for tracking upload progress (sent bytes, total bytes)
  Future<Map<String, dynamic>> sendImage(
    File imageFile, {
    String? endpoint,
    SendProgressCallback? onSendProgress,
  }) async {
    _ensureInitialized();
    _ensureBrowserKey();

    return await _apiService.uploadImage(
      browserKey: _browserKey!,
      imageFile: imageFile,
      endpoint: endpoint,
      onSendProgress: onSendProgress,
    );
  }

  /// Get chat message history with pagination
  ///
  /// [page] - Page number (default: 1)
  /// [perPage] - Number of messages per page (default: 20)
  Future<PaginatedMessages> getMessages({
    int page = 1,
    int perPage = 20,
  }) async {
    _ensureInitialized();
    _ensureBrowserKey();

    return await _apiService.getMessages(
      browserKey: _browserKey!,
      page: page,
      perPage: perPage,
    );
  }

  /// Load chat messages for history/regeneration with pagination
  ///
  /// This is useful when you want to load chat history when app starts
  /// or when regenerating the chat page. It will:
  /// 1. Check if user is registered
  /// 2. Update browser session with stored user data
  /// 3. Return paginated message history
  ///
  /// [page] - Page number (default: 1)
  /// [perPage] - Number of messages per page (default: 20)
  ///
  /// Returns empty PaginatedMessages if user is not registered
  Future<PaginatedMessages> loadMessages({
    int page = 1,
    int perPage = 20,
  }) async {
    _ensureInitialized();

    // Check if browser key exists
    if (_browserKey == null) {
      // Try to load from storage
      _browserKey = await _storageService.getBrowserKey();
    }

    // If still no browser key, user is not registered
    if (_browserKey == null) {
      return PaginatedMessages(
        messages: [],
        total: 0,
        currentPage: 1,
        perPage: perPage,
        lastPage: 1,
        hasMore: false,
      );
    }

    // Get stored user data
    final userData = await _storageService.getUserData();
    if (userData == null) {
      return PaginatedMessages(
        messages: [],
        total: 0,
        currentPage: 1,
        perPage: perPage,
        lastPage: 1,
        hasMore: false,
      );
    }

    try {
      // Try to get messages directly with pagination
      return await getMessages(page: page, perPage: perPage);
    } catch (e) {
      // If fails, return empty paginated response
      return PaginatedMessages(
        messages: [],
        total: 0,
        currentPage: 1,
        perPage: perPage,
        lastPage: 1,
        hasMore: false,
      );
    }
  }

  /// Send typing indicator
  void sendTyping(bool isTyping) {
    if (_browserKey != null) {
      _socketService.sendTyping(_browserKey!, isTyping);
    }
  }

  /// Check if user is registered
  Future<bool> isRegistered() async {
    return await _storageService.isRegistered();
  }

  /// Get stored user data
  Future<Map<String, dynamic>?> getUserData() async {
    return await _storageService.getUserData();
  }

  /// Clear all stored data and reset
  Future<void> reset() async {
    await _storageService.clearAll();
    _browserKey = null;
    _chatId = null;
    _socketService.disconnect();
  }

  /// Disconnect from chat
  void disconnect() {
    _socketService.disconnect();
  }

  /// Reconnect to chat
  void reconnect() {
    if (_remoteConfig != null) {
      _socketService.connect(
        socketUrl: config.socketUrl ?? _remoteConfig!.socketUrl,
        apiKey: _remoteConfig!.socketApiKey,
        browserKey: _browserKey,
      );
    }
  }

  /// Dispose all resources
  void dispose() {
    _apiService.dispose();
    _socketService.dispose();
    _messageController.close();
    _connectionController.close();
    _typingController.close();
    _readyController.close();
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw ChatException('Chat not initialized. Call initialize() first.');
    }
  }

  void _ensureBrowserKey() {
    if (_browserKey == null) {
      throw ChatException('Not registered. Call register() first.');
    }
  }
}

/// Chat exception
class ChatException implements Exception {
  final String message;

  ChatException(this.message);

  @override
  String toString() => 'ChatException: $message';
}
