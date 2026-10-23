import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../services/audio_player_service.dart';

/// Hoja modal para configurar el Temporizador de Apagado (Sleep Timer).
///
/// Ofrece presets comunes (15, 30, 45, 60 min, o al terminar la pista actual)
/// y permite cancelar un temporizador activo con fade-out suave.
class SleepTimerSheet extends StatefulWidget {
  const SleepTimerSheet({
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
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SleepTimerSheet(audioService: audioService),
    );
  }

  @override
  State<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<SleepTimerSheet> {
  AudioPlayerService get _audio => widget.audioService;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(
                Icons.bedtime_rounded,
                color: AppTheme.accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Temporizador de apagado',
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Estado activo si existe
          StreamBuilder<Duration?>(
            stream: _audio.sleepTimerStream,
            builder: (context, snapshot) {
              if (_audio.isSleepTimerActive) {
                final remaining = _audio.sleepTimerRemaining;
                final isEndOfTrack = _audio.isSleepTimerEndOfTrack;

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        color: AppTheme.accent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isEndOfTrack
                              ? 'Apagado al terminar la canción actual'
                              : 'Apagado en ${formatDuration(remaining ?? Duration.zero)}',
                          style: text.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _audio.cancelSleepTimer();
                          setState(() {});
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: const Text('Desactivar'),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          // Presets
          _PresetTile(
            title: '15 minutos',
            onTap: () {
              _audio.startSleepTimer(const Duration(minutes: 15));
              Navigator.of(context).pop();
            },
          ),
          _PresetTile(
            title: '30 minutos',
            onTap: () {
              _audio.startSleepTimer(const Duration(minutes: 30));
              Navigator.of(context).pop();
            },
          ),
          _PresetTile(
            title: '45 minutos',
            onTap: () {
              _audio.startSleepTimer(const Duration(minutes: 45));
              Navigator.of(context).pop();
            },
          ),
          _PresetTile(
            title: '1 hora',
            onTap: () {
              _audio.startSleepTimer(const Duration(hours: 1));
              Navigator.of(context).pop();
            },
          ),
          _PresetTile(
            title: 'Al finalizar la canción actual',
            icon: Icons.music_note_rounded,
            onTap: () {
              _audio.setSleepTimerEndOfTrack();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.title,
    required this.onTap,
    this.icon = Icons.access_time_rounded,
  });

  final String title;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondary, size: 20),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: onTap,
    );
  }
}
