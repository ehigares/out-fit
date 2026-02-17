import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/models/event_model.dart';
import '../../onboarding/providers/profile_provider.dart';
import '../providers/feed_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    // Check onboarding completion
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkProfile());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkProfile() async {
    final profile = await ref.read(currentProfileProvider.future);
    if (profile == null && mounted) {
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(feedFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Out-Fit', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          // Filter button
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Filter',
                onPressed: () => _showFilterSheet(context),
              ),
              if (filters.hasFilters)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Nearby'),
            Tab(text: 'Free'),
            Tab(text: 'Paid'),
            Tab(text: 'For You'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _EventFeedTab(provider: nearbyEventsProvider),
          _EventFeedTab(provider: freeEventsProvider),
          _EventFeedTab(provider: paidEventsProvider),
          _EventFeedTab(
            provider: recommendedEventsProvider,
            emptyMessage: 'No recommendations yet.\nUpdate your preferences in Profile.',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/events/create'),
        icon: const Icon(Icons.add),
        label: const Text('Create Event'),
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _FilterSheet(),
    );
  }
}

// ---------------------------------------------------------------------------
// Event feed tab
// ---------------------------------------------------------------------------
class _EventFeedTab extends ConsumerWidget {
  const _EventFeedTab({
    required this.provider,
    this.emptyMessage = 'No upcoming events found.',
  });

  final ProviderListenable<AsyncValue<List<EventModel>>> provider;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(e.toString()),
            TextButton(
              onPressed: () => ref.invalidate(provider as ProviderOrFamily),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (events) => events.isEmpty
          ? Center(
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(provider as ProviderOrFamily),
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 100),
                itemCount: events.length,
                itemBuilder: (_, i) => _EventCard(event: events[i]),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Event card
// ---------------------------------------------------------------------------
class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr =
        DateFormat('EEE, MMM d • h:mm a').format(event.startsAt.toLocal());

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/events/${event.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category + price row
              Row(
                children: [
                  Chip(
                    label: Text(
                      AppConstants.formatCategoryLabel(event.category),
                      style: const TextStyle(fontSize: 11),
                    ),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: event.isFree
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: event.isFree ? Colors.green : Colors.orange,
                      ),
                    ),
                    child: Text(
                      AppConstants.formatPriceCents(
                          event.priceCents, event.currency),
                      style: TextStyle(
                        color: event.isFree
                            ? Colors.green.shade700
                            : Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Title
              Text(
                event.title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              // Date
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    dateStr,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Location
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      event.locationText,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Tags + stats
              Row(
                children: [
                  _tag(
                    AppConstants.formatCategoryLabel(event.skillLevel),
                    Colors.blue.shade50,
                    Colors.blue.shade700,
                  ),
                  const SizedBox(width: 6),
                  _tag(
                    AppConstants.formatCategoryLabel(event.intensityLevel),
                    Colors.purple.shade50,
                    Colors.purple.shade700,
                  ),
                  const Spacer(),
                  // RSVP count (public — count only, not list)
                  const Icon(Icons.people_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('${event.rsvpCount}/${event.maxOccupancy}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (event.avgRating != null) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.star, size: 14, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(
                      event.avgRating!.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: fg)),
      );
}

// ---------------------------------------------------------------------------
// Filter bottom sheet
// ---------------------------------------------------------------------------
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(feedFilterProvider);
    final notifier = ref.read(feedFilterProvider.notifier);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, ctrl) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: ListView(
          controller: ctrl,
          children: [
            Row(
              children: [
                Text('Filters',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        )),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    notifier.clearAll();
                    Navigator.pop(context);
                  },
                  child: const Text('Clear all'),
                ),
              ],
            ),
            const Divider(),
            _filterSection(
              context,
              'Category',
              AppConstants.eventCategories,
              filters.category,
              (v) => notifier.setCategory(v == filters.category ? null : v),
            ),
            _filterSection(
              context,
              'Intensity',
              AppConstants.intensityLevels,
              filters.intensityLevel,
              (v) => notifier.setIntensity(
                  v == filters.intensityLevel ? null : v),
            ),
            _filterSection(
              context,
              'Skill Level',
              AppConstants.skillLevels,
              filters.skillLevel,
              (v) =>
                  notifier.setSkill(v == filters.skillLevel ? null : v),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterSection(
    BuildContext ctx,
    String title,
    List<String> options,
    String? selected,
    void Function(String) onTap,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: options
                .map(
                  (o) => FilterChip(
                    label: Text(AppConstants.formatCategoryLabel(o),
                        style: const TextStyle(fontSize: 12)),
                    selected: selected == o,
                    onSelected: (_) => onTap(o),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
      );
}
