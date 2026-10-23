import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'core/theme/app_theme.dart';
import 'features/home/home_screen.dart';
import 'services/audio_handler.dart';
import 'services/audio_player_service.dart';
import 'services/lyrics_service.dart';
import 'services/palette_service.dart';
import 'services/search_service.dart';

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

  // Servicios compartidos de la arquitectura híbrida.
  final searchService = SearchService();
  final paletteService = PaletteService();
  final lyricsService = LyricsService();

  // Background Service: la música sigue con la pantalla apagada y los
  // controles aparecen en la pantalla de bloqueo / notificación.
  final audioHandler = await initAudioService();
  final audioService = AudioPlayerService(
    audioHandler,
    searchService: searchService,
  );

  runApp(
    GhostMusicApp(
      audioService: audioService,
      searchService: searchService,
      paletteService: paletteService,
      lyricsService: lyricsService,
    ),
  );
}

class GhostMusicApp extends StatelessWidget {
  const GhostMusicApp({
    super.key,
    required this.audioService,
    required this.searchService,
    required this.paletteService,
    required this.lyricsService,
  });

  final AudioPlayerService audioService;
  final SearchService searchService;
  final PaletteService paletteService;
  final LyricsService lyricsService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghost Music',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.dark,
      theme: AppTheme.dark,
      home: HomeScreen(
        audioService: audioService,
        searchService: searchService,
        paletteService: paletteService,
        lyricsService: lyricsService,
      ),
    );
  }
}
