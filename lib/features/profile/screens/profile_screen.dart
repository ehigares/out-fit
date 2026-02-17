import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/models/profile_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../events/providers/events_provider.dart';
import '../../onboarding/providers/profile_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final myEventsAsync = ref.watch(myEventsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          profileAsync.maybeWhen(
            data: (p) {
              if (p?.isAdmin == true) {
                return IconButton(
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  tooltip: 'Admin Panel',
                  onPressed: () => context.push('/admin'),
                );
              }
              return const SizedBox.shrink();
            },
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Sign Out',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Sign Out'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                await ref.read(authNotifierProvider.notifier).signOut();
                if (context.mounted) context.go('/login');
              }
            },
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (profile) {
          if (profile == null) {
            return Center(
              child: ElevatedButton(
                onPressed: () => context.go('/onboarding'),
                child: const Text('Complete Profile'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Avatar + name
              Center(
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    profile.fullName.isNotEmpty
                        ? profile.fullName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                profile.fullName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              if (profile.verificationBadge == AppConstants.badgeVerified)
                const Center(
                  child: Chip(
                    avatar: Icon(Icons.verified, color: Colors.blue, size: 16),
                    label: Text('Verified', style: TextStyle(fontSize: 12)),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (profile.isAdmin)
                    const Chip(
                      avatar: Icon(Icons.shield, color: Colors.red, size: 16),
                      label: Text('Admin', style: TextStyle(fontSize: 12)),
                    ),
                  if (profile.isAdmin && profile.isTrustedHost)
                    const SizedBox(width: 8),
                  if (profile.isTrustedHost)
                    const Chip(
                      avatar: Icon(Icons.star, color: Colors.amber, size: 16),
                      label: Text('Trusted Host',
                          style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Info section
              _SectionHeader('Account Info'),
              _InfoTile(Icons.email_outlined, 'Email', profile.email),
              _InfoTile(
                  Icons.phone_outlined, 'Phone', '••••••••• (private)'),
              _InfoTile(Icons.location_on_outlined, 'Location',
                  profile.homeLocationLabel ?? AppConstants.defaultLocationLabel),
              _InfoTile(Icons.settings_outlined, 'Location Mode',
                  AppConstants.formatCategoryLabel(profile.locationMode)),
              if (profile.locationMode == AppConstants.locationModeRadius &&
                  profile.radiusMiles != null)
                _InfoTile(Icons.radar_outlined, 'Radius',
                    '${profile.radiusMiles} miles'),
              const SizedBox(height: 24),

              // Preferences
              _SectionHeader('Preferences'),
              _PrefChips('Workouts', profile.workoutPreferences),
              _PrefChips('Intensity', profile.intensityPreferences),
              _PrefChips('Equipment', profile.equipmentPreferences),
              const SizedBox(height: 24),

              // Edit profile button
              OutlinedButton.icon(
                onPressed: () => _showEditDialog(context, ref, profile),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Profile'),
              ),
              const SizedBox(height: 32),

              // My events
              _SectionHeader('My Events'),
              myEventsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Text(e.toString(), style: const TextStyle(color: Colors.red)),
                data: (events) => events.isEmpty
                    ? const Text('You have not created any events yet.',
                        style: TextStyle(color: Colors.grey))
                    : Column(
                        children: events
                            .map(
                              (e) => Card(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  onTap: () =>
                                      context.push('/events/${e.id}'),
                                  title: Text(e.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500)),
                                  subtitle: Text(e.status.toUpperCase()),
                                  trailing: _statusIcon(e.status),
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusIcon(String status) {
    switch (status) {
      case 'approved':
        return const Icon(Icons.check_circle, color: Colors.green);
      case 'pending':
        return const Icon(Icons.pending, color: Colors.orange);
      case 'rejected':
        return const Icon(Icons.cancel, color: Colors.red);
      case 'cancelled':
        return const Icon(Icons.block, color: Colors.grey);
      default:
        return const Icon(Icons.edit, color: Colors.blue);
    }
  }

  void _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    ProfileModel profile,
  ) {
    final nameCtrl = TextEditingController(text: profile.fullName);
    final phoneCtrl = TextEditingController(text: profile.phonePrivate);
    final locationCtrl =
        TextEditingController(text: profile.homeLocationLabel);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(
                  labelText: 'Phone (private)'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: locationCtrl,
              decoration:
                  const InputDecoration(labelText: 'Location Label'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final updated = profile.copyWith(
                fullName: nameCtrl.text.trim(),
                phonePrivate: phoneCtrl.text.trim(),
                homeLocationLabel: locationCtrl.text.trim(),
              );
              await ref
                  .read(profileNotifierProvider.notifier)
                  .updateProfile(updated);
              if (context.mounted) {
                ref.invalidate(currentProfileProvider);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(width: 10),
            Text('$label: ',
                style: const TextStyle(fontWeight: FontWeight.w500)),
            Expanded(
              child: Text(value,
                  style: const TextStyle(color: Colors.grey),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}

class _PrefChips extends StatelessWidget {
  const _PrefChips(this.label, this.values);
  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('$label: None set',
            style: const TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label:',
              style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: values
                .map(
                  (v) => Chip(
                    label: Text(AppConstants.formatCategoryLabel(v),
                        style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
