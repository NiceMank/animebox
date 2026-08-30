import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Bouton principal de l'application (dégradé violet, animation de pression).
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.outlined = false,
    this.compact = false,
    this.expanded = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  /// Variante secondaire (bordure violette sur fond sombre).
  final bool outlined;
  final bool compact;
  final bool expanded;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    final Color foreground = widget.outlined ? AppColors.primaryBright : Colors.white;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: BoxConstraints(minHeight: widget.compact ? 42 : 50),
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 14 : 18, vertical: widget.compact ? 9 : 12),
          decoration: BoxDecoration(
            gradient: widget.outlined ? null : const LinearGradient(colors: AppColors.primaryGradient),
            color: widget.outlined ? AppColors.surface : null,
            borderRadius: BorderRadius.circular(16),
            border: widget.outlined ? Border.all(color: AppColors.primary.withValues(alpha: 0.5)) : null,
            boxShadow: widget.outlined
                ? null
                : [BoxShadow(color: AppColors.primary.withValues(alpha: 0.32), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: widget.compact ? 16 : 18, color: foreground),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: widget.compact ? 13 : 14, fontWeight: FontWeight.w700, color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
