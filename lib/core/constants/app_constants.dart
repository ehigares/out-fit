/// Central constants for Out-Fit MVP.
/// All enums and allowed values live here to keep the rest of the codebase DRY.
class AppConstants {
  AppConstants._();

  // ── Event categories ──────────────────────────────────────────────
  // pickup_sport is intentionally excluded from MVP per product spec.
  // Add 'pickup_sport' here (and extend event_type enum in DB) when ready.
  static const List<String> eventCategories = [
    'running',
    'cycling',
    'hiking',
    'yoga',
    'bootcamp',
    'crossfit',
    'swimming',
    'volleyball',
    'basketball',
    'tennis',
    'other',
  ];

  // ── Intensity levels ──────────────────────────────────────────────
  static const List<String> intensityLevels = ['low', 'medium', 'high'];

  // ── Skill levels ──────────────────────────────────────────────────
  static const List<String> skillLevels = [
    'beginner',
    'intermediate',
    'advanced',
  ];

  // ── Equipment options ─────────────────────────────────────────────
  static const List<String> equipmentOptions = [
    'none',
    'yoga_mat',
    'running_shoes',
    'bike',
    'helmet',
    'weights',
    'resistance_bands',
    'jump_rope',
    'water_bottle',
  ];

  // ── Location modes ────────────────────────────────────────────────
  static const String locationModeRadius = 'radius';
  static const String locationModeCity = 'city';
  static const String locationModeState = 'state';

  // ── Defaults ──────────────────────────────────────────────────────
  static const String defaultLocationLabel = 'Bay Area, CA';
  static const int defaultRadiusMiles = 25;

  // ── Event status ──────────────────────────────────────────────────
  static const String statusDraft = 'draft';
  static const String statusPending = 'pending';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';
  static const String statusCancelled = 'cancelled';

  // ── RSVP status ───────────────────────────────────────────────────
  static const String rsvpGoing = 'going';
  static const String rsvpCancelled = 'cancelled';

  // ── Verification badge ────────────────────────────────────────────
  static const String badgeNone = 'none';
  static const String badgeVerified = 'verified';

  // ── Display helpers ───────────────────────────────────────────────
  static String formatCategoryLabel(String cat) {
    return cat[0].toUpperCase() + cat.substring(1).replaceAll('_', ' ');
  }

  static String formatPriceCents(int cents, String currency) {
    if (cents == 0) return 'Free';
    final dollars = cents / 100;
    return '\$${dollars.toStringAsFixed(dollars == dollars.truncate() ? 0 : 2)}';
  }
}
