class ClubModel {
  const ClubModel({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    this.primaryCategory,
    this.homeBaseLocation,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String? primaryCategory;
  final String? homeBaseLocation;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ClubModel.fromJson(Map<String, dynamic> json) {
    return ClubModel(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      primaryCategory: json['primary_category'] as String?,
      homeBaseLocation: json['home_base_location'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson(String ownerId) => {
        'owner_id': ownerId,
        'name': name,
        'description': description,
        'primary_category': primaryCategory,
        'home_base_location': homeBaseLocation,
      };
}
