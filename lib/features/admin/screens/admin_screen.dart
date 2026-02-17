import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/models/event_model.dart';
import '../../../shared/models/profile_model.dart';
import '../providers/admin_provider.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.pending_actions), text: 'Pending Events'),
            Tab(icon: Icon(Icons.people), text: 'Users'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _PendingEventsTab(),
          _UsersTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending events tab
// ---------------------------------------------------------------------------
class _PendingEventsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(pendingEventsProvider);

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            const Text('Admin access required'),
            Text(e.toString(),
                style: const TextStyle(fontSize: 12, color: Colors.red)),
          ],
        ),
      ),
      data: (events) => events.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: Colors.green),
                  SizedBox(height: 8),
                  Text('No pending events.',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(pendingEventsProvider),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: events.length,
                itemBuilder: (_, i) =>
                    _PendingEventCard(event: events[i]),
              ),
            ),
    );
  }
}

class _PendingEventCard extends ConsumerWidget {
  const _PendingEventCard({required this.event});
  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr =
        DateFormat('MMM d, y h:mm a').format(event.startsAt.toLocal());

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            onTap: () => context.push('/events/${event.id}'),
            title: Text(event.title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateStr),
                Text(event.locationText),
                Text(
                    '${AppConstants.formatCategoryLabel(event.category)} • ${AppConstants.formatCategoryLabel(event.skillLevel)} • ${AppConstants.formatPriceCents(event.priceCents, event.currency)}'),
              ],
            ),
            trailing: const Icon(Icons.open_in_new, size: 18),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              event.overview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await ref
                          .read(adminNotifierProvider.notifier)
                          .rejectEvent(event.id);
                      if (ok && context.mounted) {
                        ref.invalidate(pendingEventsProvider);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Event rejected'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final ok = await ref
                          .read(adminNotifierProvider.notifier)
                          .approveEvent(event.id);
                      if (ok && context.mounted) {
                        ref.invalidate(pendingEventsProvider);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Event approved!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Users tab — toggle trusted_host and admin flags
// ---------------------------------------------------------------------------
class _UsersTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(allProfilesProvider);

    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (users) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(allProfilesProvider),
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: users.length,
          itemBuilder: (_, i) => _UserCard(profile: users[i]),
        ),
      ),
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.profile});
  final ProfileModel profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(profile.fullName.isNotEmpty
                      ? profile.fullName[0].toUpperCase()
                      : '?'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.fullName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                      Text(profile.email,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Trusted Host: ',
                    style: TextStyle(fontSize: 13)),
                const Spacer(),
                Switch(
                  value: profile.isTrustedHost,
                  onChanged: (v) async {
                    final ok = await ref
                        .read(adminNotifierProvider.notifier)
                        .toggleTrustedHost(profile.id, profile.isTrustedHost);
                    if (ok && context.mounted) {
                      ref.invalidate(allProfilesProvider);
                    }
                  },
                ),
              ],
            ),
            Row(
              children: [
                const Text('Admin: ', style: TextStyle(fontSize: 13)),
                const Spacer(),
                Switch(
                  value: profile.isAdmin,
                  onChanged: (v) async {
                    // Confirm before granting admin
                    if (!profile.isAdmin) {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Grant Admin'),
                          content: Text(
                              'Grant admin access to ${profile.fullName}?'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, true),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.red),
                              child: const Text('Grant'),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                    }
                    final ok = await ref
                        .read(adminNotifierProvider.notifier)
                        .toggleAdmin(profile.id, profile.isAdmin);
                    if (ok && context.mounted) {
                      ref.invalidate(allProfilesProvider);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
