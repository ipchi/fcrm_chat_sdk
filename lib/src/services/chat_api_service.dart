import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../config/chat_config.dart';
import '../models/chat_app_config.dart';
import '../models/browser.dart';
import '../models/paginated_messages.dart';

/// Callback for tracking upload progress
/// [sent] - bytes sent so far
/// [total] - total bytes to send
typedef SendProgressCallback = void Function(int sent, int total);

/// Token for cancelling upload operations
class CancelToken {
  bool _isCancelled = false;
  final _completer = Completer<void>();

  /// Whether this token has been cancelled
  bool get isCancelled => _isCancelled;

  /// Future that completes when cancelled
  Future<void> get whenCancelled => _completer.future;

  /// Cancel the operation
  void cancel() {
    if (!_isCancelled) {
      _isCancelled = true;
      _completer.complete();
    }
  }
}

/// Exception thrown when an upload is cancelled
class UploadCancelledException implements Exception {
  final String message;
  UploadCancelledException([this.message = 'Upload was cancelled']);

  @override
  String toString() => 'UploadCancelledException: $message';
}

/// API service for FCRM Chat
class ChatApiService {
  final ChatConfig config;
  final http.Client _client;

  ChatApiService({
    required this.config,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Log message if logging is enabled
  void _log(String message) {
    if (config.enableLogging) {
      print('[FCRM Chat] $message');
    }
  }

  /// Get default headers with signature
  Map<String, String> _getHeaders({bool isJson = true}) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Chat-Signature': config.generateSignature(),
      'X-Chat-App-Key': config.appKey,
    };
    if (isJson) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  /// Get chat app configuration
  Future<ChatAppRemoteConfig> getConfig() async {
    final signature = config.generateSignature();
    final url = Uri.parse('${config.apiUrl}/config')
        .replace(queryParameters: {
      'key': config.appKey,
      'sig': signature,
    });

    _log('Getting config from: $url');

    final response = await _client.get(
      url,
      headers: {'Accept': 'application/json'},
    ).timeout(Duration(milliseconds: config.connectionTimeout));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _log('Config received: ${data['app_name']}');
      return ChatAppRemoteConfig.fromJson(data);
    } else {
      final error = _parseError(response);
      _log('Config error: $error');
      throw ChatApiException(error, response.statusCode);
    }
  }

