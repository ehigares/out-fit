import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/club_model.dart';

// ---------------------------------------------------------------------------
// All clubs list (public read)
// ---------------------------------------------------------------------------
final clubsListProvider = FutureProvider.autoDispose<List<ClubModel>>((ref) async {
  final raw = await Supabase.instance.client
      .from('clubs')
      .select()
      .order('name');
  return (raw as List)
      .map((e) => ClubModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Single club by id
// ---------------------------------------------------------------------------
final clubDetailProvider =
    FutureProvider.autoDispose.family<ClubModel?, String>((ref, clubId) async {
  final raw = await Supabase.instance.client
      .from('clubs')
      .select()
      .eq('id', clubId)
      .maybeSingle();
  if (raw == null) return null;
  return ClubModel.fromJson(raw as Map<String, dynamic>);
});

// ---------------------------------------------------------------------------
// My clubs (owned by current user)
// ---------------------------------------------------------------------------
final myClubsProvider = FutureProvider.autoDispose<List<ClubModel>>((ref) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return [];
  final raw = await Supabase.instance.client
      .from('clubs')
      .select()
      .eq('owner_id', userId)
      .order('name');
  return (raw as List)
      .map((e) => ClubModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Clubs CRUD notifier
// ---------------------------------------------------------------------------
class ClubsNotifier extends StateNotifier<AsyncValue<void>> {
  ClubsNotifier() : super(const AsyncValue.data(null));

  final _db = Supabase.instance.client;

  Future<String?> createClub({
    required String name,
    String? description,
    String? primaryCategory,
    String? homeBaseLocation,
  }) async {
    state = const AsyncValue.loading();
    String? createdId;
    state = await AsyncValue.guard(() async {
      final userId = _db.auth.currentUser!.id;
      final result = await _db.from('clubs').insert({
        'owner_id': userId,
        'name': name,
        'description': description,
        'primary_category': primaryCategory,
        'home_base_location': homeBaseLocation,
      }).select('id').single();
      createdId = result['id'] as String;
    });
    return state is AsyncError ? null : createdId;
  }

  Future<bool> deleteClub(String clubId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _db.from('clubs').delete().eq('id', clubId);
    });
    return state is! AsyncError;
  }
}

final clubsNotifierProvider =
    StateNotifierProvider<ClubsNotifier, AsyncValue<void>>(
  (_) => ClubsNotifier(),
);
