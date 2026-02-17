import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/event_model.dart';
import '../../../shared/models/rsvp_model.dart';

const _eventSelectFull = '''
  *,
  rsvp_count:event_rsvps(count),
  event_rating_summary(avg_rating, review_count)
''';

// ---------------------------------------------------------------------------
// Single event detail
// ---------------------------------------------------------------------------
final eventDetailProvider =
    FutureProvider.autoDispose.family<EventModel?, String>((ref, id) async {
  final raw = await Supabase.instance.client
      .from('events')
      .select(_eventSelectFull)
      .eq('id', id)
      .maybeSingle();
  if (raw == null) return null;
  return EventModel.fromJson(raw as Map<String, dynamic>);
});

// ---------------------------------------------------------------------------
// My events (created by current user — all statuses)
// ---------------------------------------------------------------------------
final myEventsProvider = FutureProvider.autoDispose<List<EventModel>>((ref) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return [];
  final raw = await Supabase.instance.client
      .from('events')
      .select('*, rsvp_count:event_rsvps(count)')
      .eq('creator_id', userId)
      .order('starts_at', ascending: false);
  return (raw as List)
      .map((e) => EventModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Check if current user has RSVP'd to a given event
// ---------------------------------------------------------------------------
final myRsvpProvider =
    FutureProvider.autoDispose.family<RsvpModel?, String>((ref, eventId) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return null;

  final raw = await Supabase.instance.client
      .from('event_rsvps')
      .select()
      .eq('event_id', eventId)
      .eq('user_id', userId)
      .maybeSingle();

  if (raw == null) return null;
  return RsvpModel.fromJson(raw as Map<String, dynamic>);
});

// ---------------------------------------------------------------------------
// Events notifier — CRUD + RSVP
// ---------------------------------------------------------------------------
class EventsNotifier extends StateNotifier<AsyncValue<void>> {
  EventsNotifier() : super(const AsyncValue.data(null));

  final _db = Supabase.instance.client;

  /// Creates an event. Status is set by DB trigger based on trusted_host flag.
  Future<String?> createEvent(EventModel event) async {
    state = const AsyncValue.loading();
    String? createdId;
    state = await AsyncValue.guard(() async {
      final userId = _db.auth.currentUser!.id;
      final result = await _db
          .from('events')
          .insert(event.toInsertJson(userId))
          .select('id, status')
          .single();
      createdId = result['id'] as String;
    });
    return state is AsyncError ? null : createdId;
  }

  /// Cancel an event (creator only — their own approved events).
  Future<bool> cancelEvent(String eventId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _db
          .from('events')
          .update({'status': 'cancelled'})
          .eq('id', eventId);
    });
    return state is! AsyncError;
  }

  /// RSVP to an event.
  Future<bool> rsvp(String eventId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final userId = _db.auth.currentUser!.id;
      await _db.from('event_rsvps').upsert({
        'event_id': eventId,
        'user_id': userId,
        'status': 'going',
      });
    });
    return state is! AsyncError;
  }

  /// Cancel RSVP.
  Future<bool> cancelRsvp(String eventId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final userId = _db.auth.currentUser!.id;
      await _db
          .from('event_rsvps')
          .update({'status': 'cancelled'})
          .eq('event_id', eventId)
          .eq('user_id', userId);
    });
    return state is! AsyncError;
  }
}

final eventsNotifierProvider =
    StateNotifierProvider<EventsNotifier, AsyncValue<void>>(
  (_) => EventsNotifier(),
);
