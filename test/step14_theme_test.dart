import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/core/theme/app_colors.dart';
import 'package:animebox/core/theme/app_theme.dart';
import 'package:animebox/features/settings/services/app_settings.dart';
import 'package:animebox/features/local/data/local_database.dart';

/// Prompt 14 — Remplacement complet du système de couleurs (violet → bleu).
void main() {
  // ---------------------------------------------------------------------
  // 1. La palette SOMBRE est une identité BLEUE centralisée (§1-§4).
  // ---------------------------------------------------------------------

  group('Palette sombre bleue (source de vérité unique)', () {
    test('accents bleus exacts (plus aucun violet)', () {
      expect(AppColorsDark.primary, const Color(0xFF3B82F6));
      expect(AppColorsDark.primaryDark, const Color(0xFF1D4ED8));
      expect(AppColorsDark.primaryBright, const Color(0xFF93C5FD));
      expect(AppColorsDark.primary, isNot(const Color(0xFF8B5CF6))); // ancien violet
      expect(AppColorsDark.primaryDark, isNot(const Color(0xFF6C3AE8)));
      expect(AppColorsDark.primaryBright, isNot(const Color(0xFFB9A4FF)));
    });

    test('fonds très sombres, surfaces légèrement bleutées', () {
      expect(AppColorsDark.background.computeLuminance(), lessThan(0.03));
      expect(AppColorsDark.surface.computeLuminance(), lessThan(0.03));
      // bleutées : le canal bleu domine dans les surfaces
      expect(AppColorsDark.surface.b, greaterThan(AppColorsDark.surface.r));
      expect(AppColorsDark.surfaceAlt.b, greaterThan(AppColorsDark.surfaceAlt.r));
      expect(AppColorsDark.card.b, greaterThan(AppColorsDark.card.r));
      expect(AppColorsDark.bottomBar.b, greaterThan(AppColorsDark.bottomBar.r));
    });

    test('texte clair sur fond sombre (contraste, §15)', () {
      expect(AppColorsDark.textPrimary.computeLuminance(), greaterThan(0.9));
      expect(AppColorsDark.textSecondary.computeLuminance(), greaterThan(0.3));
    });

    test('dégradés bleus — fin du magenta (§14)', () {
      expect(AppColorsDark.primaryGradient, [AppColorsDark.primaryDark, AppColorsDark.primary]);
      expect(AppColorsDark.accentGradient, [AppColorsDark.primary, AppColorsDark.vostfr]);
      for (final Color c in [...AppColorsDark.primaryGradient, ...AppColorsDark.accentGradient]) {
        expect(c, isNot(const Color(0xFFD946EF))); // ancien magenta
        expect(c.b, greaterThanOrEqualTo(c.r)); // la dominance est bleue
      }
    });
  });

  // ---------------------------------------------------------------------
  // 2. Sémantique figée : vert / ambre / rouge — JAMAIS bleus (§4).
  // ---------------------------------------------------------------------

  group('Couleurs sémantiques honnêtes dans les deux palettes', () {
    void checkSemantics(Color success, Color warning, Color danger) {
      // succès = vert dominant
      expect(success.g, greaterThan(success.r));
      expect(success.g, greaterThan(success.b));
      // avertissement = ambre/orange : rouge+vert marqués, bleu faible
      expect(warning.r, greaterThan(warning.b));
      expect(warning.g, greaterThan(warning.b));
      // erreur = rouge dominant
      expect(danger.r, greaterThan(danger.g));
      expect(danger.r, greaterThan(danger.b));
    }

    test('mode sombre', () {
      checkSemantics(AppColorsDark.success, AppColorsDark.warning, AppColorsDark.danger);
      expect(AppColorsDark.danger, const Color(0xFFEF4444)); // rouge franc (§4)
    });

    test('mode clair', () {
      checkSemantics(AppColorsLight.success, AppColorsLight.warning, AppColorsLight.danger);
    });

    test('pastilles de langue = couleurs de contenu conservées (§14)', () {
      // VF reste rose (pas de bleu déguisé), VOSTFR reste dans la famille ciel.
      expect(AppColorsDark.vf, const Color(0xFFFB7185));
      expect(AppColorsDark.vostfr, const Color(0xFF38BDF8));
    });
  });

  // ---------------------------------------------------------------------
  // 3. Vrai mode CLAIR (§6/§19/§20) : fonds clairs, texte sombre, bleu.
  // ---------------------------------------------------------------------

  group('Palette claire (vrai mode clair)', () {
    test('fonds blanc / gris très clair', () {
      expect(AppColorsLight.background.computeLuminance(), greaterThan(0.9));
      expect(AppColorsLight.surface.computeLuminance(), greaterThan(0.95));
      expect(AppColorsLight.surfaceAlt.computeLuminance(), greaterThan(0.89));
    });

    test('texte sombre (contraste sur clair, §15)', () {
      expect(AppColorsLight.textPrimary.computeLuminance(), lessThan(0.05));
      expect(AppColorsLight.textSecondary.computeLuminance(), lessThan(0.15));
    });

    test('accent bleu lisible sur blanc (§15)', () {
      expect(AppColorsLight.primary, const Color(0xFF2563EB));
      expect(AppColorsLight.primary.computeLuminance(), lessThan(0.25));
      expect(AppColorsLight.primaryBright.computeLuminance(), lessThan(0.2));
    });
  });

  // ---------------------------------------------------------------------
  // 4. Bascule de la palette active — point d'entrée unique (§3).
  // ---------------------------------------------------------------------

  group('AppColors.apply — hot-swap complet', () {
    test('bascule sombre → clair → sombre sur TOUTES les couleurs', () {
      AppColors.apply(Brightness.light);
      try {
        expect(AppColors.activeBrightness, Brightness.light);
        expect(AppColors.background, AppColorsLight.background);
        expect(AppColors.surface, AppColorsLight.surface);
        expect(AppColors.card, AppColorsLight.card);
        expect(AppColors.bottomBar, AppColorsLight.bottomBar);
        expect(AppColors.primary, AppColorsLight.primary);
        expect(AppColors.primaryBright, AppColorsLight.primaryBright);
        expect(AppColors.textPrimary, AppColorsLight.textPrimary);
        expect(AppColors.textSecondary, AppColorsLight.textSecondary);
        expect(AppColors.divider, AppColorsLight.divider);
        expect(AppColors.success, AppColorsLight.success);
        expect(AppColors.warning, AppColorsLight.warning);
        expect(AppColors.danger, AppColorsLight.danger);
        expect(AppColors.vf, AppColorsLight.vf);
        expect(AppColors.vostfr, AppColorsLight.vostfr);
        expect(AppColors.primaryGradient, equals([AppColorsLight.primaryDark, AppColorsLight.primary]));
      } finally {
        AppColors.apply(Brightness.dark);
      }
      expect(AppColors.activeBrightness, Brightness.dark);
      expect(AppColors.background, AppColorsDark.background);
      expect(AppColors.primary, AppColorsDark.primary);
      expect(AppColors.textPrimary, AppColorsDark.textPrimary);
      expect(AppColors.danger, AppColorsDark.danger);
    });

    test('le bleu se change en un seul endroit : les champs actifs suivent les palettes', () {
      AppColors.apply(Brightness.dark);
      expect(identical(AppColors.primary, AppColorsDark.primary), isTrue);
      AppColors.apply(Brightness.light);
      try {
        expect(identical(AppColors.primary, AppColorsLight.primary), isTrue);
      } finally {
        AppColors.apply(Brightness.dark);
      }
    });
  });

  // ---------------------------------------------------------------------
  // 5. ThemeData : sombre ET clair depuis la même source (§18-§20).
  // ---------------------------------------------------------------------

  group('AppTheme — thèmes sombre et clair réels', () {
    test('thème sombre bleu cohérent', () {
      final ThemeData dark = AppTheme.dark;
      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, AppColorsDark.background);
      expect(dark.colorScheme.primary, AppColorsDark.primary);
      expect(dark.colorScheme.error, AppColorsDark.danger);
      expect(dark.dividerTheme.color, AppColorsDark.divider);
      expect(dark.textTheme.bodyLarge?.color, AppColorsDark.textPrimary);
    });

    test('thème clair réel : fond clair, texte sombre, bleu en accent', () {
      final ThemeData light = AppTheme.light;
      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, AppColorsLight.background);
      expect(light.scaffoldBackgroundColor.computeLuminance(), greaterThan(0.9));
      expect(light.colorScheme.primary, AppColorsLight.primary);
      expect(light.colorScheme.error, AppColorsLight.danger);
      expect(light.textTheme.bodyLarge?.color, AppColorsLight.textPrimary);
      expect(light.textTheme.bodyMedium?.color, AppColorsLight.textSecondary);
    });

    test('les polices et rayons restent identiques (aucun redesign)', () {
      expect(AppTheme.dark.textTheme.bodyLarge?.fontSize, AppTheme.light.textTheme.bodyLarge?.fontSize);
      expect(AppTheme.dark.fontFamily, 'Poppins');
      expect(AppTheme.light.fontFamily, 'Poppins');
    });
  });

  // ---------------------------------------------------------------------
  // 6. Trois modes persistés (§19) : dark / light / system.
  // ---------------------------------------------------------------------

  group('Préférence de thème — trois choix persistés', () {
    test('AppThemeMode expose dark, light, system', () {
      expect(AppThemeMode.values, containsAll(<AppThemeMode>[AppThemeMode.dark, AppThemeMode.light, AppThemeMode.system]));
      expect(AppThemeMode.values.length, 3);
    });

    test('cycle dark → light persistant et recharge (rétrocompatible)', () async {
      final Directory dir = await Directory.systemTemp.createTemp('animebox_theme_');
      try {
        final LocalDatabase db1 = (await LocalDatabase.open(directoryPath: dir.path))!;
        final AppSettings first = AppSettings(database: db1);
        await first.ensureLoaded();
        expect(first.theme, AppThemeMode.dark); // défaut conservé
        await first.setTheme(AppThemeMode.light);
        expect(first.theme, AppThemeMode.light);
        await db1.close();

        final LocalDatabase db2 = (await LocalDatabase.open(directoryPath: dir.path))!;
        final AppSettings second = AppSettings(database: db2);
        await second.ensureLoaded();
        expect(second.theme, AppThemeMode.light); // survit au redémarrage
        await second.setTheme(AppThemeMode.system);
        await db2.close();

        final LocalDatabase db3 = (await LocalDatabase.open(directoryPath: dir.path))!;
        final AppSettings third = AppSettings(database: db3);
        await third.ensureLoaded();
        expect(third.theme, AppThemeMode.system);
        await db3.close();
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('valeurs historiques : « dark »/inconnue → sombre (aucune régression)', () async {
      final Directory dir = await Directory.systemTemp.createTemp('animebox_theme_legacy_');
      try {
        final LocalDatabase db = (await LocalDatabase.open(directoryPath: dir.path))!;
        await db.setSetting('app.theme', 'dark'); // valeur historique
        final AppSettings settings = AppSettings(database: db);
        await settings.ensureLoaded();
        expect(settings.theme, AppThemeMode.dark);
        await db.setSetting('app.theme', 'incohérent');
        await settings.ensureLoaded();
        // valeur inconnue → retombe sur sombre au prochain chargement
        final AppSettings reloaded = AppSettings(database: db);
        await reloaded.ensureLoaded();
        expect(reloaded.theme, AppThemeMode.dark);
        await db.close();
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  // ---------------------------------------------------------------------
  // 7. Chaînes du sélecteur (FR/EN honnêtes, §5).
  // ---------------------------------------------------------------------

  group('SettingsStrings — libellés des trois modes', () {
    test('FR : Sombre / Clair / Système', () {
      final SettingsStrings s = SettingsStrings('fr');
      expect(s.themeDark, 'Sombre');
      expect(s.themeLight, 'Clair');
      expect(s.themeSystem, 'Système');
      expect(s.themeNote, contains('sombre'));
      expect(s.themeNote, contains('clair'));
      expect(s.themeNote, isNot(contains('identité sombre'))); // note obsolète retirée
    });

    test('EN : Dark / Light / System', () {
      final SettingsStrings s = SettingsStrings('en');
      expect(s.themeDark, 'Dark');
      expect(s.themeLight, 'Light');
      expect(s.themeSystem, 'System');
    });
  });
}
