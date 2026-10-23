import 'package:material_ui/material_ui.dart';

import '../../core/settings_manager.dart';
import '../../core/theme/app_theme.dart';

/// Pantalla de Ajustes estilo Apple Music con selector de Calidad de Audio.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.settingsManager,
  });

  final SettingsManager? settingsManager;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsManager get _settings =>
      widget.settingsManager ?? SettingsManager.instance;

  @override
  void initState() {
    super.initState();
    _settings.init();
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
          final currentQuality = _settings.audioQuality;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              // Cabecera de sección estilo iOS / Apple Music.
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 8),
                child: Text(
                  'CALIDAD DE AUDIO',
                  style: text.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
              ),

              // Tarjeta agrupada con las 3 opciones de calidad.
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
                        isSelected: currentQuality == AudioQuality.values[i],
                        isFirst: i == 0,
                        isLast: i == AudioQuality.values.length - 1,
                        onSelect: () =>
                            _settings.setAudioQuality(AudioQuality.values[i]),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Nota explicativa sobre el motor de enrutamiento con Fallback.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Ghost Music utiliza enrutamiento inteligente con tolerancia a fallos '
                  '(Graceful Degradation). Si el proveedor seleccionado no está disponible, '
                  'el motor degrada automáticamente en cascada (Deezer FLAC → JioSaavn 320kbps → YouTube 128kbps) '
                  'sin interrumpir tu reproducción.',
                  style: text.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                    height: 1.45,
                  ),
                ),
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
