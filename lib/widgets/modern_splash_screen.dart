import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ModernSplashScreen extends StatelessWidget {
  final bool embedded;
  final bool animateIntro;
  final bool showLoading;

  const ModernSplashScreen({
    super.key,
    this.embedded = false,
    this.animateIntro = true,
    this.showLoading = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget brandContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 90,
          height: 90,
          child: Image.asset(
            'assets/logo/Agenix.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.auto_awesome_rounded,
              size: 46,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'AGENIX',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            letterSpacing: 2.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Plan faster. Flow smarter.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurface),
        ),
        if (showLoading) ...[
          const SizedBox(height: 24),
          const SizedBox(
            width: 120,
            child: LinearProgressIndicator(minHeight: 2.2),
          ),
        ],
      ],
    );

    if (animateIntro) {
      brandContent = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.98, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: brandContent,
      );
    }

    final content = Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B0C0F), Color(0xFF101826), Color(0xFF1A1711)],
            ),
          ),
        ),
        Center(child: brandContent),
      ],
    );

    if (embedded) {
      return content;
    }

    return Scaffold(body: content);
  }
}
