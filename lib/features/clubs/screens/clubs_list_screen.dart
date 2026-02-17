import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../providers/clubs_provider.dart';

class ClubsListScreen extends ConsumerWidget {
  const ClubsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubsAsync = ref.watch(clubsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Clubs')),
      body: clubsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (clubs) => clubs.isEmpty
            ? const Center(
                child: Text('No clubs yet. Create one!',
                    style: TextStyle(color: Colors.grey)),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(clubsListProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 100),
                  itemCount: clubs.length,
                  itemBuilder: (_, i) {
                    final club = clubs[i];
                    return Card(
                      child: ListTile(
                        onTap: () => context.push('/clubs/${club.id}'),
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            club.name[0].toUpperCase(),
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(club.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (club.primaryCategory != null)
                              Text(AppConstants.formatCategoryLabel(
                                  club.primaryCategory!)),
                            if (club.homeBaseLocation != null)
                              Row(
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      size: 12, color: Colors.grey),
                                  const SizedBox(width: 2),
                                  Text(club.homeBaseLocation!,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    );
                  },
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/clubs/create'),
        icon: const Icon(Icons.add),
        label: const Text('Create Club'),
      ),
    );
  }
}
