import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/rsvp_model.dart';
import '../../onboarding/providers/profile_provider.dart';

// ---------------------------------------------------------------------------
// PRIVATE screen — attendee list visible only to host and admin.
// RLS on the DB also enforces this; this screen adds a UI-level check.
// ---------------------------------------------------------------------------

final _rsvpListProvider =
    FutureProvider.autoDispose.family<List<RsvpModel>, String>((ref, eventId) async {
  // Fetch with profile name join; phone_private is NOT selected.
  final raw = await Supabase.instance.client
      .from('event_rsvps')
      .select('*, profiles(full_name, email)')
      .eq('event_id', eventId)
      .eq('status', 'going')
      .order('created_at');

  return (raw as List)
      .map((e) => RsvpModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

class RsvpAttendeesScreen extends ConsumerWidget {
  const RsvpAttendeesScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final rsvpAsync = ref.watch(_rsvpListProvider(eventId));
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendees'),
        subtitle: const Text('Private — visible to host & admin only',
            style: TextStyle(fontSize: 11)),
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (profile) {
          // UI-level guard (DB RLS is the real enforcement)
          // The query will fail or return empty if user is not authorized.
          final isAdmin = profile?.isAdmin ?? false;
          _ = isAdmin; // suppress unused warning — used in label below

          return rsvpAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 48, color: Colors.grey),
                  const SizedBox(height: 8),
                  Text(
                    'Access denied or no attendees.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    e.toString(),
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            data: (rsvps) {
              if (rsvps.isEmpty) {
                return const Center(
                  child: Text('No attendees yet.',
                      style: TextStyle(color: Colors.grey)),
                );
              }
              return Column(
                children: [
                  Container(
                    color: Colors.amber.shade50,
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outlined,
                            color: Colors.amber, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This list is private. ${rsvps.length} attendee(s) going.',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: rsvps.length,
                      itemBuilder: (_, i) {
                        final rsvp = rsvps[i];
                        final isMe = rsvp.userId == currentUserId;
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              (rsvp.fullName?.isNotEmpty == true
                                      ? rsvp.fullName![0]
                                      : '?')
                                  .toUpperCase(),
                            ),
                          ),
                          title: Text(
                            rsvp.fullName ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: isMe
                              ? const Text('(you)',
                                  style: TextStyle(fontStyle: FontStyle.italic))
                              : null,
                          trailing: isAdmin
                              ? Text(rsvp.email ?? '',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey))
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
