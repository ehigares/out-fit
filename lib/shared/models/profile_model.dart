class ProfileModel {
  const ProfileModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phonePrivate,
    required this.is18Plus,
    this.homeLocationLabel,
    required this.locationMode,
    this.radiusMiles,
    this.city,
    this.state,
    required this.workoutPreferences,
    required this.intensityPreferences,
    required this.equipmentPreferences,
    required this.isAdmin,
    required this.isTrustedHost,
    required this.verificationBadge,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String fullName;
  final String email;
  // Never display phone to other users — stored private
  final String phonePrivate;
  final bool is18Plus;
  final String? homeLocationLabel;
  final String locationMode;
  final int? radiusMiles;
  final String? city;
  final String? state;
  final List<String> workoutPreferences;
  final List<String> intensityPreferences;
  final List<String> equipmentPreferences;
  final bool isAdmin;
  final bool isTrustedHost;
  final String verificationBadge;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      phonePrivate: json['phone_private'] as String,
      is18Plus: json['is_18_plus'] as bool? ?? false,
      homeLocationLabel: json['home_location_label'] as String?,
      locationMode: json['location_mode'] as String? ?? 'radius',
      radiusMiles: json['radius_miles'] as int?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      workoutPreferences: _parseStringList(json['workout_preferences']),
      intensityPreferences: _parseStringList(json['intensity_preferences']),
      equipmentPreferences: _parseStringList(json['equipment_preferences']),
      isAdmin: json['is_admin'] as bool? ?? false,
      isTrustedHost: json['is_trusted_host'] as bool? ?? false,
      verificationBadge: json['verification_badge'] as String? ?? 'none',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'phone_private': phonePrivate,
        'is_18_plus': is18Plus,
        'home_location_label': homeLocationLabel,
        'location_mode': locationMode,
        'radius_miles': radiusMiles,
        'city': city,
        'state': state,
        'workout_preferences': workoutPreferences,
        'intensity_preferences': intensityPreferences,
        'equipment_preferences': equipmentPreferences,
      };

  Map<String, dynamic> toUpdateJson() => {
        'full_name': fullName,
        'phone_private': phonePrivate,
        'home_location_label': homeLocationLabel,
        'location_mode': locationMode,
        'radius_miles': radiusMiles,
        'city': city,
        'state': state,
        'workout_preferences': workoutPreferences,
        'intensity_preferences': intensityPreferences,
        'equipment_preferences': equipmentPreferences,
      };

  ProfileModel copyWith({
    String? fullName,
    String? phonePrivate,
    String? homeLocationLabel,
    String? locationMode,
    int? radiusMiles,
    String? city,
    String? state,
    List<String>? workoutPreferences,
    List<String>? intensityPreferences,
    List<String>? equipmentPreferences,
  }) =>
      ProfileModel(
        id: id,
        fullName: fullName ?? this.fullName,
        email: email,
        phonePrivate: phonePrivate ?? this.phonePrivate,
        is18Plus: is18Plus,
        homeLocationLabel: homeLocationLabel ?? this.homeLocationLabel,
        locationMode: locationMode ?? this.locationMode,
        radiusMiles: radiusMiles ?? this.radiusMiles,
        city: city ?? this.city,
        state: state ?? this.state,
        workoutPreferences: workoutPreferences ?? this.workoutPreferences,
        intensityPreferences: intensityPreferences ?? this.intensityPreferences,
        equipmentPreferences: equipmentPreferences ?? this.equipmentPreferences,
        isAdmin: isAdmin,
        isTrustedHost: isTrustedHost,
        verificationBadge: verificationBadge,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }
}
