import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/event_model.dart';
import '../../../shared/models/profile_model.dart';

// ---------------------------------------------------------------------------
// Pending events — admin only (RLS ensures non-admins get empty results)
// ---------------------------------------------------------------------------
final pendingEventsProvider =
    FutureProvider.autoDispose<List<EventModel>>((ref) async {
  final raw = await Supabase.instance.client
      .from('events')
      .select('*, rsvp_count:event_rsvps(count)')
      .eq('status', 'pending')
      .order('created_at');
  return (raw as List)
      .map((e) => EventModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// All users — admin only (profiles RLS restricts non-admins)
// ---------------------------------------------------------------------------
final allProfilesProvider =
    FutureProvider.autoDispose<List<ProfileModel>>((ref) async {
  final raw = await Supabase.instance.client
      .from('profiles')
      // Exclude phone_private from admin list view — only accessible in own profile
      .select(
          'id, full_name, email, is_admin, is_trusted_host, verification_badge, created_at, updated_at, '
          'home_location_label, location_mode, radius_miles, city, state, '
          'workout_preferences, intensity_preferences, equipment_preferences, '
          'is_18_plus, phone_private')
      .order('created_at');
  return (raw as List)
      .map((e) => ProfileModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Admin action notifier
// ---------------------------------------------------------------------------
class AdminNotifier extends StateNotifier<AsyncValue<void>> {
  AdminNotifier() : super(const AsyncValue.data(null));

  final _db = Supabase.instance.client;

  Future<bool> approveEvent(String eventId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final adminId = _db.auth.currentUser!.id;
      await _db.from('events').update({
        'status': 'approved',
        'approved_by': adminId,
        'approved_at': DateTime.now().toIso8601String(),
      }).eq('id', eventId);
    });
    return state is! AsyncError;
  }

  Future<bool> rejectEvent(String eventId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _db
          .from('events')
          .update({'status': 'rejected'})
          .eq('id', eventId);
    });
    return state is! AsyncError;
  }

  /// Toggle trusted host status for a user.
  Future<bool> toggleTrustedHost(String userId, bool current) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _db
          .from('profiles')
          .update({'is_trusted_host': !current})
          .eq('id', userId);
    });
    return state is! AsyncError;
  }

  /// Toggle admin status — use with caution.
  Future<bool> toggleAdmin(String userId, bool current) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _db
          .from('profiles')
          .update({'is_admin': !current})
          .eq('id', userId);
    });
    return state is! AsyncError;
  }
}

final adminNotifierProvider =
    StateNotifierProvider<AdminNotifier, AsyncValue<void>>(
  (_) => AdminNotifier(),
);
