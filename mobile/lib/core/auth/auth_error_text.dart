import 'package:firebase_auth/firebase_auth.dart';

/// Turns any sign-in or sign-up error into a short, plain sentence.
/// Never show raw exception text to a person.
String friendlyAuthError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-email':
        return 'That email address does not look right. Please check it.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'The email or password is not correct. Please try again.';
      case 'email-already-in-use':
        return 'An account with this email already exists. Try signing in.';
      case 'weak-password':
        return 'Please choose a stronger password (at least 8 characters).';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'network-request-failed':
        return 'No internet connection. Please check your data or Wi-Fi.';
      case 'operation-not-allowed':
        return 'Sign-in with email is not switched on yet. Please contact support.';
      case 'internal-error':
      case 'invalid-api-key':
      case 'app-not-authorized':
        return 'We could not reach the sign-in service. Please try again in a moment.';
      default:
        return 'Something went wrong while signing in. Please try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}

/// Short code for support, safe to show in small grey text under the message.
String authErrorCode(Object error) =>
    error is FirebaseAuthException ? error.code : 'unknown';
