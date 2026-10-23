import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/duration_formatter.dart';
import '../viewmodels/player_view_model.dart';

/// Barra de progreso con scrubbing preciso:
/// - El track se engrosa al arrastrar (Apple Music) y muestra el buffer.
/// - Mientras se arrastra, la posición es local (no salta con el stream).
/// - Feedback háptico al soltar.
class PlaybackProgressBar extends StatefulWidget {
  const PlaybackProgressBar({
    super.key,
    required this.progressStream,
    required this.onSeek,
  });

  final Stream<ProgressState> progressStream;
  final ValueChanged<Duration> onSeek;

  @override
  State<PlaybackProgressBar> createState() => _PlaybackProgressBarState();
}

class _PlaybackProgressBarState extends State<PlaybackProgressBar> {
  late final Stream<ProgressState> _stream = widget.progressStream;
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final dragging = _dragValue != null;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppTheme.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    return StreamBuilder<ProgressState>(
      stream: _stream,
      initialData: ProgressState.zero,
      builder: (context, snapshot) {
        final p = snapshot.data ?? ProgressState.zero;
        final totalMs = p.total.inMilliseconds.toDouble();
        final max = totalMs <= 0 ? 1.0 : totalMs;
        final value =
            (_dragValue ?? p.position.inMilliseconds.toDouble()).clamp(0.0, max);
        final buffered = p.buffered.inMilliseconds.toDouble().clamp(0.0, max);
        final shown = Duration(milliseconds: value.round());
        final remaining = p.total - shown;

        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: dragging ? 22 : 16,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Indicador de buffer.
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: dragging ? 8 : 4,
                      thumbShape: SliderComponentShape.noThumb,
                      activeTrackColor: const Color(0x55FFFFFF),
                      disabledActiveTrackColor: const Color(0x55FFFFFF),
                      disabledInactiveTrackColor: const Color(0x22FFFFFF),
                    ),
                    child: Slider(value: buffered, max: max, onChanged: null),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: dragging ? 8 : 4,
                      inactiveTrackColor: Colors.transparent,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: dragging ? 0 : 5,
                        elevation: 0,
                        pressedElevation: 0,
                      ),
                    ),
                    child: Slider(
                      value: value,
                      max: max,
                      onChangeStart: (v) => setState(() => _dragValue = v),
                      onChanged: (v) => setState(() => _dragValue = v),
                      onChangeEnd: (v) {
                        HapticFeedback.selectionClick();
                        widget.onSeek(Duration(milliseconds: v.round()));
                        setState(() => _dragValue = null);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatDuration(shown), style: labelStyle),
                  Text(
                    '-${formatDuration(remaining.isNegative ? Duration.zero : remaining)}',
                    style: labelStyle,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
