import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/animebox_app.dart';
import 'core/theme/app_colors.dart';
import 'features/anime/data/repositories/mock_anime_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Barres système transparentes, dans l'esprit sombre de l'application.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bottomBar,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(AnimeBoxApp(repository: MockAnimeRepository()));
}
