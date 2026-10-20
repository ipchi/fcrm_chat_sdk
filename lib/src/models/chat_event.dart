import 'dart:convert';

import 'message.dart';

/// A durable v2 change received live or replayed after a disconnection.
class ChatEvent {
  final int cursor;
  final String event;
  final String? eventId;
  final ChatMessage? message;
  final String? messageId;
  final int? throughSeq;
  final DateTime? createdAt;

  const ChatEvent({
    required this.cursor,
    required this.event,
    this.eventId,
    this.message,
    this.messageId,
    this.throughSeq,
    this.createdAt,
  });

  /// Both transports use the same data projection. Live events may include
  /// their event id inside data; replay responses include it in the envelope.
  factory ChatEvent.fromJson(dynamic json) {
    final envelope = _map(json);
    var payload = envelope;
    var cursor = _integer(envelope['cursor']);
    var eventId = (envelope['eventId'] ?? envelope['event_id'])?.toString();
    var event = (envelope['event'] ?? envelope['type'])?.toString();
    for (var depth = 0; depth < 8; depth++) {
      final nested = payload['data'];
      if (nested == null) break;
      payload = _map(nested);
      cursor ??= _integer(payload['cursor']);
      eventId ??= (payload['eventId'] ?? payload['event_id'])?.toString();
      event ??= (payload['event'] ?? payload['type'])?.toString();
    }
    final messageData =
        payload['message'] != null ? _map(payload['message']) : payload;
    final containsMessage = messageData.containsKey('content') ||
        messageData.containsKey('seq') ||
        messageData.containsKey('kind') ||
        messageData.containsKey('sender');
    final message = containsMessage ? ChatMessage.fromJson(messageData) : null;

    return ChatEvent(
      cursor: cursor ?? 0,
      event: event ?? 'message.created',
      eventId: eventId ??
          (messageData['eventId'] ?? messageData['event_id'])?.toString(),
      message: message,
      messageId: (envelope['messageId'] ??
              envelope['message_id'] ??
              payload['messageId'] ??
              payload['message_id'] ??
              message?.publicId)
          ?.toString(),
      throughSeq: _integer(envelope['throughSeq'] ??
          envelope['through_seq'] ??
          payload['throughSeq'] ??
          payload['through_seq']),
      createdAt: DateTime.tryParse((envelope['createdAt'] ??
                  envelope['created_at'] ??
                  payload['createdAt'] ??
                  payload['created_at'] ??
                  '')
              .toString()) ??
          message?.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'cursor': cursor,
        'eventId': eventId,
        'type': event,
        'createdAt': createdAt?.toIso8601String(),
        if (messageId != null) 'messageId': messageId,
        if (throughSeq != null) 'throughSeq': throughSeq,
        'data': message?.toJson() ??
            {
              if (messageId != null) 'messageId': messageId,
              if (throughSeq != null) 'throughSeq': throughSeq,
            },
      };
}

/// A v2 history page, ordered from the oldest to the newest message.
class ChatHistory {
  final List<ChatMessage> messages;
  final bool hasMore;

  const ChatHistory({required this.messages, required this.hasMore});

  factory ChatHistory.fromJson(Map<String, dynamic> json) => ChatHistory(
        messages: (json['messages'] as List? ?? [])
            .map((message) => ChatMessage.fromJson(_map(message)))
            .toList(),
        hasMore: json['hasMore'] == true || json['has_more'] == true,
      );

  /// Supply this cursor as `getHistory(before: ...)` to fetch an older page.
  int? get beforeSeq {
    int? oldest;
    for (final message in messages) {
      final seq = message.seq;
      if (seq != null && (oldest == null || seq < oldest)) oldest = seq;
    }
    return oldest;
  }

  Map<String, dynamic> toJson() => {
        'messages': messages.map((message) => message.toJson()).toList(),
        'hasMore': hasMore,
      };
}

/// A page of durable events used to recover after a socket disconnection.
class ChatEventPage {
  final List<ChatEvent> events;
  final int nextCursor;

  const ChatEventPage({required this.events, required this.nextCursor});

  factory ChatEventPage.fromJson(Map<String, dynamic> json) {
    final events =
        (json['events'] as List? ?? []).map(ChatEvent.fromJson).toList();
    return ChatEventPage(
      events: events,
      nextCursor: _integer(json['nextCursor'] ?? json['next_cursor']) ??
          events.fold<int>(0,
              (cursor, event) => event.cursor > cursor ? event.cursor : cursor),
    );
  }

  Map<String, dynamic> toJson() => {
        'events': events.map((event) => event.toJson()).toList(),
        'nextCursor': nextCursor,
      };
}

Map<String, dynamic> _map(dynamic value) {
  if (value is String) return _map(jsonDecode(value));
  if (value is Map) return Map<String, dynamic>.from(value);
  throw const FormatException('Expected a chat event object');
}

int? _integer(dynamic value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');
