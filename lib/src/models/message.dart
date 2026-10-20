import 'dart:convert';

import 'message_rating.dart';

/// Message model shared by the legacy and v2 chat transports.
class ChatMessage {
  /// Legacy numeric id, or the v2 sequence number.
  final int id;

  /// Opaque identifier used by v2 and the message rating endpoints.
  final String? publicId;
  final int? seq;
  final String? clientMessageId;
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

  /// Attachment type supplied by v2. Null for a legacy message.
  final MessageKind? kind;
  final String? imageUrl;
  final String? audioUrl;
  final int? durationMs;
  final bool allowLinks;

  /// Whether the current client may rate this message.
  final bool isRatable;

  /// The full legacy rating, including its optional comment.
  final MessageRating? rating;
  final int? _ratingScore;
  final bool? _edited;
  final DateTime? _editedAt;

  ChatMessage({
    required this.id,
    this.publicId,
    this.seq,
    this.clientMessageId,
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
    this.kind,
    this.imageUrl,
    this.audioUrl,
    this.durationMs,
    this.allowLinks = false,
    this.isRatable = false,
    this.rating,
    int? ratingScore,
    bool? edited,
    DateTime? editedAt,
  })  : _ratingScore = ratingScore,
        _edited = edited,
        _editedAt = editedAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final seq = _integer(json['seq']);
    final rawId = json['id'];
    final isV2 =
        json.containsKey('kind') || json.containsKey('sender') || seq != null;
    final metadata = json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'])
        : null;
    final rawRating = json['rating'];
    final rating = rawRating is Map
        ? MessageRating.fromJson(Map<String, dynamic>.from(rawRating))
        : null;

