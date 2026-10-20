import 'dart:convert';

import 'package:fcrm_chat_sdk/fcrm_chat_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _v2Message({
  String kind = 'audio',
  String sender = 'agent',
  int seq = 42,
}) =>
    {
      'id': '01JPUBLICMESSAGE',
      'seq': seq,
      'clientMessageId': 'client-request-1',
      'sender': sender,
      'senderName': 'Operator',
      'kind': kind,
      'imageUrl': kind == 'image' ? 'https://chat.test/image.png' : null,
      'audioUrl': kind == 'audio' ? 'https://chat.test/audio.m4a' : null,
      'durationMs': kind == 'audio' ? 3250 : null,
      'content': kind == 'text' ? 'https://chat.test/image.png' : '',
      'edited': true,
      'read': true,
      'ratable': true,
      'rating': 4,
      'allowLinks': true,
      'createdAt': '2026-10-20T10:00:00Z',
    };

void main() {
  group('ChatMessage', () {
    test('preserves v2 audio, identity, rating and sender projection', () {
      final message = ChatMessage.fromJson(_v2Message());

      expect(message.id, 42);
      expect(message.seq, 42);
      expect(message.publicId, '01JPUBLICMESSAGE');
      expect(message.clientMessageId, 'client-request-1');
      expect(message.type, MessageType.admin);
      expect(message.senderName, 'Operator');
      expect(message.kind, MessageKind.audio);
      expect(message.audioUrl, 'https://chat.test/audio.m4a');
      expect(message.durationMs, 3250);
      expect(message.isAudio, isTrue);
      expect(message.isImage, isFalse);
      expect(message.isEdited, isTrue);
      expect(message.isRead, isTrue);
      expect(message.isRatable, isTrue);
      expect(message.ratingScore, 4);
      expect(message.rating, isNull);
      expect(message.allowLinks, isTrue);

      final restored = ChatMessage.fromJson(message.copyWith().toJson());
      expect(restored.toJson(), message.toJson());
    });

    test('v2 text URLs stay text and visitor maps to user', () {
      final message =
          ChatMessage.fromJson(_v2Message(kind: 'text', sender: 'visitor'));
      expect(message.type, MessageType.user);
      expect(message.isImage, isFalse);
      expect(message.isAudio, isFalse);
      expect(message.kind, MessageKind.text);

      final image = ChatMessage.fromJson(_v2Message(kind: 'image'));
      expect(image.isImage, isTrue);
      expect(image.imageUrl, 'https://chat.test/image.png');
    });

    test('legacy ids, metadata attachments and full ratings stay available',
        () {
      final message = ChatMessage.fromJson({
        'id': 7,
        'public_id': 'public-7',
        'chat_id': 3,
        'content': 'https://chat.test/storage/image.jpg',
        'type': 'admin',
        'created_at': '2026-10-19T08:00:00Z',
        'metadata': {
          'edited': true,
          'edited_at': '2026-10-20T08:00:00Z',
          'original_content': 'original',
        },
        'rating': {'rating': 5, 'comment': 'Helpful'},
      });
      expect(message.id, 7);
      expect(message.chatId, 3);
      expect(message.seq, isNull);
      expect(message.kind, isNull);
      expect(message.isImage, isTrue);
      expect(message.isEdited, isTrue);
      expect(message.editedAt, DateTime.utc(2026, 10, 20, 8));
      expect(message.originalContent, 'original');
      expect(message.rating!.comment, 'Helpful');
      expect(message.ratingScore, 5);
      expect(ChatMessage.fromJson(message.toJson()).toJson(), message.toJson());
    });

    test('handles numeric legacy strings and camelcase read timestamps', () {
      final message = ChatMessage.fromJson({
        'id': '8',
        'chatId': '3',
        'isRead': true,
        'readAt': '2026-10-20T08:00:00Z',
        'editedAt': '2026-10-20T08:01:00Z',
        'edited': true,
        'createdAt': '2026-10-20T08:00:00Z',
      });
      expect(message.id, 8);
      expect(message.publicId, isNull);
      expect(message.chatId, 3);
      expect(message.isRead, isTrue);
      expect(message.readAt, DateTime.utc(2026, 10, 20, 8));
      expect(message.editedAt, DateTime.utc(2026, 10, 20, 8, 1));
    });
  });

  test('SocketMessage accepts nested JSON-string envelopes', () {
    final socketMessage = SocketMessage.fromJson(jsonEncode({
      'event': 'message.created',
      'data': jsonEncode({'message': _v2Message()}),
    }));
    expect(socketMessage.event, 'message.created');
    expect(socketMessage.message.publicId, '01JPUBLICMESSAGE');
    expect(socketMessage.message.isAudio, isTrue);
    expect(() => SocketMessage.fromJson('bad JSON'), throwsFormatException);
  });

  group('ChatEvent', () {
    test('parses live inner ids and replay outer ids identically', () {
      final live = ChatEvent.fromJson({
        'cursor': 12,
        'event': 'message.created',
        'data': {..._v2Message(), 'eventId': 'event-12'},
      });
      final replay = ChatEvent.fromJson({
        'cursor': 12,
        'eventId': 'event-12',
        'type': 'message.created',
        'data': _v2Message(),
      });
      expect(live.eventId, 'event-12');
      expect(live.messageId, '01JPUBLICMESSAGE');
      expect(live.toJson(), replay.toJson());
      expect(ChatEvent.fromJson(live.toJson()).toJson(), live.toJson());
    });

    test('keeps read events without manufacturing a message', () {
      final event = ChatEvent.fromJson({
        'cursor': 13,
        'type': 'message.read',
        'eventId': 'event-13',
        'data': {'throughSeq': 42},
      });
      expect(event.message, isNull);
      expect(event.throughSeq, 42);
      expect(ChatEvent.fromJson(event.toJson()).throughSeq, 42);
    });

    test('event pages retain the recovery cursor', () {
      final page = ChatEventPage.fromJson({
        'events': [
          {'cursor': 12, 'type': 'message.created', 'data': _v2Message()},
        ],
        'nextCursor': 15,
      });
      expect(page.events.single.message!.isAudio, isTrue);
      expect(page.nextCursor, 15);
      expect(ChatEventPage.fromJson(page.toJson()).nextCursor, 15);
    });
  });

  test('history cursor is the oldest loaded message sequence', () {
    final history = ChatHistory.fromJson({
      'messages': [_v2Message(seq: 42), _v2Message(seq: 39)],
      'hasMore': true,
    });
    expect(history.beforeSeq, 39);
    expect(history.hasMore, isTrue);
    expect(const ChatHistory(messages: [], hasMore: false).beforeSeq, isNull);
  });

  test('send response keeps v2 message and acknowledgement flags', () {
    final response = SendMessageResponse.fromJson({
      'message': _v2Message(),
      'duplicate': true,
      'aiPending': true,
    });
    expect(response.success, isTrue);
    expect(response.userMessageId, 42);
    expect(response.message!.isAudio, isTrue);
    expect(response.duplicate, isTrue);
    expect(response.aiPending, isTrue);
  });

  test('remote config accepts PHP empty arrays and required field lists', () {
    final config = ChatAppRemoteConfig.fromJson({
      'settings': [],
      'required_fields': ['name', 'phone'],
      'v2': {
        'base_url': 'https://chat.test/',
        'app_key': 'app-1',
        'socket_namespace': '/v2',
        'socket_path': '/v2/socket.io',
      },
    });
    expect(config.settings, isEmpty);
    expect(config.requiredFields, {'name': 'name', 'phone': 'phone'});
    expect(config.isV2, isTrue);
    expect(config.v2!.baseUrl, 'https://chat.test');
    expect(config.v2!.socketNamespace, '/v2');
    expect(config.v2!.socketPath, '/v2/socket.io');
    expect(ChatAppRemoteConfig.fromJson(config.toJson()).toJson(),
        config.toJson());
    expect(
        ChatAppRemoteConfig.fromJson({
          'required_fields': {'email': 'Email'}
        }).requiredFields,
        {'email': 'Email'});
  });

  test('v2 negotiation defaults on and can be disabled in config copies', () {
    final config = ChatConfig(
      baseUrl: 'https://api.test///',
      companyToken: 'tenant',
      appKey: 'key',
      appSecret: 'secret',
    );
    expect(config.apiUrl, 'https://api.test/api/v1/mobile-chat/tenant');
    expect(config.enableV2, isTrue);
    expect(config.copyWith(enableV2: false).enableV2, isFalse);
  });

  test('v2 pagination adapters distinguish lower bounds from exact totals', () {
    final page = PaginatedMessages(
      messages: [],
      total: 20,
      currentPage: 1,
      perPage: 20,
      lastPage: 2,
      hasMore: true,
      hasExactTotal: false,
      nextBeforeSeq: 39,
    );
    final restored = PaginatedMessages.fromJson(page.toJson());
    expect(restored.hasExactTotal, isFalse);
    expect(restored.nextBeforeSeq, 39);
  });
}
