import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../features/telegram/data/models/source_status.dart';

/// Pastille de statut d'une source : Actif (vert), Synchronisation
/// (bleu, pulsant), Erreur (rouge), Désactivé (gris).
class SourceStatusIndicator extends StatelessWidget {
  const SourceStatusIndicator({super.key, required this.status, this.labelVisible = true});

  final SourceStatus status;
  final bool labelVisible;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      SourceStatus.active => AppColors.success,
      SourceStatus.syncing => AppColors.primaryBright,
      SourceStatus.error => AppColors.danger,
      SourceStatus.disabled => AppColors.textMuted,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(color: color, pulsing: status == SourceStatus.syncing),
        if (labelVisible) ...[
          const SizedBox(width: 7),
          Text(
            status.label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ],
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pulsing) {
      return Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.7), blurRadius: 6 + 8 * _controller.value, spreadRadius: 2 * _controller.value)],
          ),
        );
      },
    );
  }
}
