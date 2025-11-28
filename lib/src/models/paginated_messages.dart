import 'message.dart';

/// Paginated messages response
class PaginatedMessages {
  final List<ChatMessage> messages;
  final int total;
  final int currentPage;
  final int perPage;
  final int lastPage;
  final bool hasMore;

  PaginatedMessages({
    required this.messages,
    required this.total,
    required this.currentPage,
    required this.perPage,
    required this.lastPage,
    required this.hasMore,
  });

  factory PaginatedMessages.fromJson(Map<String, dynamic> json) {
    final messagesData = json['messages'] as List? ?? [];
    final messages = messagesData
        .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
        .toList();

    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};

    return PaginatedMessages(
      messages: messages,
      total: pagination['total'] ?? messages.length,
      currentPage: pagination['current_page'] ?? 1,
      perPage: pagination['per_page'] ?? messages.length,
      lastPage: pagination['last_page'] ?? 1,
      hasMore: pagination['has_more'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messages': messages.map((m) => m.toJson()).toList(),
      'pagination': {
        'total': total,
        'current_page': currentPage,
        'per_page': perPage,
        'last_page': lastPage,
        'has_more': hasMore,
      },
    };
  }
}
