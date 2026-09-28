import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user_profile.dart';
import '../models/auth_models.dart';
import '../models/responder_profile.dart';

/// Holds validated fields required to create a resident or responder account.
class RegistrationInput {
  const RegistrationInput({
    required this.firstName,
    required this.lastName,
    required this.dateOfBirth,
    required this.gender,
    required this.phoneNumber,
    required this.email,
    required this.password,
    required this.role,
    required this.preferredLanguage,
    required this.consentCrossBorderTransfer,
    this.organizationName,
    this.organizationType,
    this.registrationNumber,
    this.serviceArea,
  });

  final String firstName;
  final String lastName;
  final DateTime dateOfBirth;
  final String gender;
  final String phoneNumber;
  final String email;
  final String password;
  final UserRole role;
  final PreferredLanguage preferredLanguage;
  final bool consentCrossBorderTransfer;
  final String? organizationName;
  final OrganizationType? organizationType;
  final String? registrationNumber;
  final String? serviceArea;
}

/// Contains the Firebase user returned after successful sign-in.
class SignInResult {
  const SignInResult({required this.user});

  final User user;
}

/// Coordinates Firebase Authentication with the application's user documents.
class AuthRepository {
  AuthRepository({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  /// Emits the current Firebase user whenever authentication changes.
  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  /// Signs out the current Firebase user.
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  /// Creates authentication and profile records for [input].
  Future<void> register(RegistrationInput input) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: input.email.trim(),
      password: input.password,
    );

    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-created',
        message: 'Unable to create account. Please try again.',
      );
    }

    final now = FieldValue.serverTimestamp();
    final accountStatus = input.role == UserRole.responder
        ? AccountStatus.pendingVerification
        : AccountStatus.active;

    final userDoc = {
      'userId': user.uid,
      'firstName': input.firstName.trim(),
      'lastName': input.lastName.trim(),
      'dateOfBirth': Timestamp.fromDate(
        DateTime(input.dateOfBirth.year, input.dateOfBirth.month, input.dateOfBirth.day),
      ),
      'gender': input.gender.trim(),
      'phoneNumber': input.phoneNumber.trim(),
      'email': input.email.trim(),
      'role': input.role.firestoreValue,
      'preferredLanguage': input.preferredLanguage.firestoreValue,
      'accountStatus': accountStatus.firestoreValue,
      'consentCrossBorderTransfer': input.consentCrossBorderTransfer,
      'createdAt': now,
      'updatedAt': now,
      'lastLoginAt': now,
    };

    // Commit the user and responder records together so registration is consistent.
    final batch = _firestore.batch();
    final userRef = _firestore.collection('users').doc(user.uid);
    batch.set(userRef, userDoc);

    if (input.role == UserRole.responder) {
      final responderRef = _firestore.collection('responders').doc(user.uid);
      batch.set(responderRef, {
        'responderId': user.uid,
        'organizationName': input.organizationName?.trim() ?? '',
        'organizationType': input.organizationType?.firestoreValue ?? 'Other',
        'registrationNumber': input.registrationNumber?.trim() ?? '',
        'verificationStatus': ResponderVerificationStatus.pending.firestoreValue,
        'verificationNotes': null,
        'verifiedBy': null,
        'verifiedAt': null,
        'availabilityStatus': AvailabilityStatus.offline.firestoreValue,
        'currentLatitude': null,
        'currentLongitude': null,
        'serviceArea': input.serviceArea?.trim() ?? 'Unspecified',
        'createdAt': now,
        'updatedAt': now,
      });
    }

    await batch.commit();

    // Refresh the token so server-assigned custom claims are available immediately.
    await user.getIdToken(true);
  }

  /// Authenticates a user and updates their last-login timestamp.
  Future<SignInResult> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No account found for this email.',
      );
    }

    await _firestore.collection('users').doc(user.uid).update({
      'lastLoginAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Refresh the token before role-based routing reads server-assigned claims.
    await user.getIdToken(true);

    return SignInResult(user: user);
  }

  /// Loads the user's role and account state, or null when no profile exists.
  Future<AppUserProfile?> getUserProfile(String userId) async {
    final snapshot = await _firestore.collection('users').doc(userId).get();
    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }
    return AppUserProfile.fromMap(snapshot.data()!);
  }

  /// Loads responder verification details, or null when no record exists.
  Future<ResponderProfile?> getResponderProfile(String userId) async {
    final snapshot = await _firestore.collection('responders').doc(userId).get();
    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }
    return ResponderProfile.fromMap(snapshot.data()!);
  }

  /// Maps Firebase sign-in failures to messages suitable for the sign-in form.
  String mapSignInError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email address.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Unable to sign in at the moment. Please try again.';
    }
  }
}
