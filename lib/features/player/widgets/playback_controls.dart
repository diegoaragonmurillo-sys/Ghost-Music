import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/theme/app_theme.dart';

/// Controles de reproducción con jerarquía tipo Spotify:
/// Play/Pause grande y central (Ley de Fitts), anterior/siguiente medianos y
/// shuffle/repeat periféricos con estado activo en color de acento.
class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
    required this.isPlaying,
    required this.isLoading,
    required this.shuffle,
    required this.loopMode,
    required this.accentColor,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onShuffle,
    required this.onRepeat,
  });

  final bool isPlaying;
  final bool isLoading;
  final bool shuffle;
  final LoopMode loopMode;
  final Color accentColor;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ToggleButton(
          icon: Icons.shuffle_rounded,
          active: shuffle,
          accent: accentColor,
          onTap: onShuffle,
        ),
        _PressableIcon(
          icon: Icons.skip_previous_rounded,
          size: 44,
          onTap: onPrevious,
        ),
        _PlayPauseButton(
          isPlaying: isPlaying,
          isLoading: isLoading,
          onTap: onPlayPause,
        ),
        _PressableIcon(
          icon: Icons.skip_next_rounded,
          size: 44,
          onTap: onNext,
        ),
        _ToggleButton(
          icon: loopMode == LoopMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          active: loopMode != LoopMode.off,
          accent: accentColor,
          onTap: onRepeat,
        ),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.isPlaying,
    required this.isLoading,
    required this.onTap,
  });

  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 76,
        height: 76,
        decoration: const BoxDecoration(
          color: AppTheme.textPrimary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: isLoading && !isPlaying
                ? const SizedBox(
                    key: ValueKey('loading'),
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.black,
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    key: ValueKey(isPlaying),
                    size: 44,
                    color: Colors.black,
                  ),
          ),
        ),
      ),
    );
  }
}

class _PressableIcon extends StatelessWidget {
  const _PressableIcon({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: size),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.icon,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                icon,
                key: ValueKey('$icon$active'),
                size: 24,
                color: active ? accent : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Micro-interacción: el botón se encoge al presionarse con rebote elástico.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.86 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
