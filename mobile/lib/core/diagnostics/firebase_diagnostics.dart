import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Prints which Firebase app and key this build uses. Debug builds only.
/// Shows only the LAST 4 characters of the key so nothing secret leaks.
void logFirebaseDiagnostics() {
  if (!kDebugMode) return;
  try {
    final o = Firebase.app().options;
    final key = o.apiKey;
    final end = key.length >= 4 ? key.substring(key.length - 4) : '????';
    debugPrint('FIREBASE project=${o.projectId} appId=${o.appId} apiKeyEnds=$end');
  } catch (e) {
    debugPrint('FIREBASE diagnostics failed: ${e.runtimeType}');
  }
}
