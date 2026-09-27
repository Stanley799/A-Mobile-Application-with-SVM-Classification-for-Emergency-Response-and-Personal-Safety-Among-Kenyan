import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color background = Color(0xFFFAF8F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF5F2EE);

  static const Color brand = Color(0xFF0F766E);
  static const Color brandLight = Color(0xFFE6F4F2);
  static const Color brandMid = Color(0xFF5EAAA8);

  static const Color sos = Color(0xFFD94A4A);
  static const Color sosDeep = Color(0xFFB33A3A);
  static const Color sosLight = Color(0xFFFDECEC);

  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color warning = Color(0xFFE65100);
  static const Color warningLight = Color(0xFFFFF3E0);
  static const Color warningText = Color(0xFF9C3700);
  static const Color info = Color(0xFF1565C0);
  static const Color infoLight = Color(0xFFE3F2FD);
  static const Color neutral = Color(0xFF616161);
  static const Color neutralLight = Color(0xFFF0F0F0);

  static const Color medicalBg = Color(0xFFE8F5E9);
  static const Color medicalFg = Color(0xFF2E7D32);
  static const Color roadBg = Color(0xFFE3F2FD);
  static const Color roadFg = Color(0xFF1565C0);
  static const Color fireBg = Color(0xFFFFF3E0);
  static const Color fireFg = Color(0xFFE65100);
  static const Color securityBg = Color(0xFFF3E5F5);
  static const Color securityFg = Color(0xFF6A1B9A);
  static const Color abductionBg = Color(0xFFFFEBEE);
  static const Color abductionFg = Color(0xFFAD1457);
  static const Color otherBg = Color(0xFFF5F5F5);
  static const Color otherFg = Color(0xFF616161);

  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF5F5F5F);
  static const Color textTertiary = Color(0xFF6B6B6B);
  static const Color divider = Color(0xFFEBE6E0);
  static const Color transparent = Color(0x00000000);
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double full = 999;
}

class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> sosGlow = [
    BoxShadow(color: Color(0x33D94A4A), blurRadius: 40, spreadRadius: 4),
  ];

  static const List<BoxShadow> navigation = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, -4)),
  ];
}

class AppTheme {
  static ThemeData get data {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      primary: AppColors.brand,
      surface: AppColors.surface,
    ).copyWith(error: AppColors.sosDeep);
    final textTheme = GoogleFonts.interTextTheme().apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      textTheme: textTheme.copyWith(
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        bodySmall: textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: AppColors.textTertiary,
        ),
      ),
      useMaterial3: true,
    );
  }
}
