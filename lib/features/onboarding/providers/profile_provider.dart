import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/profile_model.dart';

// ---------------------------------------------------------------------------
// Current user profile — loaded once and cached.
// Use ref.invalidate(currentProfileProvider) to force a refresh.
// ---------------------------------------------------------------------------
final currentProfileProvider = FutureProvider<ProfileModel?>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;

  final data = await Supabase.instance.client
      .from('profiles')
      .select()
      .eq('id', user.id)
      .maybeSingle();

  if (data == null) return null;
  return ProfileModel.fromJson(data as Map<String, dynamic>);
});

// ---------------------------------------------------------------------------
// Profile upsert notifier
// ---------------------------------------------------------------------------
class ProfileNotifier extends StateNotifier<AsyncValue<void>> {
  ProfileNotifier() : super(const AsyncValue.data(null));

  final _db = Supabase.instance.client;

  Future<void> createProfile(ProfileModel profile) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _db.from('profiles').insert(profile.toInsertJson());
    });
  }

  Future<void> updateProfile(ProfileModel profile) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _db
          .from('profiles')
          .update(profile.toUpdateJson())
          .eq('id', profile.id);
    });
  }
}

final profileNotifierProvider =
    StateNotifierProvider<ProfileNotifier, AsyncValue<void>>(
  (_) => ProfileNotifier(),
);
