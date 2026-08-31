import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Boîte grise de squelette (placeholder de chargement).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 16, this.radius = 10});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Enveloppe pulsante (opacité animée) pour les squelettes de chargement.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) =>
          Opacity(opacity: 0.45 + 0.4 * _controller.value, child: child),
      child: widget.child,
    );
  }
}

/// Squelette de carte de source (liste « Mes sources »).
class SourceCardSkeleton extends StatelessWidget {
  const SourceCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              SkeletonBox(width: 46, height: 46, radius: 14),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 14, width: 120)),
            ],
          ),
          const SizedBox(height: 14),
          const SkeletonBox(height: 12, width: 170),
          const SizedBox(height: 12),
          Row(
            children: const [
              SkeletonBox(width: 70, height: 13),
              SizedBox(width: 14),
              SkeletonBox(width: 70, height: 13),
              SizedBox(width: 14),
              SkeletonBox(width: 70, height: 13),
            ],
          ),
        ],
      ),
    );
  }
}

/// Squelette de ligne de publication (écran « Publications récentes »).
class PublicationSkeleton extends StatelessWidget {
  const PublicationSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const SkeletonBox(width: 40, height: 40, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(height: 13, width: 110),
                SizedBox(height: 8),
                SkeletonBox(height: 11, width: 220),
                SizedBox(height: 8),
                SkeletonBox(height: 11, width: 160),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
