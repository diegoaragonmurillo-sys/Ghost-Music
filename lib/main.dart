import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'features/player/views/player_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Barra de estado clara sobre el fondo oscuro e inmersivo.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  runApp(const GhostMusicApp());
}

class GhostMusicApp extends StatelessWidget {
  const GhostMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghost Music',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.dark,
      theme: AppTheme.dark,
      home: const PlayerScreen(),
    );
  }
}
