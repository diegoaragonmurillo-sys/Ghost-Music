import 'package:material_ui/material_ui.dart';

import '../../core/settings_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../services/download_service.dart';

/// Pantalla de Ajustes estilo Apple Music con selectores de Calidad de Audio
/// (Streaming y Descargas) y Gestión de Almacenamiento Offline.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.settingsManager,
    this.downloadService,
  });

  final SettingsManager? settingsManager;
  final DownloadService? downloadService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsManager get _settings =>
      widget.settingsManager ?? SettingsManager.instance;
  DownloadService get _downloads =>
      widget.downloadService ?? DownloadService.instance;

  @override
  void initState() {
    super.initState();
    _settings.init();
  }

  Future<void> _confirmClearAllDownloads() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Vaciar descargas',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            '¿Estás seguro de que deseas eliminar todas las canciones descargadas? Se liberará el almacenamiento local.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Eliminar todo'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _downloads.deleteAllDownloads();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se han eliminado todas las descargas.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        title: Text(
          'Ajustes',
          style: text.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        centerTitle: true,
      ),
      body: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          final streamingQuality = _settings.audioQuality;
          final downloadQuality = _settings.downloadQuality;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              // ---------------------------------------------------------------
              // SECCIÓN 1: CALIDAD DE STREAMING
              // ---------------------------------------------------------------
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 8),
                child: Text(
                  'CALIDAD DE STREAMING',
                  style: text.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C22),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x18FFFFFF)),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < AudioQuality.values.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: 56,
                          endIndent: 16,
                          color: Color(0x18FFFFFF),
                        ),
                      _AudioQualityOptionTile(
                        quality: AudioQuality.values[i],
                        isSelected: streamingQuality == AudioQuality.values[i],
                        isFirst: i == 0,
                        isLast: i == AudioQuality.values.length - 1,
                        onSelect: () =>
                            _settings.setAudioQuality(AudioQuality.values[i]),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Ghost Music degrada en cascada automáticamente si la fuente no está disponible '
                  '(Deezer FLAC -> JioSaavn 320k -> YouTube 128k).',
                  style: text.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ---------------------------------------------------------------
              // SECCIÓN 2: CALIDAD DE DESCARGA
              // ---------------------------------------------------------------
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 8),
                child: Text(
                  'CALIDAD DE DESCARGA',
                  style: text.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C22),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x18FFFFFF)),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < AudioQuality.values.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: 56,
                          endIndent: 16,
                          color: Color(0x18FFFFFF),
                        ),
                      _AudioQualityOptionTile(
                        quality: AudioQuality.values[i],
                        isSelected: downloadQuality == AudioQuality.values[i],
                        isFirst: i == 0,
                        isLast: i == AudioQuality.values.length - 1,
                        onSelect: () =>
                            _settings.setDownloadQuality(AudioQuality.values[i]),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Las canciones descargadas guardan en disco audio, carátula y letras LRC.',
                  style: text.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ---------------------------------------------------------------
              // SECCIÓN 3: ALMACENAMIENTO OFFLINE
              // ---------------------------------------------------------------
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 8),
                child: Text(
                  'ALMACENAMIENTO OFFLINE',
                  style: text.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: _downloads,
                builder: (context, _) {
                  final totalBytes = _downloads.totalStorageBytes;
                  final count = _downloads.downloadedPackages.length;
                  final mbString = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C22),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x18FFFFFF)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$count ${count == 1 ? 'canción descargada' : 'canciones descargadas'}',
                                  style: text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Espacio ocupado: $mbString MB',
                                  style: text.bodySmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            FilledButton.tonalIcon(
                              onPressed: count == 0
                                  ? null
                                  : _confirmClearAllDownloads,
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    AppTheme.accent.withValues(alpha: 0.15),
                                foregroundColor: AppTheme.accent,
                                disabledBackgroundColor: Colors.white10,
                                disabledForegroundColor: Colors.white24,
                              ),
                              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                              label: const Text('Vaciar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AudioQualityOptionTile extends StatelessWidget {
  const _AudioQualityOptionTile({
    required this.quality,
    required this.isSelected,
    required this.isFirst,
    required this.isLast,
    required this.onSelect,
  });

  final AudioQuality quality;
  final bool isSelected;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onSelect;

  IconData get _icon => switch (quality) {
        AudioQuality.dataSaver => Icons.data_saver_on_rounded,
        AudioQuality.high => Icons.high_quality_rounded,
        AudioQuality.lossless => Icons.graphic_eq_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final borderRadius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(16) : Radius.zero,
      bottom: isLast ? const Radius.circular(16) : Radius.zero,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent.withValues(alpha: 0.18)
                      : const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _icon,
                  size: 20,
                  color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            quality.title,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.accent.withValues(alpha: 0.22)
                                : const Color(0x1FFFFFFF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            quality.badge,
                            style: text.labelSmall?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? AppTheme.accent
                                  : AppTheme.textSecondary,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      quality.subtitle,
                      style: text.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedOpacity(
                opacity: isSelected ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.accent,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
