import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../features/auth/models/app_user_profile.dart';
import '../features/auth/models/auth_models.dart';
import '../features/auth/models/responder_profile.dart';
import '../features/auth/services/auth_repository.dart';
import 'permission_service.dart';

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
  bool _loading = true;

  User? get firebaseUser => _firebaseUser;
  AppUserProfile? get profile => _profile;
  ResponderProfile? get responderProfile => _responderProfile;
  bool get isLoading => _loading;

  Future<void> _onAuthChanged(User? user) async {
    _loading = true;
    _firebaseUser = user;
    _profile = null;
    _responderProfile = null;
    notifyListeners();

    if (user != null) {
      try {
        _profile = await authRepository.getUserProfile(user.uid);
        if (_profile?.role.firestoreValue == 'Responder') {
          _responderProfile = await authRepository.getResponderProfile(user.uid);
        }
        if (_profile != null) {
          await permissionService.requestForRole(_profile!.role);
        }
      } on FirebaseException {
        _profile = null;
        _responderProfile = null;
      }
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    await _onAuthChanged(authRepository.currentUser);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
