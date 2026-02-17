import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/models/event_model.dart';
import '../../clubs/providers/clubs_provider.dart';
import '../../onboarding/providers/profile_provider.dart';
import '../providers/events_provider.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _overviewCtrl = TextEditingController();
  final _maxOccupancyCtrl = TextEditingController(text: '20');
  final _priceCentsCtrl = TextEditingController(text: '0');

  String _category = AppConstants.eventCategories.first;
  String _skillLevel = AppConstants.skillLevels.first;
  String _intensityLevel = AppConstants.intensityLevels.first;
  DateTime _startsAt = DateTime.now().add(const Duration(days: 1));
  DateTime? _endsAt;
  String? _clubId;
  final Set<String> _equipment = {};

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    _overviewCtrl.dispose();
    _maxOccupancyCtrl.dispose();
    _priceCentsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (time == null) return;
    setState(() {
      _startsAt = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final priceCents =
        (double.tryParse(_priceCentsCtrl.text) ?? 0) * 100;

    final event = EventModel(
      id: '',
      creatorId: '',
      clubId: _clubId,
      title: _titleCtrl.text.trim(),
      locationText: _locationCtrl.text.trim(),
      startsAt: _startsAt,
      endsAt: _endsAt,
      priceCents: priceCents.toInt(),
      currency: 'USD',
      category: _category,
      maxOccupancy: int.parse(_maxOccupancyCtrl.text),
      overview: _overviewCtrl.text.trim(),
      equipmentNeeded: _equipment.toList(),
      skillLevel: _skillLevel,
      intensityLevel: _intensityLevel,
      status: 'pending',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final eventId = await ref
        .read(eventsNotifierProvider.notifier)
        .createEvent(event);

    if (!mounted) return;

    final err = ref.read(eventsNotifierProvider);
    err.whenOrNull(
      error: (e, _) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      ),
    );

    if (eventId != null) {
      // Show pending/approved info
      final profile = await ref.read(currentProfileProvider.future);
      final isTrusted = profile?.isTrustedHost ?? false;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isTrusted
                  ? 'Event published successfully!'
                  : 'Event submitted for admin approval.',
            ),
            backgroundColor: isTrusted ? Colors.green : Colors.orange,
          ),
        );
        context.go('/events/$eventId');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(eventsNotifierProvider) is AsyncLoading;
    final myClubsAsync = ref.watch(myClubsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Event')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title
                TextFormField(
                  controller: _titleCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Event Title *',
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Title required' : null,
                ),
                const SizedBox(height: 16),

                // Category
                DropdownButtonFormField<String>(
                  value: _category,
                  decoration: const InputDecoration(
                    labelText: 'Category *',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: AppConstants.eventCategories
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                                AppConstants.formatCategoryLabel(c)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _category = v!),
                ),
                const SizedBox(height: 16),

                // Location
                TextFormField(
                  controller: _locationCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Location *',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    hintText: 'e.g., Dolores Park, San Francisco',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Location required' : null,
                ),
                const SizedBox(height: 16),

                // Start date/time
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('Start Date & Time *'),
                  subtitle: Text(
                    DateFormat('EEE, MMM d, y h:mm a').format(_startsAt),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickStartDate,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade400),
                  ),
                ),
                const SizedBox(height: 16),

                // Skill level
                DropdownButtonFormField<String>(
                  value: _skillLevel,
                  decoration: const InputDecoration(
                    labelText: 'Skill Level *',
                    prefixIcon: Icon(Icons.fitness_center),
                  ),
                  items: AppConstants.skillLevels
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child:
                                Text(AppConstants.formatCategoryLabel(s)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _skillLevel = v!),
                ),
                const SizedBox(height: 16),

                // Intensity level
                DropdownButtonFormField<String>(
                  value: _intensityLevel,
                  decoration: const InputDecoration(
                    labelText: 'Intensity Level *',
                    prefixIcon: Icon(Icons.bolt_outlined),
                  ),
                  items: AppConstants.intensityLevels
                      .map((i) => DropdownMenuItem(
                            value: i,
                            child:
                                Text(AppConstants.formatCategoryLabel(i)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _intensityLevel = v!),
                ),
                const SizedBox(height: 16),

                // Max occupancy
                TextFormField(
                  controller: _maxOccupancyCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Max Attendees *',
                    prefixIcon: Icon(Icons.people_outlined),
                  ),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 1) return 'Enter a valid number';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Price (0 = free)
                TextFormField(
                  controller: _priceCentsCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Price (USD) — 0 for free',
                    prefixIcon: Icon(Icons.attach_money),
                    helperText:
                        'Full payment integration coming soon. Set price for informational purposes.',
                  ),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    if (n == null || n < 0) return 'Enter 0 or a positive amount';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Optional club association
                myClubsAsync.maybeWhen(
                  data: (clubs) => clubs.isEmpty
                      ? const SizedBox.shrink()
                      : DropdownButtonFormField<String?>(
                          value: _clubId,
                          decoration: const InputDecoration(
                            labelText: 'Associate with Club (optional)',
                            prefixIcon: Icon(Icons.groups_outlined),
                          ),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('None')),
                            ...clubs.map((c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                )),
                          ],
                          onChanged: (v) => setState(() => _clubId = v),
                        ),
                  orElse: () => const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),

                // Equipment
                const Text('Equipment Needed',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: AppConstants.equipmentOptions
                      .map(
                        (o) => FilterChip(
                          label: Text(
                            AppConstants.formatCategoryLabel(o),
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: _equipment.contains(o),
                          onSelected: (_) => setState(() {
                            _equipment.contains(o)
                                ? _equipment.remove(o)
                                : _equipment.add(o);
                          }),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),

                // Overview
                TextFormField(
                  controller: _overviewCtrl,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Event Overview *',
                    prefixIcon: Icon(Icons.description_outlined),
                    alignLabelWithHint: true,
                    hintText:
                        'Describe the event, what to expect, meeting point, etc.',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Overview required' : null,
                ),
                const SizedBox(height: 32),

                // Info about approval
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'New events require admin approval unless you are a trusted host.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: saving ? null : _submit,
                  child: saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit Event'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
