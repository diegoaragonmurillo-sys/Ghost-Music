import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../features/player/models/track.dart';
import '../../services/download_service.dart';

/// Renderiza la carátula de un [Track] desde disco local si está descargado
/// (100% offline sin conexión) o desde la red si no lo está.
class TrackArtworkImage extends StatelessWidget {
  const TrackArtworkImage({
    super.key,
    required this.track,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.errorWidget,
  });

  final Track track;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    final pkg = DownloadService.instance.getPackage(track.id);
    final localArt = pkg?.localArtworkPath;

    Widget image;
    if (localArt != null && File(localArt).existsSync()) {
      image = Image.file(
        File(localArt),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _buildFallbackNetworkImage(),
      );
    } else {
      image = _buildFallbackNetworkImage();
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: image,
      );
    }
    return image;
  }

  Widget _buildFallbackNetworkImage() {
    final url = track.artworkUrl.isNotEmpty
        ? track.artworkUrl
        : (track.fallbackArtworkUrl ?? '');

    if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      return _buildError();
    }

    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) {
        final fallback = track.fallbackArtworkUrl;
        if (fallback != null && fallback.isNotEmpty && fallback != url) {
          return Image.network(
            fallback,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, _, _) => _buildError(),
          );
        }
        return _buildError();
      },
    );
  }

  Widget _buildError() {
    return errorWidget ??
        Container(
          width: width,
          height: height,
          color: const Color(0xFF1C1C22),
          child: const Icon(
            Icons.music_note_rounded,
            color: Colors.white70,
          ),
        );
  }
}
