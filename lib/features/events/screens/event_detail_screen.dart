import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../onboarding/providers/profile_provider.dart';
import '../providers/events_provider.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventDetailProvider(eventId));
    final rsvpAsync = ref.watch(myRsvpProvider(eventId));
    final profileAsync = ref.watch(currentProfileProvider);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event'),
        actions: [
          eventAsync.maybeWhen(
            data: (event) {
              if (event == null) return const SizedBox.shrink();
              final isCreator = event.creatorId == currentUserId;
              if (!isCreator) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'cancel') {
                    final ok = await ref
                        .read(eventsNotifierProvider.notifier)
                        .cancelEvent(eventId);
                    if (ok && context.mounted) {
                      ref.invalidate(eventDetailProvider(eventId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Event cancelled')),
                      );
                    }
                  }
                },
                itemBuilder: (_) => [
                  if (event.status == 'approved' || event.status == 'pending')
                    const PopupMenuItem(
                        value: 'cancel', child: Text('Cancel Event')),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (event) {
          if (event == null) {
            return const Center(child: Text('Event not found'));
          }

          final isCreator = event.creatorId == currentUserId;
          final isAdmin = profileAsync.valueOrNull?.isAdmin ?? false;
          final canSeeRsvpList = isCreator || isAdmin;
          final dateStr = DateFormat('EEEE, MMMM d, y\nh:mm a')
              .format(event.startsAt.toLocal());

          return ListView(
            padding: const EdgeInsets.all(0),
            children: [
              // Status banner
              if (event.status != 'approved')
                _StatusBanner(status: event.status),

              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category + price
                    Row(
                      children: [
                        Chip(
                          label: Text(
                              AppConstants.formatCategoryLabel(event.category)),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: event.isFree
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  event.isFree ? Colors.green : Colors.orange,
                            ),
                          ),
                          child: Text(
                            AppConstants.formatPriceCents(
                                event.priceCents, event.currency),
                            style: TextStyle(
                              color: event.isFree
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Title
                    Text(
                      event.title,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    // Date
                    _InfoRow(
                        icon: Icons.calendar_today_outlined, text: dateStr),
                    if (event.endsAt != null)
                      _InfoRow(
                        icon: Icons.alarm,
                        text:
                            'Ends: ${DateFormat('h:mm a').format(event.endsAt!.toLocal())}',
                      ),
                    const SizedBox(height: 4),

                    // Location
                    _InfoRow(
                        icon: Icons.location_on_outlined,
                        text: event.locationText),
                    const SizedBox(height: 4),

                    // Skill + intensity
                    Row(
                      children: [
                        _InfoChip(
                          'Skill: ${AppConstants.formatCategoryLabel(event.skillLevel)}',
                          Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        _InfoChip(
                          'Intensity: ${AppConstants.formatCategoryLabel(event.intensityLevel)}',
                          Colors.purple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // RSVP count (public) + rating
                    Row(
                      children: [
                        const Icon(Icons.people_outline, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          '${event.rsvpCount} / ${event.maxOccupancy} going',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        const Spacer(),
                        if (event.avgRating != null) ...[
                          const Icon(Icons.star, color: Colors.amber, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            '${event.avgRating!.toStringAsFixed(1)} (${event.reviewCount ?? 0})',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),

                    // RSVP list button (host/admin only — private)
                    if (canSeeRsvpList) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.push('/events/$eventId/rsvps'),
                        icon: const Icon(Icons.list_alt, size: 18),
                        label: const Text('View Attendee List (Host/Admin)'),
                      ),
                    ],

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Overview
                    Text(
                      'About this event',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(event.overview),

                    // Equipment
                    if (event.equipmentNeeded.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Equipment Needed',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: event.equipmentNeeded
                            .map((e) => Chip(
                                  label: Text(
                                      AppConstants.formatCategoryLabel(e),
                                      style: const TextStyle(fontSize: 12)),
                                ))
                            .toList(),
                      ),
                    ],

                    // Paid event note — Stripe placeholder
                    if (!event.isFree) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.payment_outlined,
                                color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Payment required. Payment processing coming soon.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // RSVP button
                    if (event.isApproved) ...[
                      rsvpAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (rsvp) {
                          final isGoing = rsvp?.isGoing ?? false;
                          final isFull =
                              event.rsvpCount >= event.maxOccupancy && !isGoing;

                          if (isFull && !isGoing) {
                            return const Center(
                              child: Text('Event is full',
                                  style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold)),
                            );
                          }

                          return ElevatedButton.icon(
                            onPressed: () async {
                              final notifier = ref
                                  .read(eventsNotifierProvider.notifier);
                              bool ok;
                              if (isGoing) {
                                ok = await notifier.cancelRsvp(eventId);
                              } else {
                                ok = await notifier.rsvp(eventId);
                              }
                              if (ok && context.mounted) {
                                ref.invalidate(myRsvpProvider(eventId));
                                ref.invalidate(eventDetailProvider(eventId));
                              }
                            },
                            icon: Icon(
                              isGoing
                                  ? Icons.cancel_outlined
                                  : Icons.check_circle_outline,
                            ),
                            label: Text(isGoing ? 'Cancel RSVP' : 'RSVP — Going'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isGoing
                                  ? Colors.red.shade50
                                  : null,
                              foregroundColor:
                                  isGoing ? Colors.red : null,
                            ),
                          );
                        },
                      ),
                    ],

                    // Write review (if RSVP'd)
                    rsvpAsync.maybeWhen(
                      data: (rsvp) {
                        if (rsvp?.isGoing != true) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  context.push('/events/$eventId/review'),
                              icon: const Icon(Icons.rate_review_outlined),
                              label: const Text('Write a Review'),
                            ),
                          ],
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    ),
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = {
      'pending': (Colors.orange.shade50, Colors.orange.shade800),
      'rejected': (Colors.red.shade50, Colors.red.shade800),
      'cancelled': (Colors.grey.shade100, Colors.grey.shade700),
      'draft': (Colors.blue.shade50, Colors.blue.shade800),
    };
    final icons = {
      'pending': Icons.pending_outlined,
      'rejected': Icons.cancel_outlined,
      'cancelled': Icons.block_outlined,
      'draft': Icons.edit_outlined,
    };
    final messages = {
      'pending': 'Pending admin approval',
      'rejected': 'This event was rejected',
      'cancelled': 'This event has been cancelled',
      'draft': 'Draft — not yet submitted',
    };

    final (bg, fg) = colors[status] ?? (Colors.grey.shade100, Colors.grey);

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icons[status] ?? Icons.info_outline, color: fg, size: 18),
          const SizedBox(width: 8),
          Text(
            messages[status] ?? status,
            style: TextStyle(color: fg, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
      );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.label, this.color);
  final String label;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: color.shade700),
        ),
      );
}
