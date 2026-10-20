import 'message.dart';

/// Paginated messages response
class PaginatedMessages {
  final List<ChatMessage> messages;
  final int total;
  final int currentPage;
  final int perPage;
  final int lastPage;
  final bool hasMore;

  /// False when adapting v2 cursor pages, which do not report a total count.
  final bool hasExactTotal;
  final int? nextBeforeSeq;

  PaginatedMessages({
    required this.messages,
    required this.total,
    required this.currentPage,
    required this.perPage,
    required this.lastPage,
    required this.hasMore,
    this.hasExactTotal = true,
    this.nextBeforeSeq,
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
      hasExactTotal: pagination['has_exact_total'] ?? true,
      nextBeforeSeq: pagination['next_before_seq'],
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
        'has_exact_total': hasExactTotal,
        'next_before_seq': nextBeforeSeq,
      },
    };
  }
}
