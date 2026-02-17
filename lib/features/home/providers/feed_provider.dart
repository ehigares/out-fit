import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/event_model.dart';
import '../../onboarding/providers/profile_provider.dart';

// ---------------------------------------------------------------------------
// Filter state
// ---------------------------------------------------------------------------
class FeedFilters {
  const FeedFilters({
    this.category,
    this.intensityLevel,
    this.skillLevel,
    this.equipment,
  });

  final String? category;
  final String? intensityLevel;
  final String? skillLevel;
  final String? equipment;

  FeedFilters copyWith({
    String? category,
    String? intensityLevel,
    String? skillLevel,
    String? equipment,
    bool clearCategory = false,
    bool clearIntensity = false,
    bool clearSkill = false,
    bool clearEquipment = false,
  }) =>
      FeedFilters(
        category: clearCategory ? null : (category ?? this.category),
        intensityLevel:
            clearIntensity ? null : (intensityLevel ?? this.intensityLevel),
        skillLevel: clearSkill ? null : (skillLevel ?? this.skillLevel),
        equipment: clearEquipment ? null : (equipment ?? this.equipment),
      );

  bool get hasFilters =>
      category != null ||
      intensityLevel != null ||
      skillLevel != null ||
      equipment != null;
}

class FeedFilterNotifier extends StateNotifier<FeedFilters> {
  FeedFilterNotifier() : super(const FeedFilters());

  void setCategory(String? v) =>
      state = v == null ? state.copyWith(clearCategory: true) : state.copyWith(category: v);
  void setIntensity(String? v) =>
      state = v == null ? state.copyWith(clearIntensity: true) : state.copyWith(intensityLevel: v);
  void setSkill(String? v) =>
      state = v == null ? state.copyWith(clearSkill: true) : state.copyWith(skillLevel: v);
  void setEquipment(String? v) =>
      state = v == null ? state.copyWith(clearEquipment: true) : state.copyWith(equipment: v);
  void clearAll() => state = const FeedFilters();
}

final feedFilterProvider =
    StateNotifierProvider<FeedFilterNotifier, FeedFilters>(
  (_) => FeedFilterNotifier(),
);

// ---------------------------------------------------------------------------
// Shared Supabase event select string
// ---------------------------------------------------------------------------
const _eventSelect = '''
  *,
  rsvp_count:event_rsvps(count)
''';

// ---------------------------------------------------------------------------
// Fetch helpers — apply shared filters then Dart-side filter for extra fields
// ---------------------------------------------------------------------------
List<EventModel> _applyDartFilters(
  List<dynamic> raw,
  FeedFilters filters,
) {
  var events = raw.map((e) => EventModel.fromJson(e as Map<String, dynamic>)).toList();
  if (filters.category != null) {
    events = events.where((e) => e.category == filters.category).toList();
  }
  if (filters.intensityLevel != null) {
    events = events
        .where((e) => e.intensityLevel == filters.intensityLevel)
        .toList();
  }
  if (filters.skillLevel != null) {
    events = events.where((e) => e.skillLevel == filters.skillLevel).toList();
  }
  if (filters.equipment != null) {
    events = events
        .where((e) => e.equipmentNeeded.contains(filters.equipment))
        .toList();
  }
  return events;
}

// ---------------------------------------------------------------------------
// Nearby events (all approved, upcoming) — no geo in MVP; uses location label
// for extensibility. True geo can be added with PostGIS later.
// ---------------------------------------------------------------------------
final nearbyEventsProvider =
    FutureProvider.autoDispose<List<EventModel>>((ref) async {
  final filters = ref.watch(feedFilterProvider);
  final raw = await Supabase.instance.client
      .from('events')
      .select(_eventSelect)
      .eq('status', 'approved')
      .gte('starts_at', DateTime.now().toIso8601String())
      .order('starts_at');
  return _applyDartFilters(raw as List, filters);
});

// ---------------------------------------------------------------------------
// Free events
// ---------------------------------------------------------------------------
final freeEventsProvider =
    FutureProvider.autoDispose<List<EventModel>>((ref) async {
  final filters = ref.watch(feedFilterProvider);
  final raw = await Supabase.instance.client
      .from('events')
      .select(_eventSelect)
      .eq('status', 'approved')
      .eq('price_cents', 0)
      .gte('starts_at', DateTime.now().toIso8601String())
      .order('starts_at');
  return _applyDartFilters(raw as List, filters);
});

// ---------------------------------------------------------------------------
// Paid events
// ---------------------------------------------------------------------------
final paidEventsProvider =
    FutureProvider.autoDispose<List<EventModel>>((ref) async {
  final filters = ref.watch(feedFilterProvider);
  final raw = await Supabase.instance.client
      .from('events')
      .select(_eventSelect)
      .eq('status', 'approved')
      .gt('price_cents', 0)
      .gte('starts_at', DateTime.now().toIso8601String())
      .order('starts_at');
  return _applyDartFilters(raw as List, filters);
});

// ---------------------------------------------------------------------------
// Recommended — deterministic filter by user preferences.
// Stub for MVP: "Based on your preferences". No ML.
// Falls back to all approved events if user has no preferences set.
// ---------------------------------------------------------------------------
final recommendedEventsProvider =
    FutureProvider.autoDispose<List<EventModel>>((ref) async {
  final filters = ref.watch(feedFilterProvider);
  final profileAsync = await ref.watch(currentProfileProvider.future);

  var query = Supabase.instance.client
      .from('events')
      .select(_eventSelect)
      .eq('status', 'approved')
      .gte('starts_at', DateTime.now().toIso8601String())
      .order('starts_at');

  final raw = await query;
  var events = _applyDartFilters(raw as List, filters);

  // Apply preference-based filtering
  if (profileAsync != null) {
    final prefs = profileAsync.workoutPreferences;
    final intensityPrefs = profileAsync.intensityPreferences;

    if (prefs.isNotEmpty) {
      events = events.where((e) => prefs.contains(e.category)).toList();
    }
    if (intensityPrefs.isNotEmpty) {
      events = events
          .where((e) => intensityPrefs.contains(e.intensityLevel))
          .toList();
    }
  }

  return events;
});
