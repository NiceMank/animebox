import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Indicateur de carousel (points animés).
class CarouselIndicator extends StatelessWidget {
  const CarouselIndicator({super.key, required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? AppColors.primary : AppColors.textMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
      ],
    );
  }
}
