import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../providers/clubs_provider.dart';

class CreateClubScreen extends ConsumerStatefulWidget {
  const CreateClubScreen({super.key});

  @override
  ConsumerState<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends ConsumerState<CreateClubScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  String? _selectedCategory;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final clubId = await ref.read(clubsNotifierProvider.notifier).createClub(
          name: _nameCtrl.text.trim(),
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          primaryCategory: _selectedCategory,
          homeBaseLocation: _locationCtrl.text.trim().isEmpty
              ? null
              : _locationCtrl.text.trim(),
        );

    if (!mounted) return;

    final err = ref.read(clubsNotifierProvider);
    err.whenOrNull(
      error: (e, _) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      ),
    );

    if (clubId != null) {
      ref.invalidate(clubsListProvider);
      context.go('/clubs/$clubId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(clubsNotifierProvider) is AsyncLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Club')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Club Name *',
                    prefixIcon: Icon(Icons.groups_outlined),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Primary Category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Select category')),
                    ...AppConstants.eventCategories.map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child:
                            Text(AppConstants.formatCategoryLabel(c)),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedCategory = v),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _locationCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Home Base Location',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    hintText: 'e.g., Oakland, CA',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    prefixIcon: Icon(Icons.description_outlined),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: saving ? null : _submit,
                  child: saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Club'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
