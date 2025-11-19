import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Configuration class for FCRM Chat SDK
class ChatConfig {
  /// The base URL of your FCRM backend (e.g., https://api.yourcompany.com)
  final String baseUrl;

  /// The company/tenant token for tenant identification
  final String companyToken;

  /// The Chat App key provided in FCRM dashboard
  final String appKey;

  /// The Chat App secret provided in FCRM dashboard
  final String appSecret;

  /// Optional: Custom socket URL (if different from default)
  final String? socketUrl;

  /// Connection timeout in milliseconds
  final int connectionTimeout;

  /// Enable debug logging
  final bool enableLogging;

  ChatConfig({
    required this.baseUrl,
    required this.companyToken,
    required this.appKey,
    required this.appSecret,
    this.socketUrl,
    this.connectionTimeout = 20000,
    this.enableLogging = false,
  });

  /// Generate HMAC-SHA256 signature for API authentication
  String generateSignature() {
    final key = utf8.encode(appSecret);
    final bytes = utf8.encode(appKey);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }

  /// Get the API endpoint URL with company token
  String get apiUrl => '$baseUrl/api/v1/mobile-chat/$companyToken';

  /// Copy with new values
  ChatConfig copyWith({
    String? baseUrl,
    String? companyToken,
    String? appKey,
    String? appSecret,
    String? socketUrl,
    int? connectionTimeout,
    bool? enableLogging,
  }) {
    return ChatConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      companyToken: companyToken ?? this.companyToken,
      appKey: appKey ?? this.appKey,
      appSecret: appSecret ?? this.appSecret,
      socketUrl: socketUrl ?? this.socketUrl,
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      enableLogging: enableLogging ?? this.enableLogging,
    );
  }
}
