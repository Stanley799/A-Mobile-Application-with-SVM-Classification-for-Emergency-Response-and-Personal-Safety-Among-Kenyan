import 'package:go_router/go_router.dart';

import '../features/admin/admin_shell.dart';
import '../features/auth/models/auth_models.dart';
import '../features/auth/screens/create_account_screen.dart';
import '../features/auth/screens/sign_in_screen.dart';
import '../features/ops/ops_shell.dart';
import '../features/resident/screens/home_screen.dart';
import '../features/responder/responder_shell.dart';
import '../features/home/screens/placeholder_screens.dart';
import 'auth_state_controller.dart';

/// Builds role-aware routes and gates responders and dispatchers by approval state.
GoRouter buildRouter(AuthStateController authState) {
  return GoRouter(
    initialLocation: '/sign-in',
    refreshListenable: authState,
    redirect: (context, state) {
      final isLoading = authState.isLoading;
      if (isLoading) {
        return state.matchedLocation == '/loading' ? null : '/loading';
      }

      final user = authState.firebaseUser;
      final location = state.matchedLocation;

      if (user == null) {
        if (location == '/sign-in' || location == '/create-account') {
          return null;
        }
        return '/sign-in';
      }

      if (authState.isSystemAdmin) {
        return location == '/dispatch-console' ? null : '/dispatch-console';
      }

      final profile = authState.profile;
      if (profile == null) {
        return '/loading';
      }

      final role = profile.role;
      if (role == UserRole.resident) {
        return location == '/home' ? null : '/home';
      }

      if (role == UserRole.dispatcher) {
        // The claim, not the profile field, opens the console. Until an administrator
        // approves the application the person sees the waiting or decision screen.
        if (!authState.isDispatcher) {
          final decision = authState.staffDecision;
          if (decision?.rejected == true) {
            return location == '/registration-rejected' ? null : '/registration-rejected';
          }
          if (decision?.suspended == true) {
            return location == '/account-suspended' ? null : '/account-suspended';
          }
          return location == '/pending-verification' ? null : '/pending-verification';
        }
        return location == '/dispatch-console' ? null : '/dispatch-console';
      }

      final responder = authState.responderProfile;
      if (responder == null) {
        return '/pending-verification';
      }

      switch (responder.verificationStatus) {
        case ResponderVerificationStatus.verified:
          return location == '/responder-home' ? null : '/responder-home';
        case ResponderVerificationStatus.pending:
          return location == '/pending-verification' ? null : '/pending-verification';
        case ResponderVerificationStatus.rejected:
          return location == '/registration-rejected' ? null : '/registration-rejected';
        case ResponderVerificationStatus.suspended:
          return location == '/account-suspended' ? null : '/account-suspended';
      }
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder: (context, state) => const LoadingScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/create-account',
        builder: (context, state) => const CreateAccountScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const ResidentHomeScreen(),
      ),
      GoRoute(
        path: '/responder-home',
        builder: (context, state) => const ResponderGate(),
      ),
      GoRoute(
        path: '/pending-verification',
        builder: (context, state) =>
            PendingVerificationScreen(staff: authState.profile?.role == UserRole.dispatcher),
      ),
      GoRoute(
        path: '/registration-rejected',
        builder: (context, state) {
          final notes = authState.profile?.role == UserRole.dispatcher
              ? authState.staffDecision?.reason
              : authState.responderProfile?.verificationNotes;
          return RegistrationRejectedScreen(verificationNotes: notes);
        },
      ),
      GoRoute(
        path: '/account-suspended',
        builder: (context, state) =>
            AccountSuspendedScreen(staff: authState.profile?.role == UserRole.dispatcher),
      ),
      GoRoute(
        path: '/dispatch-console',
        builder: (context, state) => OpsShell(isAdmin: authState.isSystemAdmin),
      ),
      GoRoute(
        path: '/admin-dashboard',
        builder: (context, state) => const AdminShell(),
      ),
    ],
  );
}
