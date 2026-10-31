import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_error_text.dart';

void main() {
  group('friendlyAuthError', () {
    test('every wrong-credential code gives the same plain sentence', () {
      for (final code in [
        'user-not-found',
        'wrong-password',
        'invalid-credential',
        'invalid-login-credentials',
      ]) {
        expect(
          friendlyAuthError(FirebaseAuthException(code: code)),
          'The email or password is not correct. Please try again.',
          reason: code,
        );
      }
    });

    test('no internet and existing account have their own sentences', () {
      expect(
        friendlyAuthError(FirebaseAuthException(code: 'network-request-failed')),
        'No internet connection. Please check your data or Wi-Fi.',
      );
      expect(
        friendlyAuthError(FirebaseAuthException(code: 'email-already-in-use')),
        'An account with this email already exists. Try signing in.',
      );
    });

    test('an unknown Firebase code falls back to a safe sentence', () {
      expect(
        friendlyAuthError(FirebaseAuthException(code: 'something-new')),
        'Something went wrong while signing in. Please try again.',
      );
    });

    test('a non-Firebase error never leaks its raw text', () {
      final text = friendlyAuthError(Exception('secret internal detail'));
      expect(text, 'Something went wrong. Please try again.');
      expect(text.contains('secret'), isFalse);
    });

    test('authErrorCode gives the short support code', () {
      expect(authErrorCode(FirebaseAuthException(code: 'weak-password')), 'weak-password');
      expect(authErrorCode(Exception('x')), 'unknown');
    });
  });
}
