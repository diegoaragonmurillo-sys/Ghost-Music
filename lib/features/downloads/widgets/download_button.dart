import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/download_service.dart';
import '../../player/models/track.dart';
import '../models/offline_package.dart';

/// Botón reactivo de descarga para un [Track].
///
/// Cambia de estado dinámicamente:
/// - `idle`: icono de descarga
/// - `downloading`: indicador circular de progreso con botón de cancelar
/// - `downloaded`: check de completado en acento (al tocar, opción para borrar)
/// - `error`: alerta en ámbar para reintentar
class DownloadButton extends StatelessWidget {
  const DownloadButton({
    super.key,
    required this.track,
    this.size = 24.0,
    this.downloadService,
  });

  final Track track;
  final double size;
  final DownloadService? downloadService;

  DownloadService get _service => downloadService ?? DownloadService.instance;

  Future<void> _promptDelete(BuildContext context) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1C1C22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Eliminar descarga',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '¿Deseas eliminar "${track.title}" del almacenamiento offline?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                        ),
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        child: const Text('Eliminar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      await _service.deleteDownload(track.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final progress = _service.getProgress(track.id);

        switch (progress.status) {
          case DownloadTaskStatus.idle:
            return IconButton(
              tooltip: 'Descargar para escuchar offline',
              iconSize: size,
              icon: const Icon(
                Icons.arrow_circle_down_rounded,
                color: AppTheme.textSecondary,
              ),
              onPressed: () => _service.downloadTrack(track),
            );

          case DownloadTaskStatus.downloading:
            return Tooltip(
              message: 'Descargando: ${(progress.progress * 100).toInt()}%',
              child: InkWell(
                borderRadius: BorderRadius.circular(size),
                onTap: () => _service.cancelDownload(track.id),
                child: SizedBox(
                  width: size + 16,
                  height: size + 16,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: size + 2,
                        height: size + 2,
                        child: CircularProgressIndicator(
                          value: progress.progress.clamp(0.05, 1.0),
                          strokeWidth: 2.5,
                          color: AppTheme.accent,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                      Icon(
                        Icons.stop_rounded,
                        size: size * 0.6,
                        color: AppTheme.accent,
                      ),
                    ],
                  ),
                ),
              ),
            );

          case DownloadTaskStatus.downloaded:
            return IconButton(
              tooltip: 'Descargado (Toca para eliminar)',
              iconSize: size,
              icon: const Icon(
                Icons.download_done_rounded,
                color: AppTheme.accent,
              ),
              onPressed: () => _promptDelete(context),
            );

          case DownloadTaskStatus.error:
            return IconButton(
              tooltip: 'Error al descargar. Toca para reintentar.',
              iconSize: size,
              icon: const Icon(
                Icons.error_outline_rounded,
                color: Colors.amberAccent,
              ),
              onPressed: () => _service.downloadTrack(track),
            );
        }
      },
    );
  }
}
