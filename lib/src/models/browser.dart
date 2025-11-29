/// Browser/Device registration model
class Browser {
  final String browserKey;
  final int? chatId;
  final Map<String, dynamic> userData;
  final List<dynamic>? lastMessages;

  Browser({
    required this.browserKey,
    this.chatId,
    required this.userData,
    this.lastMessages,
  });

  factory Browser.fromJson(Map<String, dynamic> json) {
    return Browser(
      browserKey: json['browser_key'] ?? '',
      chatId: json['chat_id'],
      userData: Map<String, dynamic>.from(json['user_data'] ?? {}),
      lastMessages: json['last_messages'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'browser_key': browserKey,
      'chat_id': chatId,
      'user_data': userData,
      'last_messages': lastMessages,
    };
  }
}

/// Registration response
class RegistrationResponse {
  final bool success;
  final String browserKey;
  final int? chatId;
  final String? message;
  final List<dynamic>? lastMessages;

  RegistrationResponse({
    required this.success,
    required this.browserKey,
    this.chatId,
    this.message,
    this.lastMessages,
  });

  factory RegistrationResponse.fromJson(Map<String, dynamic> json) {
    return RegistrationResponse(
      success: json['success'] ?? false,
      browserKey: json['browser_key'] ?? '',
      chatId: json['chat_id'],
      message: json['message'],
      lastMessages: json['last_messages'],
    );
  }
}

/// Send message response
class SendMessageResponse {
  final bool success;
  final int userMessageId;
  final int chatId;
  final bool aiAgentEnabled;
  final Map<String, dynamic>? aiMessage;

  SendMessageResponse({
    required this.success,
    required this.userMessageId,
    required this.chatId,
    required this.aiAgentEnabled,
    this.aiMessage,
  });

  factory SendMessageResponse.fromJson(Map<String, dynamic> json) {
    return SendMessageResponse(
      success: json['success'] ?? false,
      userMessageId: json['user_message_id'] ?? 0,
      chatId: json['chat_id'] ?? 0,
      aiAgentEnabled: json['ai_agent_enabled'] ?? false,
      aiMessage: json['ai_message'],
    );
  }
}

/// Update user data response
class UpdateUserDataResponse {
  final bool success;
  final Map<String, dynamic> userData;
  final String? message;

  UpdateUserDataResponse({
    required this.success,
    required this.userData,
    this.message,
  });

  factory UpdateUserDataResponse.fromJson(Map<String, dynamic> json) {
    return UpdateUserDataResponse(
      success: json['success'] ?? false,
      userData: Map<String, dynamic>.from(json['user_data'] ?? {}),
      message: json['message'],
    );
  }
}

/// Edit message response
class EditMessageResponse {
  final bool success;
  final int messageId;
  final String content;
  final bool edited;
  final String? editedAt;

  EditMessageResponse({
    required this.success,
    required this.messageId,
    required this.content,
    required this.edited,
    this.editedAt,
  });

  factory EditMessageResponse.fromJson(Map<String, dynamic> json) {
    final message = json['message'] as Map<String, dynamic>?;
    return EditMessageResponse(
      success: json['success'] ?? false,
      messageId: message?['id'] ?? 0,
      content: message?['content'] ?? '',
      edited: message?['edited'] ?? false,
      editedAt: message?['edited_at'],
    );
  }
}
