import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/signature.dart';
import '../../core/sensors/angle_sensor.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';

/// Then/Now composer (spec F-14): an old photo, and the angle it was taken from.
class ThenNowField extends StatefulWidget {
  const ThenNowField({
    super.key,
    required this.photo,
    required this.caption,
    required this.angle,
    required this.onPick,
    required this.onAngle,
  });

  final Uint8List? photo;
  final TextEditingController caption;
  final CaptureAngle? angle;
  final VoidCallback onPick;
  final ValueChanged<CaptureAngle> onAngle;

  @override
  State<ThenNowField> createState() => _ThenNowFieldState();
}

class _ThenNowFieldState extends State<ThenNowField> {
  final _sensor = AngleSensor();

  @override
  void initState() {
    super.initState();
    _sensor
      ..addListener(() => setState(() {}))
      ..start();
  }

  @override
  void dispose() {
    _sensor.dispose();
    super.dispose();
  }

  void _save() {
    if (!_sensor.available) return;
    HapticFeedback.mediumImpact();
    widget.onAngle(CaptureAngle(heading: _sensor.heading!, pitch: _sensor.pitch!));
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.angle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          onTap: widget.onPick,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.lg),
            child: AspectRatio(
              aspectRatio: 4 / 5,
              child: widget.photo != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        // Shown in sepia: it's the past.
                        ColorFiltered(
                          colorFilter: const ColorFilter.matrix([
                            0.393, 0.769, 0.189, 0, 0, //
                            0.349, 0.686, 0.168, 0, 0,
                            0.272, 0.534, 0.131, 0, 0,
                            0, 0, 0, 1, 0,
                          ]),
                          child: Image.memory(widget.photo!, fit: BoxFit.cover),
                        ),
                        const Positioned(
                          left: 12,
                          top: 12,
                          child: _Tag('THEN'),
                        ),
                      ],
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: TraceColors.surface,
                        border: Border.all(color: TraceColors.line),
                        borderRadius: BorderRadius.circular(Radii.lg),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.history_rounded, color: TraceColors.sun, size: 40),
                          const SizedBox(height: Space.sm),
                          Text('Choose an old photo', style: serif(size: 20)),
                          const SizedBox(height: 4),
                          Text('taken from right where you stand', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: widget.caption,
          maxLength: 500,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'When was it taken? Who took it?', counterText: ''),
        ),
        const SizedBox(height: Space.md),
        Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: TraceColors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: saved != null ? TraceColors.mint.withValues(alpha: 0.4) : TraceColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(saved != null ? Icons.check_circle_rounded : Icons.explore_rounded,
                      color: saved != null ? TraceColors.mint : TraceColors.sun, size: 20),
                  const SizedBox(width: Space.sm),
                  const Text('Camera angle', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(
                    _sensor.available
                        ? '${compassPoint(_sensor.heading!)} ${_sensor.heading!.round()}° · ${_sensor.pitch!.round()}° tilt'
                        : 'No compass',
                    style: const TextStyle(color: TraceColors.textMuted, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(
                saved == null
                    ? 'Point your phone the way the old camera pointed, then save the angle. Visitors will use it to line up.'
                    : 'Saved: facing ${compassPoint(saved.heading)} (${saved.heading.round()}°), tilted ${saved.pitch.round()}°.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TraceColors.textMuted),
              ),
              const SizedBox(height: Space.sm + 4),
              GhostButton(
                label: saved == null ? 'Save this angle' : 'Save again',
                icon: Icons.my_location_rounded,
                color: TraceColors.sun,
                onPressed: _sensor.available ? _save : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(100)),
        child: Text(text, style: const TextStyle(color: TraceColors.sun, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)),
      );
}