  /// Register a new browser/device
  Future<RegistrationResponse> registerBrowser({
    required Map<String, dynamic> userData,
    String? endpoint,
  }) async {
    final url = Uri.parse('${config.apiUrl}/register-browser');

    _log('Registering browser');

    final response = await _client.post(
      url,
      headers: _getHeaders(),
      body: jsonEncode({
        'chat_app_key': config.appKey,
        'user_data': userData,
        'endpoint': endpoint,
      }),
    ).timeout(Duration(milliseconds: config.connectionTimeout));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _log('Browser registered: ${data['browser_key']}');
      return RegistrationResponse.fromJson(data);
    } else {
      final error = _parseError(response);
      _log('Registration error: $error');
      throw ChatApiException(error, response.statusCode);
    }
  }

  /// Update browser/device information
  Future<RegistrationResponse> updateBrowser({
    required String browserKey,
    required Map<String, dynamic> userData,
  }) async {
    final url = Uri.parse('${config.apiUrl}/browser/update');

    _log('Updating browser: $browserKey');

    final response = await _client.post(
      url,
      headers: _getHeaders(),
      body: jsonEncode({
        'chat_app_key': config.appKey,
        'browser_key': browserKey,
        'user_data': userData,
      }),
    ).timeout(Duration(milliseconds: config.connectionTimeout));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _log('Browser updated');
      return RegistrationResponse.fromJson(data);
    } else {
      final error = _parseError(response);
      _log('Update error: $error');
      throw ChatApiException(error, response.statusCode);
    }
  }

  /// Update specific user data fields (partial update)
  ///
  /// Only updates the fields provided, preserves other existing data
  Future<UpdateUserDataResponse> updateUserData({
    required String browserKey,
    required Map<String, dynamic> data,
  }) async {
    final url = Uri.parse('${config.apiUrl}/browser/update-data');

    _log('Updating user data for browser: $browserKey');

    final response = await _client.post(
      url,
      headers: _getHeaders(),
      body: jsonEncode({
        'chat_app_key': config.appKey,
        'browser_key': browserKey,
        'data': data,
      }),
    ).timeout(Duration(milliseconds: config.connectionTimeout));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _log('User data updated');
      return UpdateUserDataResponse.fromJson(data);
    } else {
      final error = _parseError(response);
      _log('Update user data error: $error');
      throw ChatApiException(error, response.statusCode);
    }
  }

  /// Send a message
  Future<SendMessageResponse> sendMessage({
    required String browserKey,
    required String message,
    String? endpoint,
    Map<String, dynamic>? metadata,
  }) async {
    final url = Uri.parse('${config.apiUrl}/send-message');

    _log('Sending message');

    final Map<String, dynamic> body = {
      'chat_app_key': config.appKey,
      'browser_key': browserKey,
      'message': message,
      'endpoint': endpoint,
    };

    if (metadata != null && metadata.isNotEmpty) {
      body['metadata'] = metadata;
    }

    final response = await _client.post(
      url,
      headers: _getHeaders(),
      body: jsonEncode(body),
    ).timeout(Duration(milliseconds: config.connectionTimeout));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _log('Message sent: ${data['user_message_id']}');
      return SendMessageResponse.fromJson(data);
    } else {
      final error = _parseError(response);
      _log('Send error: $error');
      throw ChatApiException(error, response.statusCode);
    }
  }

  /// Edit a message (only allowed within 1 day of creation)
  ///
  /// [browserKey] - The browser key for authentication
  /// [messageId] - The ID of the message to edit
  /// [content] - The new content for the message
  Future<EditMessageResponse> editMessage({
    required String browserKey,
    required int messageId,
    required String content,
  }) async {
    final url = Uri.parse('${config.apiUrl}/edit-message');

    _log('Editing message: $messageId');

    final response = await _client.post(
      url,
      headers: _getHeaders(),
      body: jsonEncode({
        'chat_app_key': config.appKey,
        'browser_key': browserKey,
        'message_id': messageId,
        'content': content,
      }),
    ).timeout(Duration(milliseconds: config.connectionTimeout));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _log('Message edited: $messageId');
      return EditMessageResponse.fromJson(data);
    } else {
      final error = _parseError(response);
      _log('Edit error: $error');
      throw ChatApiException(error, response.statusCode);
    }
  }

  /// Get chat messages with pagination
  Future<PaginatedMessages> getMessages({
    required String browserKey,
    int page = 1,
    int perPage = 20,
  }) async {
    final url = Uri.parse('${config.apiUrl}/messages');

    _log('Getting messages (page: $page, perPage: $perPage)');

    final response = await _client.post(
      url,
      headers: _getHeaders(),
      body: jsonEncode({
        'chat_app_key': config.appKey,
        'browser_key': browserKey,
        'page': page,
        'per_page': perPage,
      }),
    ).timeout(Duration(milliseconds: config.connectionTimeout));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final paginatedMessages = PaginatedMessages.fromJson(data);
      _log('Received ${paginatedMessages.messages.length} messages (page ${paginatedMessages.currentPage}/${paginatedMessages.lastPage})');
      return paginatedMessages;
    } else {
      final error = _parseError(response);
      _log('Messages error: $error');
      throw ChatApiException(error, response.statusCode);
    }
  }

  /// Upload an image
  ///
  /// [browserKey] - The browser key for authentication
  /// [imageFile] - The image file to upload
  /// [endpoint] - Optional endpoint/screen name
  /// [onSendProgress] - Optional callback for tracking upload progress
  /// [cancelToken] - Optional token to cancel the upload
  Future<Map<String, dynamic>> uploadImage({
    required String browserKey,
    required File imageFile,
    String? endpoint,
    SendProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final url = Uri.parse('${config.apiUrl}/upload-image');

    _log('Uploading image: ${imageFile.path}');

    // Check if already cancelled
    if (cancelToken?.isCancelled == true) {
      throw UploadCancelledException();
    }

    final request = http.MultipartRequest('POST', url);

    // Add signature headers
    request.headers.addAll(_getHeaders(isJson: false));

    request.fields['chat_app_key'] = config.appKey;
    request.fields['browser_key'] = browserKey;
    if (endpoint != null) {
      request.fields['endpoint'] = endpoint;
    }

    final fileName = path.basename(imageFile.path);

    request.files.add(
      await http.MultipartFile.fromPath(
        'image',
        imageFile.path,
        filename: fileName,
      ),
    );

    http.StreamedResponse streamedResponse;
    StreamSubscription<List<int>>? uploadSubscription;

    try {
      final totalBytes = request.contentLength;
      var sentBytes = 0;

      final originalStream = request.finalize();
      final progressRequest = http.StreamedRequest('POST', url);
      progressRequest.headers.addAll(request.headers);
      progressRequest.contentLength = totalBytes;

      // Set up cancellation listener
      if (cancelToken != null) {
        cancelToken.whenCancelled.then((_) {
          uploadSubscription?.cancel();
          progressRequest.sink.close();
        });
      }

      final progressStream = originalStream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            if (cancelToken?.isCancelled == true) {
              sink.close();
              return;
            }
            sentBytes += data.length;
            onSendProgress?.call(sentBytes, totalBytes);
            sink.add(data);
          },
        ),
      );

      uploadSubscription = progressStream.listen(
        progressRequest.sink.add,
        onError: progressRequest.sink.addError,
        onDone: progressRequest.sink.close,
      );

      // Race between upload and cancellation
      if (cancelToken != null) {
        final result = await Future.any([
          progressRequest.send(),
          cancelToken.whenCancelled.then((_) => throw UploadCancelledException()),
        ]);
        streamedResponse = result as http.StreamedResponse;
      } else {
        streamedResponse = await progressRequest.send()
            .timeout(Duration(milliseconds: config.connectionTimeout));
      }

      // Check if cancelled during upload
      if (cancelToken?.isCancelled == true) {
        throw UploadCancelledException();
      }

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _log('Image uploaded: ${data['image_url']}');
        return data;
      } else {
        final error = _parseError(response);
        _log('Upload error: $error');
        throw ChatApiException(error, response.statusCode);
      }
    } catch (e) {
      if (e is UploadCancelledException) {
        _log('Upload cancelled');
        rethrow;
      }
      rethrow;
    } finally {
      await uploadSubscription?.cancel();
    }
  }

  /// Upload a file
  ///
  /// [browserKey] - The browser key for authentication
  /// [file] - The file to upload
  /// [endpoint] - Optional endpoint/screen name
  /// [onSendProgress] - Optional callback for tracking upload progress
  /// [cancelToken] - Optional token to cancel the upload
  Future<Map<String, dynamic>> uploadFile({
    required String browserKey,
    required File file,
    String? endpoint,
    SendProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    // For now, use the same endpoint as image upload
    // Backend can be extended to support generic file uploads
    return uploadImage(
      browserKey: browserKey,
      imageFile: file,
      endpoint: endpoint,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  /// Parse error from response
  String _parseError(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data['error'] != null) {
        return data['error'].toString();
      }
      if (data['errors'] != null) {
        final errors = data['errors'] as Map<String, dynamic>;
        return errors.values.expand((e) => e as List).join(', ');
      }
      if (data['message'] != null) {
        return data['message'].toString();
      }
    } catch (_) {}
    return 'Request failed with status ${response.statusCode}';
  }

  /// Dispose the client
  void dispose() {
    _client.close();
  }
}

/// API exception
class ChatApiException implements Exception {
  final String message;
  final int statusCode;

  ChatApiException(this.message, this.statusCode);

  @override
  String toString() => 'ChatApiException: $message (status: $statusCode)';
}
