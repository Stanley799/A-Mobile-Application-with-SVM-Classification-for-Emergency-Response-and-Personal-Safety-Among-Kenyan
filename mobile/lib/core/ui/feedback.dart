// Toasts and error wording. Rule for the whole app: a person never sees a raw exception, and nothing fails silently.
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

enum ToastKind { info, success, error }

class AppToast {
  AppToast._();

  static void show(BuildContext context, String message, {ToastKind kind = ToastKind.info, Duration? duration}) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    final (icon, color) = switch (kind) {
      ToastKind.success => (Icons.check_circle, const Color(0xFF7BD88F)),
      ToastKind.error => (Icons.error_outline, const Color(0xFFFFB4A9)),
      ToastKind.info => (Icons.info_outline, const Color(0xFFBFD9FF)),
    };
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      backgroundColor: Tk.ink,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      duration: duration ?? Duration(seconds: kind == ToastKind.error ? 5 : 3),
      content: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35, fontWeight: FontWeight.w600))),
      ]),
    ));
  }
}

/// Plain-language text for anything that can go wrong. Never returns a stack trace, a class name or a Firebase code.
String friendlyError(Object e) {
  if (e is TimeoutException) return 'That took too long. Check your connection and try again.';
  if (e is FirebaseException) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-login-credentials':
        return 'Email or password is not right. Check them and try again.';
      case 'invalid-email':
        return 'That email address does not look right.';
      case 'email-already-in-use':
        return 'An account with this email already exists. Try signing in.';
      case 'weak-password':
        return 'Choose a stronger password (at least 8 characters).';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a few minutes and try again.';
      case 'network-request-failed':
      case 'unavailable':
        return 'No connection. Check your internet and try again.';
      case 'permission-denied':
        return 'You do not have permission to do that.';
      case 'unauthenticated':
        return 'Please sign in again.';
      case 'deadline-exceeded':
        return 'That took too long. Try again.';
      case 'not-found':
        return 'We could not find that. It may have been removed.';
      case 'resource-exhausted':
        return 'Too many requests right now. Try again shortly.';
      case 'failed-precondition':
      case 'invalid-argument':
        final m = e.message;
        if (m != null && m.isNotEmpty && m.length < 140 && !m.contains('Exception') && !m.contains('firebase')) return m;
        return 'We could not complete that. Please check the details and try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}

/// Runs [task]; on failure shows a friendly toast and returns null. Use for any button action that is not inside an AppButton's own error handling.
Future<T?> withFeedback<T>(BuildContext context, Future<T> Function() task, {String? errorMessage, String? successMessage}) async {
  try {
    final r = await task();
    if (successMessage != null && context.mounted) AppToast.show(context, successMessage, kind: ToastKind.success);
    return r;
  } catch (e) {
    if (context.mounted) AppToast.show(context, errorMessage ?? friendlyError(e), kind: ToastKind.error);
    return null;
  }
}
