import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/models/profile_model.dart';
import '../providers/profile_provider.dart';

/// Multi-step onboarding:
///   Step 0: 18+ gate (HARD BLOCK — cannot proceed without confirming)
///   Step 1: Name + email (pre-filled) + phone
///   Step 2: Location settings
///   Step 3: Preferences (workout, intensity, equipment)
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  final _formKey = GlobalKey<FormState>();

  // Step 0
  bool _confirmed18Plus = false;

  // Step 1
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Step 2
  String _locationMode = AppConstants.locationModeRadius;
  final _locationLabelCtrl = TextEditingController(
    text: AppConstants.defaultLocationLabel,
  );
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  int _radiusMiles = AppConstants.defaultRadiusMiles;

  // Step 3
  final Set<String> _workoutPrefs = {};
  final Set<String> _intensityPrefs = {};
  final Set<String> _equipmentPrefs = {};

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    if (user?.email != null) {
      // Email pre-filled from auth, shown read-only
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _locationLabelCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final user = Supabase.instance.client.auth.currentUser!;
    final profile = ProfileModel(
      id: user.id,
      fullName: _nameCtrl.text.trim(),
      email: user.email!,
      phonePrivate: _phoneCtrl.text.trim(),
      is18Plus: true,
      homeLocationLabel: _locationLabelCtrl.text.trim().isEmpty
          ? AppConstants.defaultLocationLabel
          : _locationLabelCtrl.text.trim(),
      locationMode: _locationMode,
      radiusMiles:
          _locationMode == AppConstants.locationModeRadius ? _radiusMiles : null,
      city: _locationMode == AppConstants.locationModeCity
          ? _cityCtrl.text.trim()
          : null,
      state: _locationMode == AppConstants.locationModeState
          ? _stateCtrl.text.trim()
          : null,
      workoutPreferences: _workoutPrefs.toList(),
      intensityPreferences: _intensityPrefs.toList(),
      equipmentPreferences: _equipmentPrefs.toList(),
      isAdmin: false,
      isTrustedHost: false,
      verificationBadge: AppConstants.badgeNone,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await ref.read(profileNotifierProvider.notifier).createProfile(profile);
    if (!mounted) return;

    final state = ref.read(profileNotifierProvider);
    state.whenOrNull(
      error: (e, _) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      ),
      data: (_) {
        ref.invalidate(currentProfileProvider);
        context.go('/home');
      },
    );
  }

  void _next() {
    if (_step == 0 && !_confirmed18Plus) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must confirm you are 18+ to continue.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_step > 0 && !_formKey.currentState!.validate()) return;
    if (_step == 3) {
      _finish();
    } else {
      setState(() => _step++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(profileNotifierProvider) is AsyncLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text('Setup — Step ${_step + 1} of 4'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: (_step + 1) / 4),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: _buildStep(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _step--),
                        child: const Text('Back'),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: saving ? null : _next,
                      child: saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_step == 3 ? 'Finish' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildStep0();
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 0: Age gate ──────────────────────────────────────────────────────
  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.verified_user, size: 64, color: Color(0xFF2E7D32)),
        const SizedBox(height: 16),
        Text(
          'Age Verification',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Out-Fit is for adults 18 and older. By continuing, you confirm that you meet this requirement.',
        ),
        const SizedBox(height: 24),
        Card(
          child: CheckboxListTile(
            value: _confirmed18Plus,
            onChanged: (v) => setState(() => _confirmed18Plus = v ?? false),
            title: const Text('I confirm I am 18 years of age or older.'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
        if (!_confirmed18Plus)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '* You must confirm your age to continue.',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }

  // ── Step 1: Name + phone ──────────────────────────────────────────────────
  Widget _buildStep1() {
    final user = Supabase.instance.client.auth.currentUser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Profile',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _nameCtrl,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Full Name *',
            prefixIcon: Icon(Icons.person_outlined),
          ),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Name is required' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: user?.email ?? '',
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Email (from your account)',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Phone Number * (private — not shown to others)',
            prefixIcon: Icon(Icons.phone_outlined),
            helperText: 'Your number is kept private and never displayed publicly.',
          ),
          validator: (v) =>
              v == null || v.trim().length < 7 ? 'Enter a valid phone number' : null,
        ),
      ],
    );
  }

  // ── Step 2: Location settings ─────────────────────────────────────────────
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Location',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        const Text('This helps us find events near you.'),
        const SizedBox(height: 24),
        TextFormField(
          controller: _locationLabelCtrl,
          decoration: const InputDecoration(
            labelText: 'Location Label (e.g., "Oakland, CA")',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
        ),
        const SizedBox(height: 16),
        const Text('How do you prefer to filter events?'),
        const SizedBox(height: 8),
        ...{
          AppConstants.locationModeRadius: 'By radius (miles from me)',
          AppConstants.locationModeCity: 'By city',
          AppConstants.locationModeState: 'By state',
        }.entries.map(
              (e) => RadioListTile<String>(
                title: Text(e.value),
                value: e.key,
                groupValue: _locationMode,
                onChanged: (v) => setState(() => _locationMode = v!),
              ),
            ),
        if (_locationMode == AppConstants.locationModeRadius) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Radius: '),
              Expanded(
                child: Slider(
                  value: _radiusMiles.toDouble(),
                  min: 5,
                  max: 100,
                  divisions: 19,
                  label: '$_radiusMiles mi',
                  onChanged: (v) => setState(() => _radiusMiles = v.toInt()),
                ),
              ),
              Text('$_radiusMiles mi'),
            ],
          ),
        ],
        if (_locationMode == AppConstants.locationModeCity) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _cityCtrl,
            decoration: const InputDecoration(labelText: 'City'),
            validator: (v) => v == null || v.trim().isEmpty ? 'Enter city' : null,
          ),
        ],
        if (_locationMode == AppConstants.locationModeState) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _stateCtrl,
            decoration: const InputDecoration(labelText: 'State (e.g., CA)'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter state' : null,
          ),
        ],
      ],
    );
  }

  // ── Step 3: Preferences ───────────────────────────────────────────────────
  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Preferences',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        const Text('Used to personalise your "For You" feed. Skip to use defaults.'),
        const SizedBox(height: 20),
        _sectionLabel('Workout Types'),
        _chipGroup(
          AppConstants.eventCategories,
          _workoutPrefs,
          (v) => setState(() {
            _workoutPrefs.contains(v) ? _workoutPrefs.remove(v) : _workoutPrefs.add(v);
          }),
        ),
        const SizedBox(height: 16),
        _sectionLabel('Intensity'),
        _chipGroup(
          AppConstants.intensityLevels,
          _intensityPrefs,
          (v) => setState(() {
            _intensityPrefs.contains(v)
                ? _intensityPrefs.remove(v)
                : _intensityPrefs.add(v);
          }),
        ),
        const SizedBox(height: 16),
        _sectionLabel('Equipment'),
        _chipGroup(
          AppConstants.equipmentOptions,
          _equipmentPrefs,
          (v) => setState(() {
            _equipmentPrefs.contains(v)
                ? _equipmentPrefs.remove(v)
                : _equipmentPrefs.add(v);
          }),
        ),
      ],
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      );

  Widget _chipGroup(
    List<String> options,
    Set<String> selected,
    void Function(String) onTap,
  ) =>
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: options
            .map(
              (o) => FilterChip(
                label: Text(AppConstants.formatCategoryLabel(o)),
                selected: selected.contains(o),
                onSelected: (_) => onTap(o),
              ),
            )
            .toList(),
      );
}
