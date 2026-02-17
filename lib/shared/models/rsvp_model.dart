class RsvpModel {
  const RsvpModel({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.status,
    required this.createdAt,
    this.fullName,
    this.email,
    // phone_private intentionally excluded from joins — never expose to non-admins
  });

  final String id;
  final String eventId;
  final String userId;
  final String status;
  final DateTime createdAt;

  // Joined from profiles (host/admin view only)
  final String? fullName;
  final String? email; // only visible to admin

  bool get isGoing => status == 'going';

  factory RsvpModel.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return RsvpModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      userId: json['user_id'] as String,
      status: json['status'] as String? ?? 'going',
      createdAt: DateTime.parse(json['created_at'] as String),
      fullName: profile?['full_name'] as String?,
      email: profile?['email'] as String?,
    );
  }
}
