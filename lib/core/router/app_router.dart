import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/shell/main_shell.dart';
import '../../features/admin/screens/admin_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/clubs/screens/club_detail_screen.dart';
import '../../features/clubs/screens/clubs_list_screen.dart';
import '../../features/clubs/screens/create_club_screen.dart';
import '../../features/events/screens/create_event_screen.dart';
import '../../features/events/screens/event_detail_screen.dart';
import '../../features/events/screens/rsvp_attendees_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/reviews/screens/submit_review_screen.dart';

// ---------------------------------------------------------------------------
// GoRouterRefreshStream — triggers re-evaluation of route guards on auth change
// ---------------------------------------------------------------------------
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<AuthState> stream) {
    notifyListeners();
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Router provider
// ---------------------------------------------------------------------------
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = GoRouterRefreshStream(
    Supabase.instance.client.auth.onAuthStateChange,
  );
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refreshListenable,
    redirect: (context, state) async {
      final session = Supabase.instance.client.auth.currentSession;
      final isLoggedIn = session != null;
      final loc = state.matchedLocation;

      // Not logged in → send to login (allow signup too)
      if (!isLoggedIn) {
        if (loc == '/login' || loc == '/signup') return null;
        return '/login';
      }

      // Logged in on auth page → go home
      if (loc == '/login' || loc == '/signup') return '/home';

      // Already heading to onboarding — allow
      if (loc == '/onboarding') return null;

      // Check profile exists; if not → onboarding
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('id')
            .eq('id', session.user.id)
            .maybeSingle();
        if (profile == null) return '/onboarding';
      } catch (_) {
        // Network error or RLS denial — stay on current page
      }

      // Guard admin route
      if (loc == '/admin') {
        try {
          final p = await Supabase.instance.client
              .from('profiles')
              .select('is_admin')
              .eq('id', session.user.id)
              .single();
          if (p['is_admin'] != true) return '/home';
        } catch (_) {
          return '/home';
        }
      }

      return null;
    },
    routes: [
      // ── Auth ────────────────────────────────────────────────────────
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        name: 'signup',
        builder: (_, __) => const SignupScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),

      // ── Admin ────────────────────────────────────────────────────────
      GoRoute(
        path: '/admin',
        name: 'admin',
        builder: (_, __) => const AdminScreen(),
      ),

      // ── Events (outside shell — no bottom nav) ─────────────────────
      GoRoute(
        path: '/events/create',
        name: 'create-event',
        builder: (_, __) => const CreateEventScreen(),
      ),
      GoRoute(
        path: '/events/:id/rsvps',
        name: 'event-rsvps',
        builder: (_, state) =>
            RsvpAttendeesScreen(eventId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/events/:id/review',
        name: 'submit-review',
        builder: (_, state) =>
            SubmitReviewScreen(eventId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/events/:id',
        name: 'event-detail',
        builder: (_, state) =>
            EventDetailScreen(eventId: state.pathParameters['id']!),
      ),

      // ── Clubs (outside shell) ────────────────────────────────────────
      GoRoute(
        path: '/clubs/create',
        name: 'create-club',
        builder: (_, __) => const CreateClubScreen(),
      ),
      GoRoute(
        path: '/clubs/:id',
        name: 'club-detail',
        builder: (_, state) =>
            ClubDetailScreen(clubId: state.pathParameters['id']!),
      ),

      // ── Main shell with bottom nav ──────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            builder: (_, __) => const HomeScreen(),
          ),
          GoRoute(
            path: '/clubs',
            name: 'clubs',
            builder: (_, __) => const ClubsListScreen(),
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (_, __) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  );
});
