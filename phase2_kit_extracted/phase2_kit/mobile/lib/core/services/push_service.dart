// Stores this phone's push token so the dispatch function can wake the responder app. Never throws.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class PushService {
  static bool _listening = false;

  static Future<void> init() async {
    try {
      if (kIsWeb) return; // web push needs a VAPID key; the responder app is meant for phones
      final m = FirebaseMessaging.instance;
      await m.requestPermission(alert: true, sound: true, badge: true);
      final token = await m.getToken();
      if (token != null) await _save(token);
      if (!_listening) {
        _listening = true;
        m.onTokenRefresh.listen(_save);
      }
    } catch (e) {
      debugPrint('Push setup skipped: ${e.runtimeType}');
    }
  }

  static Future<void> _save(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('deviceTokens').doc(uid).set({
      'token': token,
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
