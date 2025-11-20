/// Message model for chat messages
class ChatMessage {
  final int id;
  final int chatId;
  final String content;
  final MessageType type;
  final String? senderName;
  final String? senderType;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.content,
    required this.type,
    this.senderName,
    this.senderType,
    required this.createdAt,
    this.metadata,
  });

  /// Create from JSON
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] ?? 0,
      chatId: json['chat_id'] ?? 0,
      content: json['content'] ?? '',
      type: MessageType.fromString(json['type'] ?? 'user'),
      senderName: json['sender_name'],
      senderType: json['sender_type'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      metadata: json['metadata'] is Map<String, dynamic> ? json['metadata'] : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chat_id': chatId,
      'content': content,
      'type': type.value,
      'sender_name': senderName,
      'sender_type': senderType,
      'created_at': createdAt.toIso8601String(),
      'metadata': metadata,
    };
  }

  /// Check if message is an image
  bool get isImage =>
      metadata?['is_image'] == true ||
      _isImageUrl(content);

  bool _isImageUrl(String content) {
    final lowerContent = content.toLowerCase();
    final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];
    return imageExtensions.any((ext) => lowerContent.contains(ext)) &&
        (lowerContent.contains('/storage/') || lowerContent.startsWith('http'));
  }

  /// Copy with new values
  ChatMessage copyWith({
    int? id,
    int? chatId,
    String? content,
    MessageType? type,
    String? senderName,
    String? senderType,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      content: content ?? this.content,
      type: type ?? this.type,
      senderName: senderName ?? this.senderName,
      senderType: senderType ?? this.senderType,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Message type enum
enum MessageType {
  user('user'),
  admin('admin'),
  ai('ai'),
  system('system');

  const MessageType(this.value);
  final String value;

  static MessageType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'user':
        return MessageType.user;
      case 'admin':
        return MessageType.admin;
      case 'ai':
        return MessageType.ai;
      case 'system':
        return MessageType.system;
      default:
        return MessageType.user;
    }
  }
}

/// Socket message wrapper
class SocketMessage {
  final String? event;
  final ChatMessage message;

  SocketMessage({
    this.event,
    required this.message,
  });

  factory SocketMessage.fromJson(Map<String, dynamic> json) {
    return SocketMessage(
      event: json['event'],
      message: ChatMessage.fromJson(json['message'] ?? json),
    );
  }
}
