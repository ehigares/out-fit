class ReviewModel {
  const ReviewModel({
    required this.id,
    required this.eventId,
    required this.reviewerId,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.reviewerName,
  });

  final String id;
  final String eventId;
  final String reviewerId;
  final int rating; // 1–5
  final String? comment;
  final DateTime createdAt;

  // Joined from profiles — name only, no phone/email
  final String? reviewerName;

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return ReviewModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      reviewerId: json['reviewer_id'] as String,
      rating: (json['rating'] as num).toInt(),
      comment: json['comment'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewerName: profile?['full_name'] as String?,
    );
  }
}
