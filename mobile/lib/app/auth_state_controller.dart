import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../features/auth/models/app_user_profile.dart';
import '../features/auth/models/auth_models.dart';
import '../features/auth/models/responder_profile.dart';
import '../features/auth/services/auth_repository.dart';
import 'permission_service.dart';

/// Keeps Firebase identity, Firestore profiles, and loading state in sync.
class AuthStateController extends ChangeNotifier {
  AuthStateController({
    required this.authRepository,
    required this.permissionService,
  }) {
    _authSubscription = authRepository.authStateChanges().listen(_onAuthChanged);
  }

  final AuthRepository authRepository;
  final PermissionService permissionService;

  StreamSubscription<User?>? _authSubscription;

  User? _firebaseUser;
  AppUserProfile? _profile;
  ResponderProfile? _responderProfile;
  StaffDecision? _staffDecision;
  bool _isSystemAdmin = false;
  bool _isDispatcher = false;
  bool _loading = true;

  User? get firebaseUser => _firebaseUser;
  AppUserProfile? get profile => _profile;
  ResponderProfile? get responderProfile => _responderProfile;
  StaffDecision? get staffDecision => _staffDecision;
  bool get isSystemAdmin => _isSystemAdmin;
  bool get isDispatcher => _isDispatcher;
  bool get isLoading => _loading;

  Future<void> _onAuthChanged(User? user) async {
    _loading = true;
    _firebaseUser = user;
    // Clear the previous account's role data before asynchronous profile reads.
    _profile = null;
    _responderProfile = null;
    _staffDecision = null;
    _isSystemAdmin = false;
    _isDispatcher = false;
    notifyListeners();

    if (user != null) {
      try {
        final tokenResult = await user.getIdTokenResult(true);
        _isSystemAdmin = tokenResult.claims?['role'] == 'SystemAdmin';
        _isDispatcher = tokenResult.claims?['role'] == 'Dispatcher';

        _profile = await authRepository.getUserProfile(user.uid);
        if (_profile?.role.firestoreValue == 'Responder') {
          _responderProfile = await authRepository.getResponderProfile(user.uid);
        }
        if (_profile?.role.firestoreValue == 'Dispatcher') {
          _staffDecision = await authRepository.getStaffDecision(user.uid);
        }
        if (_profile != null && !_isSystemAdmin) {
          await permissionService.requestForRole(_profile!.role);
        }
      } on FirebaseException {
        _isSystemAdmin = false;
        _isDispatcher = false;
        _profile = null;
        _responderProfile = null;
        _staffDecision = null;
      }
    }

    _loading = false;
    notifyListeners();
  }

  /// Reloads the current user's profile after registration or sign-in.
  Future<void> refresh() async {
    await _onAuthChanged(authRepository.currentUser);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
