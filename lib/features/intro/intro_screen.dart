import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'widgets/animated_box_cube.dart';

/// Écran d'ACCUEIL, affiché AVANT l'onboarding au premier lancement :
/// identité (logo + cube animé), puis l'utilisateur BALAYE VERS LE HAUT
/// pour démarrer. Aucune fausse action : le balayage et le chevron
/// déclenchent tous deux la suite (§27).
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onStart});

  /// Appelé UNE FOIS quand l'utilisateur demande à démarrer (balayage
  /// vers le haut ou appui sur l'indication).
  final VoidCallback onStart;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _hint = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  double _dragDelta = 0;
  bool _started = false;

  @override
  void dispose() {
    _hint.dispose();
    super.dispose();
  }

  void _start() {
    if (_started) return;
    _started = true;
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (DragUpdateDetails details) {
          _dragDelta += details.delta.dy;
          if (_dragDelta < -36) _start();
        },
        onVerticalDragEnd: (DragEndDetails details) {
          _dragDelta = 0;
          final double velocity = details.primaryVelocity ?? 0;
          if (velocity < -260) _start();
        },
        child: SafeArea(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.surface.withValues(alpha: 0.55), AppColors.background],
              ),
            ),
            child: Column(
              children: [
                const Spacer(flex: 3),
                _LogoMark(),
                const SizedBox(height: 20),
                Text(
                  'AnimeBox',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Vos animés, organisés — directement depuis Telegram.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13, color: AppColors.textSecondary),
                ),
                const Spacer(flex: 1),
                const AnimatedBoxCube(size: 170),
                const Spacer(flex: 3),
                _SwipeHint(animation: _hint, onTap: _start),
                const SizedBox(height: 34),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo de l'application (asset généré — pas un emoji ni un placeholder).
class _LogoMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.22), blurRadius: 28, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.asset(
          'assets/img/app_logo.png',
          fit: BoxFit.cover,
          errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
              ColoredBox(color: AppColors.surfaceAlt),
        ),
      ),
    );
  }
}

/// Indication « Balayer vers le haut » avec chevron flottant animé — zone
/// entièrement tactile (même action que le balayage).
class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.animation, required this.onTap});

  final Animation<double> animation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Balayer vers le haut pour démarrer',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: animation,
                builder: (BuildContext context, Widget? child) {
                  final double lift = -8 * Curves.easeOut.transform((animation.value * 2).clamp(0.0, 1.0))
                      + 8 * Curves.easeIn.transform((animation.value * 2 - 1).clamp(0.0, 1.0));
                  return Transform.translate(
                    offset: Offset(0, lift),
                    child: Opacity(
                      opacity: 1 - 0.45 * Curves.easeInOut.transform(animation.value),
                      child: Icon(Icons.keyboard_double_arrow_up_rounded, size: 30, color: AppColors.primaryBright),
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              Text(
                'Balayer vers le haut',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary, letterSpacing: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
