import 'auth_models.dart';

class AppUserProfile {
  const AppUserProfile({
    required this.userId,
    required this.role,
    required this.accountStatus,
  });

  final String userId;
  final UserRole role;
  final AccountStatus accountStatus;

  factory AppUserProfile.fromMap(Map<String, dynamic> data) {
    final role = UserRoleX.fromFirestore((data['role'] as String?) ?? 'Resident');
    final accountStatusRaw = (data['accountStatus'] as String?) ?? 'Active';

    final accountStatus = switch (accountStatusRaw) {
      'Active' => AccountStatus.active,
      'PendingVerification' => AccountStatus.pendingVerification,
      'Suspended' => AccountStatus.suspended,
      _ => AccountStatus.active,
    };

    return AppUserProfile(
      userId: (data['userId'] as String?) ?? '',
      role: role,
      accountStatus: accountStatus,
    );
  }
}
