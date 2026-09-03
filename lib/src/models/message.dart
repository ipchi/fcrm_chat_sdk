import 'message_rating.dart';

/// Message model for chat messages
class ChatMessage {
  final int id;

  /// Opaque public identifier; used to address the message when rating it.
  final String? publicId;

  final int chatId;
  final String content;
  final MessageType type;
  final String? senderName;
  final String? senderType;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isRead;
  final DateTime? readAt;
  final Map<String, dynamic>? metadata;

  /// Whether the current client may rate this message.
  final bool isRatable;

  /// This client's own rating, if it has left one.
  final MessageRating? rating;

  ChatMessage({
    required this.id,
    this.publicId,
    required this.chatId,
    required this.content,
    required this.type,
    this.senderName,
    this.senderType,
    required this.createdAt,
    this.updatedAt,
    this.isRead = false,
    this.readAt,
    this.metadata,
    this.isRatable = false,
    this.rating,
  });

  /// Create from JSON
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] ?? 0,
      publicId: json['public_id'],
      chatId: json['chat_id'] ?? 0,
      content: json['content'] ?? '',
      type: MessageType.fromString(json['type'] ?? 'user'),
      senderName: json['sender_name'],
      senderType: json['sender_type'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      isRead: json['is_read'] ?? false,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'])
          : null,
      metadata: json['metadata'] is Map<String, dynamic> ? json['metadata'] : null,
      isRatable: json['is_ratable'] ?? false,
      rating: json['rating'] is Map<String, dynamic>
          ? MessageRating.fromJson(json['rating'])
          : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'public_id': publicId,
      'chat_id': chatId,
      'content': content,
      'type': type.value,
      'sender_name': senderName,
      'sender_type': senderType,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_read': isRead,
      'read_at': readAt?.toIso8601String(),
      'metadata': metadata,
      'is_ratable': isRatable,
      'rating': rating?.toJson(),
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

  /// Check if message has been edited
  bool get isEdited => metadata?['edited'] == true;

  /// Get the edited timestamp (if edited)
  DateTime? get editedAt {
    final editedAtStr = metadata?['edited_at'];
    if (editedAtStr != null) {
      return DateTime.tryParse(editedAtStr);
    }
    return null;
  }

  /// Get the original content before editing (if edited)
  String? get originalContent => metadata?['original_content'];

  /// Check if message can be edited (within 24 hours)
  bool get canEdit {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    return diff.inHours < 24;
  }

  /// Copy with new values
  ChatMessage copyWith({
    int? id,
    String? publicId,
    int? chatId,
    String? content,
    MessageType? type,
    String? senderName,
    String? senderType,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isRead,
    DateTime? readAt,
    Map<String, dynamic>? metadata,
    bool? isRatable,
    MessageRating? rating,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      publicId: publicId ?? this.publicId,
      chatId: chatId ?? this.chatId,
      content: content ?? this.content,
      type: type ?? this.type,
      senderName: senderName ?? this.senderName,
      senderType: senderType ?? this.senderType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      metadata: metadata ?? this.metadata,
      isRatable: isRatable ?? this.isRatable,
      rating: rating ?? this.rating,
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