    return ChatMessage(
      id: rawId is int ? rawId : seq ?? _integer(rawId) ?? 0,
      publicId: (json['public_id'] ??
              json['publicId'] ??
              (rawId is String && (isV2 || _integer(rawId) == null)
                  ? rawId
                  : null))
          ?.toString(),
      seq: seq,
      clientMessageId:
          (json['clientMessageId'] ?? json['client_message_id'])?.toString(),
      chatId: _integer(json['chat_id'] ?? json['chatId']) ?? 0,
      content: json['content']?.toString() ?? '',
      type: MessageType.fromString(
          (json['sender'] ?? json['type'] ?? 'user').toString()),
      senderName: (json['senderName'] ?? json['sender_name'])?.toString(),
      senderType: (json['senderType'] ?? json['sender_type'])?.toString(),
      createdAt:
          _date(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      updatedAt: _date(json['updatedAt'] ?? json['updated_at']),
      isRead: _boolean(json['read'] ?? json['isRead'] ?? json['is_read']),
      readAt: _date(json['readAt'] ?? json['read_at']),
      metadata: metadata,
      kind: isV2
          ? MessageKind.fromString(json['kind']?.toString() ?? 'text')
          : null,
      imageUrl: (json['imageUrl'] ?? json['image_url'])?.toString(),
      audioUrl: (json['audioUrl'] ?? json['audio_url'])?.toString(),
      durationMs: _integer(json['durationMs'] ?? json['duration_ms']),
      allowLinks: _boolean(json['allowLinks'] ?? json['allow_links']),
      isRatable:
          _boolean(json['ratable'] ?? json['isRatable'] ?? json['is_ratable']),
      rating: rating,
      ratingScore: _integer(json['ratingScore'] ??
          json['rating_score'] ??
          (rawRating is Map ? rawRating['rating'] : rawRating)),
      edited: json.containsKey('edited') ? _boolean(json['edited']) : null,
      editedAt: _date(json['editedAt'] ?? json['edited_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'public_id': publicId,
        'seq': seq,
        'clientMessageId': clientMessageId,
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
        if (kind != null) 'kind': kind!.value,
        'imageUrl': imageUrl,
        'audioUrl': audioUrl,
        'durationMs': durationMs,
        'allowLinks': allowLinks,
        'is_ratable': isRatable,
        'rating': rating?.toJson() ?? ratingScore,
        'edited': isEdited,
        'editedAt': editedAt?.toIso8601String(),
      };

  /// V2 attachments are typed; text containing a URL remains text.
  bool get isImage => kind != null
      ? kind == MessageKind.image
      : metadata?['is_image'] == true || _isImageUrl(content);

  bool get isAudio =>
      kind != null ? kind == MessageKind.audio : metadata?['is_audio'] == true;

  int? get ratingScore => _ratingScore ?? rating?.rating;

  bool _isImageUrl(String content) {
    final lowerContent = content.toLowerCase();
    final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];
    return imageExtensions.any((ext) => lowerContent.contains(ext)) &&
        (lowerContent.contains('/storage/') || lowerContent.startsWith('http'));
  }

  bool get isEdited => _edited ?? _boolean(metadata?['edited']);

  DateTime? get editedAt =>
      _editedAt ?? _date(metadata?['editedAt'] ?? metadata?['edited_at']);

  String? get originalContent =>
      (metadata?['originalContent'] ?? metadata?['original_content'])
          ?.toString();

  /// The v2 public API currently does not expose message editing.
  bool get canEdit =>
      kind == null && DateTime.now().difference(createdAt).inHours < 24;

  ChatMessage copyWith({
    int? id,
    String? publicId,
    int? seq,
    String? clientMessageId,
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
    MessageKind? kind,
    String? imageUrl,
    String? audioUrl,
    int? durationMs,
    bool? allowLinks,
    bool? isRatable,
    MessageRating? rating,
    int? ratingScore,
    bool? edited,
    DateTime? editedAt,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        publicId: publicId ?? this.publicId,
        seq: seq ?? this.seq,
        clientMessageId: clientMessageId ?? this.clientMessageId,
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
        kind: kind ?? this.kind,
        imageUrl: imageUrl ?? this.imageUrl,
        audioUrl: audioUrl ?? this.audioUrl,
        durationMs: durationMs ?? this.durationMs,
        allowLinks: allowLinks ?? this.allowLinks,
        isRatable: isRatable ?? this.isRatable,
        rating: rating ?? this.rating,
        ratingScore:
            ratingScore ?? (rating != null ? rating.rating : _ratingScore),
        edited: edited ?? _edited,
        editedAt: editedAt ?? _editedAt,
      );
}

enum MessageKind {
  text('text'),
  image('image'),
  audio('audio');

  const MessageKind(this.value);
  final String value;

  static MessageKind fromString(String value) => MessageKind.values.firstWhere(
        (kind) => kind.value == value.toLowerCase(),
        orElse: () => MessageKind.text,
      );
}

enum MessageType {
  user('user'),
  admin('admin'),
  ai('ai'),
  system('system');

  const MessageType(this.value);
  final String value;

  static MessageType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'visitor':
      case 'user':
        return MessageType.user;
      case 'agent':
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

/// Legacy socket wrapper, also accepting the v2 data envelope.
class SocketMessage {
  final String? event;
  final ChatMessage message;

  SocketMessage({this.event, required this.message});

  factory SocketMessage.fromJson(dynamic json) {
    var payload = _socketMap(json);
    String? event;
    for (var depth = 0; depth < 8; depth++) {
      event ??= (payload['event'] ??
              (payload.containsKey('data') ? payload['type'] : null))
          ?.toString();
      final nested = payload['message'] ?? payload['data'];
      if (nested == null) break;
      payload = _socketMap(nested);
    }
    return SocketMessage(
      event: event,
      message: ChatMessage.fromJson(payload),
    );
  }
}

Map<String, dynamic> _socketMap(dynamic value) {
  if (value is String) {
    try {
      return _socketMap(jsonDecode(value));
    } on FormatException {
      throw const FormatException('Invalid chat socket JSON');
    }
  }
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty) return _socketMap(value.last);
  throw const FormatException('Expected a chat socket message object');
}

int? _integer(dynamic value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');

bool _boolean(dynamic value) => value == true || value == 1 || value == 'true';

DateTime? _date(dynamic value) =>
    value is DateTime ? value : DateTime.tryParse(value?.toString() ?? '');
