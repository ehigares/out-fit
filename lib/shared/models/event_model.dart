class EventModel {
  const EventModel({
    required this.id,
    required this.creatorId,
    this.clubId,
    required this.title,
    required this.locationText,
    required this.startsAt,
    this.endsAt,
    required this.priceCents,
    required this.currency,
    required this.category,
    required this.maxOccupancy,
    required this.overview,
    required this.equipmentNeeded,
    required this.skillLevel,
    required this.intensityLevel,
    required this.status,
    this.approvedBy,
    this.approvedAt,
    required this.createdAt,
    required this.updatedAt,
    this.rsvpCount = 0,
    this.avgRating,
    this.reviewCount,
  });

  final String id;
  final String creatorId;
  final String? clubId;
  final String title;
  final String locationText;
  final DateTime startsAt;
  final DateTime? endsAt;

  /// 0 = free; stored in cents to avoid floating-point issues.
  final int priceCents;
  final String currency;
  final String category;
  final int maxOccupancy;
  final String overview;
  final List<String> equipmentNeeded;
  final String skillLevel;
  final String intensityLevel;
  final String status;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Aggregated / joined fields — populated at query time
  final int rsvpCount;
  final double? avgRating;
  final int? reviewCount;

  bool get isFree => priceCents == 0;
  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';

  factory EventModel.fromJson(Map<String, dynamic> json) {
    // Supabase aggregate: event_rsvps(count) returns [{count: N}]
    int rsvpCount = 0;
    final rsvpRaw = json['rsvp_count'];
    if (rsvpRaw is List && rsvpRaw.isNotEmpty) {
      rsvpCount = (rsvpRaw.first['count'] as num?)?.toInt() ?? 0;
    } else if (rsvpRaw is int) {
      rsvpCount = rsvpRaw;
    }

    // Rating summary — joined from event_rating_summary view
    double? avgRating;
    int? reviewCount;
    final ratingRaw = json['event_rating_summary'];
    if (ratingRaw is List && ratingRaw.isNotEmpty) {
      final r = ratingRaw.first as Map<String, dynamic>;
      avgRating = (r['avg_rating'] as num?)?.toDouble();
      reviewCount = (r['review_count'] as num?)?.toInt();
    } else if (ratingRaw is Map<String, dynamic>) {
      avgRating = (ratingRaw['avg_rating'] as num?)?.toDouble();
      reviewCount = (ratingRaw['review_count'] as num?)?.toInt();
    }

    return EventModel(
      id: json['id'] as String,
      creatorId: json['creator_id'] as String,
      clubId: json['club_id'] as String?,
      title: json['title'] as String,
      locationText: json['location_text'] as String,
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: json['ends_at'] != null
          ? DateTime.parse(json['ends_at'] as String)
          : null,
      priceCents: (json['price_cents'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'USD',
      category: json['category'] as String,
      maxOccupancy: (json['max_occupancy'] as num).toInt(),
      overview: json['overview'] as String,
      equipmentNeeded: _parseStringList(json['equipment_needed']),
      skillLevel: json['skill_level'] as String,
      intensityLevel: json['intensity_level'] as String,
      status: json['status'] as String,
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      rsvpCount: rsvpCount,
      avgRating: avgRating,
      reviewCount: reviewCount,
    );
  }

  Map<String, dynamic> toInsertJson(String creatorId) => {
        'creator_id': creatorId,
        'club_id': clubId,
        'title': title,
        'location_text': locationText,
        'starts_at': startsAt.toIso8601String(),
        'ends_at': endsAt?.toIso8601String(),
        'price_cents': priceCents,
        'currency': currency,
        'category': category,
        'max_occupancy': maxOccupancy,
        'overview': overview,
        'equipment_needed': equipmentNeeded,
        'skill_level': skillLevel,
        'intensity_level': intensityLevel,
        // status is set by DB trigger based on is_trusted_host
      };

  static List<String> _parseStringList(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }
}
