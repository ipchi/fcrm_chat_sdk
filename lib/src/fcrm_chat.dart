import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import 'config/chat_config.dart';
import 'models/chat_app_config.dart';
import 'models/chat_event.dart';
import 'models/browser.dart';
import 'models/message.dart';
import 'models/message_rating.dart';
import 'models/paginated_messages.dart';
import 'services/chat_api_service.dart';
import 'services/chat_socket_service.dart';
import 'services/chat_storage_service.dart';
import 'services/chat_v2_api_service.dart';

/// Main FCRM Chat SDK class
///
/// Use this class to integrate FCRM Chat into your Flutter application.
///
/// Example:
/// ```dart
/// final chat = FcrmChat(
///   config: ChatConfig(
///     baseUrl: 'https://api.yourcompany.com',
///     companyToken: 'your-company-token',
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
  late final ChatStorageService _v2Storage;
  final http.Client? _httpClient;
  ChatV2ApiService? _v2Api;
  String? _accessToken;
  DateTime? _expiresAt;
  int? _visitorId;
  Timer? _refreshTimer;
  Future<void>? _refreshing;
  Future<void>? _syncing;
  Future<void>? _initializing;
  int _sessionGeneration = 0;
  int _eventCursor = 0;
  final _seenEvents = <String, int>{};
  final _messageCursors = <String, int>{};
  final _historyCursors = <int, Map<int, int?>>{};
  bool _disposed = false;
  bool _manuallyDisconnected = false;
  final _subscriptions = <StreamSubscription<dynamic>>[];

  ChatAppRemoteConfig? _remoteConfig;
  String? _browserKey;
  int? _chatId;
  bool _isInitialized = false;

  // Stream controllers
  final _messageController = StreamController<ChatMessage>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _typingController = StreamController<bool>.broadcast();
  final _readyController = StreamController<bool>.broadcast();
  final _eventController = StreamController<ChatEvent>.broadcast();
  final _errorController = StreamController<Object>.broadcast();

  /// Stream of incoming messages
  Stream<ChatMessage> get onMessage => _messageController.stream;

  /// Stream of connection status changes
  Stream<bool> get onConnectionChange => _connectionController.stream;

  /// Stream of typing indicator changes
  Stream<bool> get onTyping => _typingController.stream;

  /// Stream emitted when chat is ready
  Stream<bool> get onReady => _readyController.stream;

  /// Durable v2 message creation/update events, including reconnect recovery.
  Stream<ChatEvent> get onEvent => _eventController.stream;

  /// Background session refresh and event recovery errors.
  Stream<Object> get onError => _errorController.stream;

  /// Whether the server negotiated the v2 protocol.
  bool get isV2 => _v2Api != null;

  /// v2 visitor identifier. This is not a legacy browser credential.
  int? get visitorId => _visitorId;

  /// Last fully recovered durable event cursor (live events can arrive ahead).
  int get eventCursor => _eventCursor;

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

  FcrmChat({
    required this.config,
    http.Client? httpClient,
    ChatSocketService? socketService,
  }) : _httpClient = httpClient {
    _apiService = ChatApiService(config: config, client: httpClient);
    _socketService =
        socketService ?? ChatSocketService(enableLogging: config.enableLogging);
    _storageService = ChatStorageService(appKey: config.appKey);
    _v2Storage = ChatStorageService(
      appKey: 'v2_${Uri.encodeComponent(config.apiUrl)}_${config.appKey}',
    );

    // Forward socket events
    _subscriptions.add(_socketService.onMessage.listen((socketMessage) {
      if (!_disposed && !isV2 && _browserKey != null) {
        _messageController.add(socketMessage.message);
      }
    }));
    _subscriptions.add(_socketService.onEvent.listen((event) {
      if (!_disposed && isV2 && _accessToken != null) _deliverEvent(event);
    }));
    _subscriptions.add(_socketService.onConnectionChange.listen((connected) {
      if (_disposed) return;
      _connectionController.add(connected);
      if (connected && _isInitialized && isV2 && _accessToken != null) {
        unawaited(syncEvents().catchError(_reportError));
      }
    }));
    _subscriptions.add(_socketService.onAuthError.listen((_) {
      if (isV2) _renewSessionInBackground();
    }));
    _subscriptions.add(_socketService.onTyping.listen((typing) {
      if (!_disposed) _typingController.add(typing);
    }));
    _subscriptions.add(_socketService.onBrowserKeyUpdate.listen((key) async {
      if (_disposed || isV2 || _browserKey == null) return;
      _browserKey = key;
      await _storageService.saveBrowserKey(key);
    }));
  }

  /// Initialize the chat SDK
  ///
  /// Fetches remote configuration and establishes socket connection.
  Future<void> initialize() {
    if (_disposed) throw ChatException('Chat has been disposed.');
    if (_isInitialized) return Future.value();
    return _initializing ??=
        _initialize().whenComplete(() => _initializing = null);
  }

  Future<void> _initialize() async {
    final generation = _sessionGeneration;
    try {
      // Get remote configuration
      _remoteConfig = await _apiService.getConfig();
      _ensureSessionGeneration(generation);

      if (!_remoteConfig!.isActive) {
        throw ChatException('Chat app is not active');
      }

      final v2 = config.enableV2 ? _remoteConfig!.v2 : null;
      if (v2 != null) {
        _v2Api?.dispose();
        _v2Api = ChatV2ApiService(
          config: config,
          baseUrl: v2.baseUrl,
          appKey: v2.appKey,
          client: _httpClient,
        );
        await _resumeSession();
      } else {
        _v2Api?.dispose();
        _v2Api = null;
        _clearV2Memory();
        _browserKey = await _storageService.getBrowserKey();
        _ensureSessionGeneration(generation);
        _connectSocket();
      }

      _ensureSessionGeneration(generation);
      _isInitialized = true;
      _readyController.add(true);
      if (isV2 && isConnected) {
        unawaited(syncEvents().catchError(_reportError));
      }
    } catch (e) {
      if (!_disposed) _readyController.add(false);
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

    if (isV2) {
      final generation = ++_sessionGeneration;
      _clearV2Memory();
      _socketService.disconnect();
      final session = await _v2Api!.startSession(
        userData: userData,
        endpoint: endpoint,
      );
      await _adoptSession(session, generation);
      await _v2Storage.saveUserData({
        ...userData,
        'registered': true,
        'registrationDate': DateTime.now().toIso8601String(),
      });
      return;
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
    await _storageService.saveUserData({
      ...userData,
      'registered': true,
      'registrationDate': DateTime.now().toIso8601String(),
    });

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

  /// Update specific user data fields (partial update)
  ///
  /// Only updates the provided fields, preserves other existing data.
  /// Useful for updating individual fields like name, phone, email, etc.
  ///
  /// Example:
  /// ```dart
  /// // Update only name
  /// await chat.updateUserData({'name': 'New Name'});
  ///
  /// // Update multiple fields
  /// await chat.updateUserData({
  ///   'name': 'John Doe',
  ///   'phone': '+1234567890',
  /// });
  /// ```
  ///
  /// Returns the complete updated user data
  Future<Map<String, dynamic>> updateUserData(Map<String, dynamic> data) async {
    _ensureInitialized();
    _ensureBrowserKey();

    final response = await _apiService.updateUserData(
      browserKey: _browserKey!,
      data: data,
    );

    // Update stored user data
    await _storageService.saveUserData(response.userData);

    return response.userData;
  }

  /// Convenience method to update only the client name
  ///
  /// [name] - New name for the client
  /// Returns the complete updated user data
  Future<Map<String, dynamic>> updateName(String name) async {
    return updateUserData({'name': name});
  }

  /// Convenience method to update only the client phone
  ///
  /// [phone] - New phone for the client
  /// Returns the complete updated user data
  Future<Map<String, dynamic>> updatePhone(String phone) async {
    return updateUserData({'phone': phone});
  }

  /// Convenience method to update only the client email
  ///
  /// [email] - New email for the client
  /// Returns the complete updated user data
  Future<Map<String, dynamic>> updateEmail(String email) async {
    return updateUserData({'email': email});
  }

  /// Send a text message
  ///
  /// [message] - Message content
  /// [endpoint] - Optional endpoint/screen name
  /// [metadata] - Optional metadata to attach to the message
  Future<SendMessageResponse> sendMessage(
    String message, {
    String? endpoint,
    Map<String, dynamic>? metadata,
    String? clientMessageId,
  }) async {
    _ensureInitialized();
    _ensureRegistration();

    if (isV2) {
      if (metadata != null && metadata.isNotEmpty) {
        throw ChatException(
            'The v2 API does not accept custom message metadata.');
      }
      final id = clientMessageId ?? newClientMessageId();
      final data = await _withV2Token((token) => _v2Api!.sendMessage(
            accessToken: token,
            content: message,
            clientMessageId: id,
            endpoint: endpoint,
          ));
      return SendMessageResponse.fromJson(data);
    }

    return await _apiService.sendMessage(
      browserKey: _browserKey!,
      message: message,
      endpoint: endpoint,
      metadata: metadata,
    );
  }

  /// Edit a message (only allowed within 1 day of creation)
  ///
  /// [messageId] - The ID of the message to edit
  /// [content] - The new content for the message
  ///
  /// Throws an exception if:
  /// - Message is older than 24 hours
  /// - Message was not sent by this browser/user
  /// - Message doesn't exist
  ///
  /// Example:
  /// ```dart
  /// try {
  ///   final result = await chat.editMessage(
  ///     messageId: 123,
  ///     content: 'Updated message content',
  ///   );
  ///   print('Message edited: ${result.content}');
  /// } catch (e) {
  ///   print('Cannot edit: $e');
  /// }
  /// ```
  /// Rate an admin answer from 1 to 5 stars.
  ///
  /// [publicMessageId] is [ChatMessage.publicId] — the opaque id, not the
  /// numeric one. The comment is always optional: omit it to leave any
  /// existing comment untouched, or pass an empty string to clear it while
  /// keeping the rating.
  Future<MessageRating> rateMessage({
    required String publicMessageId,
    required int rating,
    String? comment,
    bool commentProvided = false,
  }) async {
    _ensureInitialized();
    _ensureBrowserKey();

    return await _apiService.rateMessage(
      browserKey: _browserKey!,
      publicMessageId: publicMessageId,
      rating: rating,
      comment: comment,
      commentProvided: commentProvided,
    );
  }

  /// Read back this client's rating of a message, or null if it has none.
  Future<MessageRating?> getRating({required String publicMessageId}) async {
    _ensureInitialized();
    _ensureBrowserKey();

    return await _apiService.getRating(
      browserKey: _browserKey!,
      publicMessageId: publicMessageId,
    );
  }

  /// Remove this client's rating of a message.
  Future<bool> removeRating({required String publicMessageId}) async {
    _ensureInitialized();
    _ensureBrowserKey();

    return await _apiService.removeRating(
      browserKey: _browserKey!,
      publicMessageId: publicMessageId,
    );
  }

  /// Register this device to receive push notifications.
  ///
  /// This SDK does not manage Firebase itself — obtain [token] from your own
  /// app's FCM/APNs setup (e.g. `FirebaseMessaging.instance.getToken()`,
  /// which requires `google-services.json`/`GoogleService-Info.plist` to
  /// already be configured per Mobile/FIREBASE_SETUP.md in the backend repo)
  /// and pass it here. [platform] is `'android'` or `'ios'`; [deviceType] is
  /// `'fcm'` for both today (`'apns'` is reserved for a direct-APNs path).
  ///
  /// Safe to call every app start / on token refresh: re-registering the
  /// same token updates the existing record instead of duplicating it.
  Future<void> registerPushDevice({
    required String token,
    required String platform,
    String deviceType = 'fcm',
    String? deviceName,
    String? deviceModel,
    String? osVersion,
    String? appVersion,
    String? locale,
  }) async {
    _ensureInitialized();
    _ensureBrowserKey();

    await _apiService.registerPushDevice(
      browserKey: _browserKey!,
      token: token,
      platform: platform,
      deviceType: deviceType,
      deviceName: deviceName,
      deviceModel: deviceModel,
      osVersion: osVersion,
      appVersion: appVersion,
      locale: locale,
    );
  }

  /// Keep-alive for a registered push device. Call this periodically (e.g. on
  /// app resume) if you want stale-device cleanup on the backend to have a
  /// recent last_seen_at to work from; not required for delivery itself.
  Future<void> sendPushHeartbeat(String token) async {
    _ensureInitialized();
    _ensureBrowserKey();

    await _apiService.sendPushHeartbeat(browserKey: _browserKey!, token: token);
  }

  /// Stop push notifications to this device — call on logout or when the
  /// user opts out.
  Future<void> unregisterPushDevice(String token) async {
    _ensureInitialized();
    _ensureBrowserKey();

    await _apiService.unregisterPushDevice(
        browserKey: _browserKey!, token: token);
  }

  Future<EditMessageResponse> editMessage({
    required int messageId,
    required String content,
  }) async {
    _ensureInitialized();
    _ensureBrowserKey();

    return await _apiService.editMessage(
      browserKey: _browserKey!,
      messageId: messageId,
      content: content,
    );
  }

  /// Upload and send an image
  ///
  /// [imageFile] - Image file to upload
  /// [endpoint] - Optional endpoint/screen name
  /// [onSendProgress] - Optional callback for tracking upload progress (sent bytes, total bytes)
  /// [cancelToken] - Optional token to cancel the upload
  ///
  /// Example with cancellation:
  /// ```dart
  /// final cancelToken = CancelToken();
  ///
  /// // Start upload
  /// final uploadFuture = chat.sendImage(
  ///   imageFile,
  ///   onSendProgress: (sent, total) {
  ///     print('Progress: ${(sent / total * 100).toStringAsFixed(1)}%');
  ///   },
  ///   cancelToken: cancelToken,
  /// );
  ///
  /// // Cancel after 2 seconds
  /// Future.delayed(Duration(seconds: 2), () {
  ///   cancelToken.cancel();
  /// });
  ///
  /// try {
  ///   final result = await uploadFuture;
  ///   print('Uploaded: ${result['image_url']}');
  /// } on UploadCancelledException {
  ///   print('Upload was cancelled');
  /// }
  /// ```
  Future<Map<String, dynamic>> sendImage(
    File imageFile, {
    String? endpoint,
    SendProgressCallback? onSendProgress,
    CancelToken? cancelToken,
    String? clientMessageId,
  }) async {
    _ensureInitialized();
    _ensureRegistration();

    if (isV2) {
      return _uploadAttachment(
        imageFile,
        kind: 'image',
        endpoint: endpoint,
        clientMessageId: clientMessageId,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
    }

    return await _apiService.uploadImage(
      browserKey: _browserKey!,
      imageFile: imageFile,
      endpoint: endpoint,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  /// Upload and send a file
  ///
  /// [file] - File to upload
  /// [endpoint] - Optional endpoint/screen name
  /// [onSendProgress] - Optional callback for tracking upload progress (sent bytes, total bytes)
  /// [cancelToken] - Optional token to cancel the upload
  ///
  /// Example:
  /// ```dart
  /// final cancelToken = CancelToken();
  ///
  /// try {
  ///   final result = await chat.sendFile(
  ///     myFile,
  ///     onSendProgress: (sent, total) {
  ///       print('Progress: ${(sent / total * 100).toStringAsFixed(1)}%');
  ///     },
  ///     cancelToken: cancelToken,
  ///   );
  ///   print('Uploaded: ${result['image_url']}');
  /// } on UploadCancelledException {
  ///   print('Upload was cancelled');
  /// }
  /// ```
  Future<Map<String, dynamic>> sendFile(
    File file, {
    String? endpoint,
    SendProgressCallback? onSendProgress,
    CancelToken? cancelToken,
    String? clientMessageId,
  }) async {
    _ensureInitialized();
    _ensureRegistration();

    if (isV2) {
      final mime = lookupMimeType(file.path) ?? '';
      if (mime.startsWith('audio/') ||
          file.path.toLowerCase().endsWith('.webm')) {
        return sendAudio(file,
            endpoint: endpoint,
            clientMessageId: clientMessageId,
            onSendProgress: onSendProgress,
            cancelToken: cancelToken);
      }
      if (mime.startsWith('image/')) {
        return sendImage(file,
            endpoint: endpoint,
            clientMessageId: clientMessageId,
            onSendProgress: onSendProgress,
            cancelToken: cancelToken);
      }
      throw ChatException('The v2 API supports image and audio attachments.');
    }

    return await _apiService.uploadFile(
      browserKey: _browserKey!,
      file: file,
      endpoint: endpoint,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
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
    _ensureRegistration();

    if (isV2) return _getV2Page(page: page, perPage: perPage);

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

    if (isV2) {
      if (_accessToken == null) {
        return PaginatedMessages(
          messages: [],
          total: 0,
          currentPage: 1,
          perPage: perPage,
          lastPage: 1,
          hasMore: false,
          hasExactTotal: false,
        );
      }
      return getMessages(page: page, perPage: perPage);
    }

    // Check if browser key exists
    _browserKey ??= await _storageService.getBrowserKey();

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
    if (isV2) return _accessToken != null;
    return await _storageService.isRegistered();
  }

  /// Get stored user data
  Future<Map<String, dynamic>?> getUserData() async {
    return await (isV2 ? _v2Storage : _storageService).getUserData();
  }

  /// Clear all stored data and reset
  Future<void> reset() async {
    ++_sessionGeneration;
    _clearV2Memory();
    _browserKey = null;
    _chatId = null;
    _socketService.disconnect();
    await _storageService.clearAll();
    await _v2Storage.clearAll();
  }

  /// Disconnect from chat
  void disconnect() {
    _manuallyDisconnected = true;
    _refreshTimer?.cancel();
    _socketService.disconnect();
  }

  /// Reconnect to chat
  void reconnect() {
    if (_disposed) return;
    _manuallyDisconnected = false;
    if (isV2 && _accessToken != null) {
      unawaited(_withV2Token((_) async {
        _scheduleRefresh();
        _connectSocket();
      }).catchError(_reportError));
    } else {
      _connectSocket();
    }
  }

  /// Dispose all resources
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_sessionGeneration;
    _clearV2Memory();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _apiService.dispose();
    _v2Api?.dispose();
    _socketService.dispose();
    _messageController.close();
    _connectionController.close();
    _typingController.close();
    _readyController.close();
    _eventController.close();
    _errorController.close();
  }

  /// Generate an id to retain across retries of the same v2 send.
  static String newClientMessageId() {
    final random = Random.secure();
    return 'c_${List.generate(12, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  /// Send a recorded voice file through the v2 attachment API.
  /// Recording and playback are managed by the host application.
  Future<Map<String, dynamic>> sendAudio(
    File audioFile, {
    int? durationMs,
    String? endpoint,
    String? clientMessageId,
    SendProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    _ensureInitialized();
    _ensureV2();
    _ensureRegistration();
    return _uploadAttachment(
      audioFile,
      kind: 'audio',
      durationMs: durationMs,
      endpoint: endpoint,
      clientMessageId: clientMessageId,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  Future<Map<String, dynamic>> _uploadAttachment(
    File file, {
    required String kind,
    int? durationMs,
    String? endpoint,
    String? clientMessageId,
    SendProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) {
    final id = clientMessageId ?? newClientMessageId();
    return _withV2Token((token) => _v2Api!.uploadAttachment(
          accessToken: token,
          file: file,
          kind: kind,
          durationMs: durationMs,
          clientMessageId: id,
          endpoint: endpoint,
          onSendProgress: onSendProgress,
          cancelToken: cancelToken,
        ));
  }

  /// V2 history in chronological order. Pass the previous page's [ChatHistory.beforeSeq]
  /// to retrieve older messages. The server provides no exact total count.
  Future<ChatHistory> getHistory({int? before, int limit = 30}) async {
    _ensureInitialized();
    _ensureV2();
    _ensureRegistration();
    final data = await _withV2Token((token) => _v2Api!.getMessages(
          accessToken: token,
          before: before,
          limit: limit,
        ));
    return ChatHistory.fromJson(data);
  }

  /// Mark operator/AI messages through this sequence as read (v2).
  Future<int> markRead({required int upToSeq}) async {
    _ensureInitialized();
    _ensureV2();
    _ensureRegistration();
    return _withV2Token((token) => _v2Api!.markRead(
          accessToken: token,
          upToSeq: upToSeq,
        ));
  }

  /// Recover durable events missed while offline. Also called after socket connection.
  /// Events received live are deduplicated against the recovered events.
  Future<void> syncEvents() {
    _ensureInitialized();
    _ensureV2();
    _ensureRegistration();
    final pending = _syncing;
    if (pending != null) return pending;
    final generation = _sessionGeneration;
    late final Future<void> future;
    future = (() async {
      while (!_disposed && generation == _sessionGeneration) {
        final page = ChatEventPage.fromJson(await _withV2Token(
          (token) => _v2Api!.getEvents(accessToken: token, after: _eventCursor),
        ));
        if (_disposed || generation != _sessionGeneration) return;
        for (final event in page.events) {
          _deliverEvent(event);
        }
        if (page.nextCursor <= _eventCursor || page.events.isEmpty) return;
        _eventCursor = page.nextCursor;
        _seenEvents
            .removeWhere((_, cursor) => cursor > 0 && cursor <= _eventCursor);
        _messageCursors.removeWhere((_, cursor) => cursor <= _eventCursor);
      }
    })()
        .whenComplete(() {
      if (identical(_syncing, future)) _syncing = null;
    });
    _syncing = future;
    return future;
  }

  void _deliverEvent(ChatEvent event) {
    if (_disposed) return;
    if (event.cursor > 0 && event.cursor <= _eventCursor) return;
    final key = event.eventId ?? (event.cursor > 0 ? '${event.cursor}' : null);
    if (key != null) {
      if (_seenEvents.containsKey(key)) return;
      _seenEvents[key] = event.cursor;
    }
    final message = event.message;
    if (message != null && event.cursor > 0) {
      final messageKey = message.publicId ?? '${message.id}';
      final previous = _messageCursors[messageKey];
      if (previous != null && previous >= event.cursor) return;
      _messageCursors.remove(messageKey);
      _messageCursors[messageKey] = event.cursor;
    }
    _eventController.add(event);
    if (message != null) _messageController.add(message);
  }

  Future<PaginatedMessages> _getV2Page(
      {required int page, required int perPage}) async {
    if (page < 1 || perPage < 1 || perPage > 50) {
      throw ArgumentError(
          'V2 page must be positive and perPage between 1 and 50.');
    }
    if (page == 1) _historyCursors.remove(perPage);
    final cursors = _historyCursors.putIfAbsent(perPage, () => {1: null});
    var current = page;
    while (!cursors.containsKey(current)) {
      --current;
    }
    var history = const ChatHistory(messages: [], hasMore: false);
    var total = 0;
    var lastPage = page;
    while (current <= page) {
      history = await getHistory(before: cursors[current], limit: perPage);
      total = (current - 1) * perPage + history.messages.length;
      lastPage = current + (history.hasMore ? 1 : 0);
      if (history.hasMore && history.beforeSeq != null) {
        cursors[current + 1] = history.beforeSeq;
      } else if (current < page) {
        history = const ChatHistory(messages: [], hasMore: false);
        break;
      }
      ++current;
    }
    return PaginatedMessages(
      messages: history.messages,
      total: total,
      currentPage: page,
      perPage: perPage,
      lastPage: lastPage,
      hasMore: history.hasMore,
      hasExactTotal: false,
      nextBeforeSeq: history.hasMore ? history.beforeSeq : null,
    );
  }

  void _connectSocket() {
    if (_disposed || _manuallyDisconnected || _remoteConfig == null) return;
    final v2 = _remoteConfig!.v2;
    if (isV2) {
      if (_accessToken == null || v2 == null) return;
      _socketService.connect(
        socketUrl: config.socketUrl ?? v2.baseUrl,
        token: _accessToken,
        namespace: v2.socketNamespace,
        path: v2.socketPath,
        timeout: Duration(milliseconds: config.connectionTimeout),
      );
    } else {
      _socketService.connect(
        socketUrl: config.socketUrl ?? _remoteConfig!.socketUrl,
        apiKey: _remoteConfig!.socketApiKey,
        browserKey: _browserKey,
        timeout: Duration(milliseconds: config.connectionTimeout),
      );
    }
  }

  Future<void> _adoptSession(
      Map<String, dynamic> session, int generation) async {
    _ensureSessionGeneration(generation);
    final token = session['access_token'] as String?;
    final lifetime = (session['expires_in'] as num?)?.toInt();
    if (token == null || token.isEmpty || lifetime == null || lifetime <= 0) {
      throw ChatException('Invalid v2 session response.');
    }
    final resume = session['resume_token'] as String?;
    if (resume != null && resume.isNotEmpty) {
      await _v2Storage.saveResumeToken(resume);
      _ensureSessionGeneration(generation);
    }
    _accessToken = token;
    _expiresAt = DateTime.now().add(Duration(seconds: lifetime));
    if (session['visitor'] is Map) {
      _visitorId = (session['visitor']['id'] as num?)?.toInt();
    }
    if (!_manuallyDisconnected) {
      _scheduleRefresh();
      _connectSocket();
    }
  }

  Future<bool> _resumeSession() async {
    final generation = _sessionGeneration;
    final resume = await _v2Storage.getResumeToken();
    _ensureSessionGeneration(generation);
    if (resume == null) return false;
    try {
      final session = await _v2Api!.resumeSession(resumeToken: resume);
      await _adoptSession(session, generation);
      return true;
    } on ChatApiException catch (error) {
      if (error.statusCode != 403 && error.statusCode != 404) rethrow;
      _ensureSessionGeneration(generation);
      _clearV2Memory();
      _socketService.disconnect();
      await _v2Storage.clearAll();
      return false;
    }
  }

  Future<void> _refreshAccessToken() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final generation = _sessionGeneration;
    late final Future<void> future;
    future = (() async {
      final token = _accessToken;
      if (token == null) {
        throw ChatException('Not registered. Call register() first.');
      }
      try {
        final session = await _v2Api!.refreshSession(accessToken: token);
        await _adoptSession(session, generation);
      } on ChatApiException catch (error) {
        _ensureSessionGeneration(generation);
        if (error.statusCode != 401 && error.statusCode != 403) rethrow;
        if (!await _resumeSession()) {
          throw ChatException('Session ended. Call register() again.');
        }
      }
    })()
        .whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
    _refreshing = future;
    return future;
  }

  Future<T> _withV2Token<T>(Future<T> Function(String token) run) async {
    final generation = _sessionGeneration;
    if (_expiresAt != null &&
        DateTime.now()
            .isAfter(_expiresAt!.subtract(const Duration(seconds: 5)))) {
      await _refreshAccessToken();
    }
    _ensureSessionGeneration(generation);
    final token = _accessToken;
    if (token == null) {
      throw ChatException('Not registered. Call register() first.');
    }
    try {
      final result = await run(token);
      _ensureSessionGeneration(generation);
      return result;
    } on ChatApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      _ensureSessionGeneration(generation);
      if (_accessToken == token) await _refreshAccessToken();
      _ensureSessionGeneration(generation);
      final result = await run(_accessToken!);
      _ensureSessionGeneration(generation);
      return result;
    }
  }

  void _clearV2Memory() {
    _refreshTimer?.cancel();
    _accessToken = null;
    _expiresAt = null;
    _visitorId = null;
    _eventCursor = 0;
    _seenEvents.clear();
    _messageCursors.clear();
    _historyCursors.clear();
    _refreshing = null;
    _syncing = null;
  }

  void _ensureSessionGeneration(int generation) {
    if (_disposed || generation != _sessionGeneration) {
      throw ChatException('Chat session changed during the request.');
    }
  }

  void _reportError(Object error) {
    if (!_disposed) _errorController.add(error);
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (_expiresAt == null || _manuallyDisconnected || _disposed) return;
    final remaining = _expiresAt!.difference(DateTime.now()).inMilliseconds;
    _refreshTimer = Timer(Duration(milliseconds: max(1, remaining * 7 ~/ 10)),
        _renewSessionInBackground);
  }

  void _renewSessionInBackground() {
    if (_disposed || _manuallyDisconnected || _accessToken == null) return;
    final generation = _sessionGeneration;
    unawaited(_refreshAccessToken().catchError((Object error) {
      _reportError(error);
      if (!_disposed &&
          !_manuallyDisconnected &&
          _accessToken != null &&
          generation == _sessionGeneration) {
        _refreshTimer?.cancel();
        _refreshTimer =
            Timer(const Duration(seconds: 5), _renewSessionInBackground);
      }
    }));
  }

  void _ensureV2() {
    if (!isV2) throw ChatException('This operation requires a v2 chat app.');
  }

  void _ensureRegistration() {
    if (isV2) {
      if (_accessToken == null) {
        throw ChatException('Not registered. Call register() first.');
      }
    } else {
      _ensureBrowserKey();
    }
  }

  void _ensureInitialized() {
    if (_disposed) throw ChatException('Chat has been disposed.');
    if (!_isInitialized) {
      throw ChatException('Chat not initialized. Call initialize() first.');
    }
  }

  void _ensureBrowserKey() {
    if (isV2) {
      throw ChatException('This operation is not exposed by the v2 API.');
    }
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
