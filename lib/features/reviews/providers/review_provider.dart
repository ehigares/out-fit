import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/review_model.dart';

// ---------------------------------------------------------------------------
// Reviews for a single event (read by anyone for approved events via RLS)
// ---------------------------------------------------------------------------
final eventReviewsProvider =
    FutureProvider.autoDispose.family<List<ReviewModel>, String>(
  (ref, eventId) async {
    final raw = await Supabase.instance.client
        .from('event_reviews')
        // Only join name — never expose phone_private or email
        .select('*, profiles(full_name)')
        .eq('event_id', eventId)
        .order('created_at', ascending: false);

    return (raw as List)
        .map((e) => ReviewModel.fromJson(e as Map<String, dynamic>))
        .toList();
  },
);

// ---------------------------------------------------------------------------
// My review for a specific event (to prevent duplicate submission)
// ---------------------------------------------------------------------------
final myReviewProvider =
    FutureProvider.autoDispose.family<ReviewModel?, String>((ref, eventId) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return null;

  final raw = await Supabase.instance.client
      .from('event_reviews')
      .select()
      .eq('event_id', eventId)
      .eq('reviewer_id', userId)
      .maybeSingle();

  if (raw == null) return null;
  return ReviewModel.fromJson(raw as Map<String, dynamic>);
});

// ---------------------------------------------------------------------------
// Review submission notifier
// ---------------------------------------------------------------------------
class ReviewNotifier extends StateNotifier<AsyncValue<void>> {
  ReviewNotifier() : super(const AsyncValue.data(null));

  final _db = Supabase.instance.client;

  Future<bool> submitReview({
    required String eventId,
    required int rating,
    String? comment,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final userId = _db.auth.currentUser!.id;
      await _db.from('event_reviews').upsert({
        'event_id': eventId,
        'reviewer_id': userId,
        'rating': rating,
        'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
      });
    });
    return state is! AsyncError;
  }
}

final reviewNotifierProvider =
    StateNotifierProvider<ReviewNotifier, AsyncValue<void>>(
  (_) => ReviewNotifier(),
);
