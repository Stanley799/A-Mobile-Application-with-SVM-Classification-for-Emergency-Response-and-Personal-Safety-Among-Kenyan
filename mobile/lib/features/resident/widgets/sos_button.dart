import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class SosButton extends StatefulWidget {
  const SosButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 224,
    child: Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Transform.scale(
            scale: 1 + (_controller.value * 0.08),
            child: child,
          ),
          child: Container(
            width: 204,
            height: 204,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: AppShadows.sosGlow,
            ),
          ),
        ),
        SizedBox.square(
          dimension: 200,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.sos, AppColors.sosDeep],
              ),
              boxShadow: AppShadows.sosGlow,
            ),
            child: Material(
              color: AppColors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onPressed,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.health_and_safety,
                      color: AppColors.surface,
                      size: 52,
                    ),
                    SizedBox(height: AppSpacing.sm),
                    Text(
                      'SOS',
                      style: TextStyle(
                        color: AppColors.surface,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      ),
                    ),
                    SizedBox(height: AppSpacing.xs),
                    Text(
                      'Report Emergency',
                      style: TextStyle(
                        color: AppColors.surface.withValues(alpha: 0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
