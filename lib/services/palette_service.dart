import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:palette_generator/palette_generator.dart';

import '../features/player/models/track.dart';
import 'download_service.dart';

/// Colores extraídos de una carátula para teñir dinámicamente la UI
/// (efecto "chameleon" de Apple Music / gradiente de Spotify).
class ArtworkPalette {
  const ArtworkPalette({required this.primary, required this.secondary});

  final Color primary;
  final Color secondary;

  static const fallback = ArtworkPalette(
    primary: Color(0xFF3A1C5C),
    secondary: Color(0xFF0E1A3A),
  );
}

class PaletteService {
  final Map<String, ArtworkPalette> _cache = {};

  /// Extrae la paleta desde el archivo local de carátula si el track está
  /// descargado (100% offline), o desde la URL de red como fallback.
  Future<ArtworkPalette> fromTrack(Track track) async {
    final pkg = DownloadService.instance.getPackage(track.id);
    if (pkg?.localArtworkPath != null) {
      final localPath = pkg!.localArtworkPath!;
      final localFile = File(localPath);
      if (localFile.existsSync()) {
        final cached = _cache['file://$localPath'];
        if (cached != null) return cached;

        try {
          final generator = await PaletteGenerator.fromImageProvider(
            ResizeImage(FileImage(localFile), width: 120, height: 120),
            maximumColorCount: 16,
          );
          final primary = generator.vibrantColor?.color ??
              generator.dominantColor?.color ??
              ArtworkPalette.fallback.primary;
          final secondary = generator.darkMutedColor?.color ??
              generator.darkVibrantColor?.color ??
              generator.mutedColor?.color ??
              ArtworkPalette.fallback.secondary;

          return _cache['file://$localPath'] =
              ArtworkPalette(primary: primary, secondary: secondary);
        } catch (_) {
          // fallback a URL
        }
      }
    }

    final paletteUrl = track.fallbackArtworkUrl ?? track.artworkUrl;
    return fromUrl(paletteUrl);
  }

  Future<ArtworkPalette> fromUrl(String url) async {
    final cached = _cache[url];
    if (cached != null) return cached;

    try {
      final generator = await PaletteGenerator.fromImageProvider(
        ResizeImage(NetworkImage(url), width: 120, height: 120),
        maximumColorCount: 16,
      );
      final primary = generator.vibrantColor?.color ??
          generator.dominantColor?.color ??
          ArtworkPalette.fallback.primary;
      final secondary = generator.darkMutedColor?.color ??
          generator.darkVibrantColor?.color ??
          generator.mutedColor?.color ??
          ArtworkPalette.fallback.secondary;

      return _cache[url] =
          ArtworkPalette(primary: primary, secondary: secondary);
    } catch (_) {
      return ArtworkPalette.fallback;
    }
  }
}
