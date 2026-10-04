import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/tokens.dart';

/// Shrinks slightly under the finger. Every tappable surface in Trace uses it.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.96, this.haptic = true});

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Motion.fast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.gradient = TraceColors.emberGradient,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Pressable(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: Motion.fast,
        opacity: enabled || loading ? 1 : 0.4,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(Radii.md),
            boxShadow: enabled
                ? [BoxShadow(color: TraceColors.ember.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))]
                : null,
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: Motion.fast,
            child: loading
                ? const SizedBox.square(
                    key: ValueKey('loading'),
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: TraceColors.ink),
                  )
                : Row(
                    key: const ValueKey('label'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[Icon(icon, color: TraceColors.ink, size: 20), const SizedBox(width: 10)],
                      Text(
                        label,
                        style: const TextStyle(
                          color: TraceColors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, this.onPressed, this.icon, this.color = TraceColors.text});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: TraceColors.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: TraceColors.line),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, color: color, size: 20), const SizedBox(width: 10)],
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

/// Round icon button used on glass surfaces.
class OrbButton extends StatelessWidget {
  const OrbButton({super.key, required this.icon, this.onTap, this.size = 48, this.tooltip});

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Pressable(
        onTap: onTap,
        scale: 0.9,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: TraceColors.surfaceHigh.withValues(alpha: 0.9),
            border: Border.all(color: TraceColors.line),
          ),
          child: Icon(icon, color: TraceColors.text, size: size * 0.44),
        ),
      ),
    );
  }
}
