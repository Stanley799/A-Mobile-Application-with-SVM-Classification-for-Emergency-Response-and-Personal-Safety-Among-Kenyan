import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class CategoryStyle {
  const CategoryStyle({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
}

CategoryStyle categoryStyle(String category) {
  switch (category) {
    case 'Medical Emergency':
      return const CategoryStyle(
        icon: Icons.medical_services,
        background: AppColors.medicalBg,
        foreground: AppColors.medicalFg,
      );
    case 'Road Accident':
      return const CategoryStyle(
        icon: Icons.directions_car,
        background: AppColors.roadBg,
        foreground: AppColors.roadFg,
      );
    case 'Fire & Rescue':
      return const CategoryStyle(
        icon: Icons.local_fire_department,
        background: AppColors.fireBg,
        foreground: AppColors.fireFg,
      );
    case 'Security Threat':
      return const CategoryStyle(
        icon: Icons.shield,
        background: AppColors.securityBg,
        foreground: AppColors.securityFg,
      );
    case 'Abduction':
      return const CategoryStyle(
        icon: Icons.person_search,
        background: AppColors.abductionBg,
        foreground: AppColors.abductionFg,
      );
    case 'Other / General':
    default:
      return const CategoryStyle(
        icon: Icons.more_horiz,
        background: AppColors.otherBg,
        foreground: AppColors.otherFg,
      );
  }
}
