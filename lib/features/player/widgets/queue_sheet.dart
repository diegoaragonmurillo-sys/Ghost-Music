import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/track_artwork_image.dart';
import '../../../services/audio_player_service.dart';
import '../models/track.dart';

/// Hoja modal interactiva para ver y gestionar la cola de reproducción ("A continuación").
///
/// Permite:
/// - Reordenar canciones por arrastre (`ReorderableListView`).
/// - Eliminar pistas de la cola deslizando o con botón.
/// - Saltar directamente a cualquier canción.
/// - Activar o desactivar el Autoplay / Radio Infinita.
class QueueSheet extends StatefulWidget {
  const QueueSheet({
    super.key,
    required this.audioService,
  });

  final AudioPlayerService audioService;

  static Future<void> show(
    BuildContext context, {
    required AudioPlayerService audioService,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QueueSheet(audioService: audioService),
    );
  }

  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet> {
  AudioPlayerService get _audio => widget.audioService;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;

    return Container(
      height: size.height * 0.78,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          // Indicador de arrastre
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // Barra de cabecera con Título y Switch de Autoplay
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A continuación',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      StreamBuilder<List<Track>>(
                        stream: _audio.queueStream,
                        builder: (context, snapshot) {
                          final count = _audio.currentQueue.length;
                          return Text(
                            '$count ${count == 1 ? "canción" : "canciones"}',
                            style: text.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // Toggle de Autoplay / Radio
                StreamBuilder<bool>(
                  stream: _audio.autoplayStream,
                  builder: (context, _) {
                    final isAutoplay = _audio.autoplayEnabled;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.all_inclusive_rounded,
                          size: 18,
                          color: isAutoplay
                              ? AppTheme.accent
                              : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Autoplay',
                          style: text.labelSmall?.copyWith(
                            color: isAutoplay
                                ? AppTheme.accent
                                : AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Switch.adaptive(
                          value: isAutoplay,
                          activeTrackColor: AppTheme.accent,
                          activeThumbColor: Colors.white,
                          onChanged: (val) {
                            setState(() {
                              _audio.autoplayEnabled = val;
                            });
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 16, color: Colors.white10),
          // Lista interactiva y reordenable
          Expanded(
            child: StreamBuilder<Track?>(
              stream: _audio.currentTrackStream,
              builder: (context, _) {
                final queue = _audio.currentQueue;
                final currentIndex = _audio.currentIndex;

                if (queue.isEmpty) {
                  return const Center(
                    child: Text(
                      'La cola de reproducción está vacía',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  );
                }

                return ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 28),
                  itemCount: queue.length,
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() {
                      _audio.reorderQueue(oldIndex, newIndex);
                    });
                  },
                  itemBuilder: (context, index) {
                    final track = queue[index];
                    final isPlayingThis = index == currentIndex;

                    return Dismissible(
                      key: ValueKey('queue_${track.id}_$index'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.redAccent.withValues(alpha: 0.8),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.white,
                        ),
                      ),
                      onDismissed: (_) {
                        _audio.removeAt(index);
                      },
                      child: ListTile(
                        key: ValueKey('tile_${track.id}_$index'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading: Stack(
                          alignment: Alignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: TrackArtworkImage(
                                track: track,
                                width: 44,
                                height: 44,
                              ),
                            ),
                            if (isPlayingThis)
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.graphic_eq_rounded,
                                  color: AppTheme.accent,
                                  size: 22,
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isPlayingThis
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isPlayingThis
                                ? AppTheme.accent
                                : Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _audio.removeAt(index);
                                });
                              },
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  color: Colors.white38,
                                ),
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          _audio.skipToQueueItem(index);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
