import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../features/auth/models/auth_models.dart';

class PermissionService {
  bool _hasRequestedResidentPermissions = false;
  bool _hasRequestedResponderPermissions = false;

  Future<void> requestForRole(UserRole role) async {
    if (kIsWeb || !_isMobileTarget) {
      return;
    }

    if (role == UserRole.responder) {
      if (_hasRequestedResponderPermissions) {
        return;
      }
      _hasRequestedResponderPermissions = true;
      await [Permission.notification, Permission.locationWhenInUse].request();
      return;
    }

    if (role == UserRole.resident) {
      if (_hasRequestedResidentPermissions) {
        return;
      }
      _hasRequestedResidentPermissions = true;
      await Permission.notification.request();
    }
  }

  bool get _isMobileTarget {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
