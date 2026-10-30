import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../features/auth/models/auth_models.dart';

/// Requests only the operating-system permissions required by each app role.
class PermissionService {
  bool _hasRequestedResidentPermissions = false;
  bool _hasRequestedResponderPermissions = false;

  /// Requests permissions needed by [role] on supported mobile platforms.
  Future<void> requestForRole(UserRole role) async {
    // Web and desktop platforms do not use the mobile permission prompts.
    if (kIsWeb || !_isMobileTarget) {
      return;
    }

    if (role == UserRole.responder) {
      if (_hasRequestedResponderPermissions) {
        return;
      }
      // Set the guard before awaiting so repeated auth notifications do not prompt twice.
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
