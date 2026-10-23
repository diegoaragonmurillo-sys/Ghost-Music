import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/library_service.dart';
import '../../player/models/track.dart';

/// Modal Bottom Sheet reutilizable para añadir un [Track] a una Playlist
/// existente o crear una nueva en el acto.
class AddToPlaylistSheet extends StatefulWidget {
  const AddToPlaylistSheet({
    super.key,
    required this.libraryService,
    required this.track,
  });

  final LibraryService libraryService;
  final Track track;

  static Future<void> show(
    BuildContext context, {
    required LibraryService libraryService,
    required Track track,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddToPlaylistSheet(
        libraryService: libraryService,
        track: track,
      ),
    );
  }

  @override
  State<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<AddToPlaylistSheet> {
  Future<void> _promptCreatePlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Nueva Playlist',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (val) => Navigator.of(dialogContext).pop(val),
            decoration: InputDecoration(
              hintText: 'Nombre de la playlist',
              hintStyle: const TextStyle(color: Color(0x80FFFFFF)),
              filled: true,
              fillColor: const Color(0xFF121216),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text(
                'Crear',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
    controller.dispose();

    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;

    final created = await widget.libraryService.createPlaylist(
      trimmed,
      initialTrack: widget.track,
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Añadida a "${created.name}"'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _addToExistingPlaylist(String playlistId, String name) async {
    await widget.libraryService.addTrackToPlaylist(playlistId, widget.track);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Añadida a "$name"'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF16161C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: widget.libraryService,
          builder: (context, _) {
            final playlists = widget.libraryService.playlists;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Añadir a una Playlist',
                              style: text.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${widget.track.title} • ${widget.track.artist}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0x18FFFFFF)),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: AppTheme.accent,
                      size: 26,
                    ),
                  ),
                  title: Text(
                    'Nueva Playlist...',
                    style: text.titleMedium?.copyWith(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Crear playlist y guardar esta canción',
                    style: text.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  onTap: _promptCreatePlaylist,
                ),
                if (playlists.isNotEmpty) ...[
                  const Divider(height: 1, color: Color(0x18FFFFFF)),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: playlists.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        indent: 78,
                        color: Color(0x14FFFFFF),
                      ),
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        final alreadyAdded = playlist.tracks.any(
                          (t) => t.id == widget.track.id,
                        );
                        final cover = playlist.coverUrl;

                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: cover != null
                                ? Image.network(
                                    cover,
                                    width: 46,
                                    height: 46,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const _PlaylistPlaceholderIcon(),
                                  )
                                : const _PlaylistPlaceholderIcon(),
                          ),
                          title: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${playlist.tracks.length} ${playlist.tracks.length == 1 ? 'canción' : 'canciones'}',
                            style: text.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          trailing: Icon(
                            alreadyAdded
                                ? Icons.check_circle_rounded
                                : Icons.add_circle_outline_rounded,
                            color: alreadyAdded
                                ? AppTheme.accent
                                : AppTheme.textSecondary,
                          ),
                          onTap: () => _addToExistingPlaylist(
                            playlist.id,
                            playlist.name,
                          ),
                        );
                      },
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Text(
                      'Aún no tienes playlists creadas.',
                      style: text.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlaylistPlaceholderIcon extends StatelessWidget {
  const _PlaylistPlaceholderIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFF23232B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.queue_music_rounded,
        color: AppTheme.textSecondary,
      ),
    );
  }
}
