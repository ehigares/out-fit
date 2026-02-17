import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../providers/clubs_provider.dart';

class ClubDetailScreen extends ConsumerWidget {
  const ClubDetailScreen({super.key, required this.clubId});

  final String clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubAsync = ref.watch(clubDetailProvider(clubId));
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: clubAsync.maybeWhen(
          data: (c) => Text(c?.name ?? 'Club'),
          orElse: () => const Text('Club'),
        ),
        actions: [
          clubAsync.maybeWhen(
            data: (club) {
              if (club != null && club.ownerId == currentUserId) {
                return PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete Club'),
                          content: const Text(
                              'Are you sure? This cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.red),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && context.mounted) {
                        final ok = await ref
                            .read(clubsNotifierProvider.notifier)
                            .deleteClub(clubId);
                        if (ok && context.mounted) {
                          ref.invalidate(clubsListProvider);
                          context.pop();
                        }
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Delete Club')),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: clubAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (club) {
          if (club == null) {
            return const Center(child: Text('Club not found'));
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Header
              CircleAvatar(
                radius: 40,
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  club.name[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                club.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              if (club.primaryCategory != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: Chip(
                    label: Text(AppConstants.formatCategoryLabel(
                        club.primaryCategory!)),
                  ),
                ),
              ],
              if (club.homeBaseLocation != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(club.homeBaseLocation!,
                        style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              const Divider(),
              if (club.description != null && club.description!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('About',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(club.description!),
              ],
              const SizedBox(height: 24),
              // Owner info
              if (club.ownerId == currentUserId)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.admin_panel_settings_outlined,
                          color: Colors.green),
                      SizedBox(width: 8),
                      Text('You own this club'),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
