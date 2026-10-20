/// Chat App configuration received from server
class ChatAppRemoteConfig {
  final String appName;
  final String? appDescription;
  final String? logoUrl;
  final bool isActive;
  final Map<String, dynamic> settings;
  final Map<String, String> requiredFields;
  final String socketUrl;
  final String socketApiKey;
  final ChatV2Config? v2;

  ChatAppRemoteConfig({
    required this.appName,
    this.appDescription,
    this.logoUrl,
    required this.isActive,
    required this.settings,
    required this.requiredFields,
    required this.socketUrl,
    required this.socketApiKey,
    this.v2,
  });

  factory ChatAppRemoteConfig.fromJson(Map<String, dynamic> json) {
    return ChatAppRemoteConfig(
      appName: json['app_name'] ?? 'Chat',
      appDescription: json['app_description'],
      logoUrl: json['logo_url'],
      isActive: json['is_active'] ?? false,
      settings: json['settings'] is Map
          ? Map<String, dynamic>.from(json['settings'])
          : {},
      requiredFields: _parseRequiredFields(json['required_fields']),
      socketUrl: json['socket_url'] ?? '',
      socketApiKey: json['socket_api_key'] ?? '',
      v2: json['v2'] is Map
          ? ChatV2Config.fromJson(Map<String, dynamic>.from(json['v2']))
          : null,
    );
  }

  static Map<String, String> _parseRequiredFields(dynamic fields) {
    if (fields == null) return {};
    if (fields is Map) {
      return Map<String, String>.from(
        fields.map((key, value) => MapEntry(key.toString(), value.toString())),
      );
    }
    if (fields is List) {
      return {
        for (final field in fields.whereType<String>()) field: field,
      };
    }
    return {};
  }

  /// Get start text from settings
  String get startText => settings['startText']?.toString() ?? '';

  /// Check if AI agent is enabled
  bool get isAiAgentEnabled => settings['ai_agent_enabled'] == true;

  /// Whether this app advertises the v2 chat transport.
  bool get isV2 => v2 != null;

  /// Get message header color
  String get msHeaderColor =>
      settings['ms_header_color']?.toString() ?? 'white';

  /// Get message name color
  String get msNameColor => settings['ms_name_color']?.toString() ?? 'darkred';

  Map<String, dynamic> toJson() {
    return {
      'app_name': appName,
      'app_description': appDescription,
      'logo_url': logoUrl,
      'is_active': isActive,
      'settings': settings,
      'required_fields': requiredFields,
      'socket_url': socketUrl,
      'socket_api_key': socketApiKey,
      if (v2 != null) 'v2': v2!.toJson(),
    };
  }
}

/// Public endpoints advertised by a v2 chat app.
class ChatV2Config {
  final String baseUrl;
  final String socketNamespace;
  final String socketPath;
  final String appKey;

  ChatV2Config({
    required String baseUrl,
    this.socketNamespace = '/v2',
    this.socketPath = '/v2/socket.io',
    required this.appKey,
  }) : baseUrl = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');

  factory ChatV2Config.fromJson(Map<String, dynamic> json) => ChatV2Config(
        baseUrl: (json['base_url'] ?? json['baseUrl'] ?? '').toString(),
        socketNamespace:
            (json['socket_namespace'] ?? json['socketNamespace'] ?? '/v2')
                .toString(),
        socketPath:
            (json['socket_path'] ?? json['socketPath'] ?? '/v2/socket.io')
                .toString(),
        appKey: (json['app_key'] ?? json['appKey'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'base_url': baseUrl,
        'socket_namespace': socketNamespace,
        'socket_path': socketPath,
        'app_key': appKey,
      };
}
