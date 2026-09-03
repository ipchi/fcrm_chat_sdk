/// A client's 1-5 star rating of an admin answer, with an optional comment.
///
/// The comment is always optional: a rating of any value may carry none.
class MessageRating {
  /// Star value, 1 through 5.
  final int rating;

  /// Optional free-text comment, or null when the client left none.
  final String? comment;

  final DateTime? updatedAt;

  /// Opaque public message id. Present on the standalone rating endpoints,
  /// absent when the rating is embedded in a message payload.
  final String? messageId;

  const MessageRating({
    required this.rating,
    this.comment,
    this.updatedAt,
    this.messageId,
  });

  factory MessageRating.fromJson(Map<String, dynamic> json) {
    return MessageRating(
      rating: json['rating'] is int
          ? json['rating']
          : int.tryParse('${json['rating']}') ?? 0,
      comment: json['comment'],
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
      messageId: json['messageId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rating': rating,
      'comment': comment,
      'updatedAt': updatedAt?.toIso8601String(),
      'messageId': messageId,
    };
  }

  /// Whether the client attached a non-empty comment.
  bool get hasComment => comment != null && comment!.trim().isNotEmpty;

  /// English label for the value. Localise in the host app if needed.
  String get label {
    switch (rating) {
      case 1:
        return 'Very poor';
      case 2:
        return 'Poor';
      case 3:
        return 'Average';
      case 4:
        return 'Good';
      case 5:
        return 'Excellent';
      default:
        return 'Unknown';
    }
  }

  MessageRating copyWith({
    int? rating,
    String? comment,
    DateTime? updatedAt,
    String? messageId,
  }) {
    return MessageRating(
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      updatedAt: updatedAt ?? this.updatedAt,
      messageId: messageId ?? this.messageId,
    );
  }
}
