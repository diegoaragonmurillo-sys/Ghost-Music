import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'features/player/views/player_screen.dart';
import 'services/audio_handler.dart';
import 'services/audio_player_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Barra de estado clara sobre el fondo oscuro e inmersivo.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  // Background Service: la música sigue con la pantalla apagada y los
  // controles aparecen en la pantalla de bloqueo / notificación.
  final audioHandler = await initAudioService();

  runApp(GhostMusicApp(audioService: AudioPlayerService(audioHandler)));
}

class GhostMusicApp extends StatelessWidget {
  const GhostMusicApp({super.key, required this.audioService});

  final AudioPlayerService audioService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghost Music',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.dark,
      theme: AppTheme.dark,
      home: PlayerScreen(audioService: audioService),
    );
  }
}
