import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../shared/widgets/carousel_indicator.dart';
import '../../shared/widgets/primary_button.dart';
import 'models/onboarding_page_data.dart';
import 'widgets/onboarding_illustrations.dart';

/// Onboarding AnimeBox — EXACTEMENT 3 écrans (prompt 13).
///
/// Écran purement visuel : la fin du parcours (« Commencer ») et « Passer »
/// sont délégués à l'appelant (séparation UI/logique, §7) — ici aucune
/// écriture de préférence ni navigation globale.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onStart, required this.onSkip});

  /// « Commencer » (écran 3) — l'appelant valide l'état et lance le
  /// vrai parcours (connexion Telegram existante, prompt 13 §5).
  final VoidCallback onStart;

  /// « Passer » — l'utilisateur valide l'onboarding sans être forcé
  /// dans le parcours Telegram (logique existante respectée, §5).
  final VoidCallback onSkip;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  int _page = 0;

  int get _lastIndex => kOnboardingPages.length - 1;

  @override
  void dispose() {
    _pulse.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_page >= _lastIndex) {
      widget.onStart();
      return;
    }
    _pageController.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  void _skip() {
    // Ramener visuellement à la fin n'a pas de sens : « Passer » valide
    // immédiatement le parcours (même état final que « Commencer »).
    widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: <Widget>[
          // Barre supérieure : « Passer » (maquettes) — zone tactile ≥ 40.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
            child: Row(children: <Widget>[
              const Spacer(),
              TextButton(
                onPressed: _skip,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 40),
                  foregroundColor: AppColors.textSecondary,
                ),
                child: const Text('Passer'),
              ),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const BouncingScrollPhysics(),
              itemCount: kOnboardingPages.length,
              onPageChanged: (int page) => setState(() => _page = page),
              itemBuilder: (BuildContext context, int index) {
                return _AppearOnActivate(
                  active: _page == index,
                  child: _OnboardingPage(
                    page: kOnboardingPages[index],
                    index: index,
                    pulse: _pulse,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // Indicateur de progression — composant existant de l'app.
          CarouselIndicator(count: kOnboardingPages.length, index: _page),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            child: PrimaryButton(
              key: ValueKey<String>(_page >= _lastIndex ? 'onboarding-start' : 'onboarding-next'),
              label: _page >= _lastIndex ? 'Commencer' : 'Suivant',
              icon: Icons.chevron_right_rounded,
              onTap: _next,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Une page : illustration + titre accentué + description (+ points clés).
/// Scrollable en secours — aucun overflow sur petits écrans (§6/§14).
class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.page, required this.index, required this.pulse});

  final OnboardingPageData page;
  final int index;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    final Widget illustration = switch (index) {
      0 => const OnboardingHeroArt(),
      1 => const OnboardingCubeArt(),
      _ => const OnboardingPrivacyArt(),
    };

    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      return SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
              SizedBox(height: index == 0 ? 4 : 12),
              // Animation discrète des éléments visuels (cube / bouclier) —
              // légère, jamais excessive (§2).
              if (index == 0)
                illustration
              else
                ScaleTransition(
                  scale: Tween<double>(begin: 1, end: 1.045).animate(
                    CurvedAnimation(parent: pulse, curve: Curves.easeInOut),
                  ),
                  child: illustration,
                ),
              const SizedBox(height: 30),
              Text.rich(
                TextSpan(children: <TextSpan>[
                  TextSpan(text: page.titleTop),
                  TextSpan(
                    text: page.titleAccent,
                    style: TextStyle(color: AppColors.primaryBright),
                  ),
                ]),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 14),
              Text(
                page.description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
              if (page.bullets.isNotEmpty) ...<Widget>[
                const SizedBox(height: 22),
                for (final String bullet in page.bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(bullet, style: Theme.of(context).textTheme.bodyMedium),
                      ),
                    ]),
                  ),
              ],
              const SizedBox(height: 12),
            ]),
          ),
        ),
      );
    });
  }
}

/// Apparition douce à l'arrivée de la page (fade + léger glissement) —
/// transition professionnelle et courte (§2).
class _AppearOnActivate extends StatelessWidget {
  const _AppearOnActivate({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: active ? 1 : 0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: active ? Offset.zero : const Offset(0, 0.03),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}
