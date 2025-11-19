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

  ChatAppRemoteConfig({
    required this.appName,
    this.appDescription,
    this.logoUrl,
    required this.isActive,
    required this.settings,
    required this.requiredFields,
    required this.socketUrl,
    required this.socketApiKey,
  });

  factory ChatAppRemoteConfig.fromJson(Map<String, dynamic> json) {
    return ChatAppRemoteConfig(
      appName: json['app_name'] ?? 'Chat',
      appDescription: json['app_description'],
      logoUrl: json['logo_url'],
      isActive: json['is_active'] ?? false,
      settings: Map<String, dynamic>.from(json['settings'] ?? {}),
      requiredFields: _parseRequiredFields(json['required_fields']),
      socketUrl: json['socket_url'] ?? '',
      socketApiKey: json['socket_api_key'] ?? '',
    );
  }

  static Map<String, String> _parseRequiredFields(dynamic fields) {
    if (fields == null) return {};
    if (fields is Map) {
      return Map<String, String>.from(
        fields.map((key, value) => MapEntry(key.toString(), value.toString())),
      );
    }
    return {};
  }

  /// Get start text from settings
  String get startText => settings['startText']?.toString() ?? '';

  /// Check if AI agent is enabled
  bool get isAiAgentEnabled => settings['ai_agent_enabled'] == true;

  /// Get message header color
  String get msHeaderColor => settings['ms_header_color']?.toString() ?? 'white';

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
    };
  }
}
