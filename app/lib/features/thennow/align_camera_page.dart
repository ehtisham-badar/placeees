import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/api/models.dart';
import '../../core/api/signature.dart';
import '../../core/api/trace_api.dart';
import '../../core/location/location_service.dart';
import '../../core/sensors/angle_sensor.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/trace_image.dart';
import '../create/image_compress.dart';

const alignTolerance = 5.0;

/// Line the live camera up with the old photo, then take today's (spec F-14).
/// Pops the new [NowPhoto] when one was added.
class AlignCameraPage extends StatefulWidget {
  const AlignCameraPage({super.key, required this.drop});

  final DropContent drop;

  @override
  State<AlignCameraPage> createState() => _AlignCameraPageState();
}

class _AlignCameraPageState extends State<AlignCameraPage> with WidgetsBindingObserver {
  final _angle = AngleSensor();
  CameraController? _camera;
  String? _cameraError;
  double _ghost = 0.5;
  bool _wasAligned = false;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _angle
      ..addListener(_onAngle)
      ..start();
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _angle.dispose();
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _camera;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull ?? cams.firstOrNull;
      if (back == null) throw CameraException('none', 'No camera');
      final c = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _camera = c);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _cameraError = e.code == 'CameraAccessDenied'
            ? 'Camera access is off. Turn it on in Settings to line up the photo.'
            : 'This device has no camera available.');
      }
    }
  }

  CaptureAngle? get _target => widget.drop.angle;

  double? get _dHeading => _target == null || _angle.heading == null ? null : headingDelta(_target!.heading, _angle.heading!);
  double? get _dPitch => _target == null || _angle.pitch == null ? null : _target!.pitch - _angle.pitch!;

  bool get _aligned =>
      _dHeading != null && _dPitch != null && _dHeading!.abs() <= alignTolerance && _dPitch!.abs() <= alignTolerance;

  void _onAngle() {
    final aligned = _aligned;
    if (aligned && !_wasAligned) HapticFeedback.heavyImpact();
    _wasAligned = aligned;
    if (mounted) setState(() {});
  }

  Future<void> _capture() async {
    final c = _camera;
    if (c == null || _capturing) return;
    final api = context.read<TraceApi>();
    final location = context.read<LocationService>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _capturing = true);
    HapticFeedback.mediumImpact();
    try {
      final shot = await c.takePicture();
      final jpeg = await compressPhoto(shot.path);
      if (jpeg == null) throw const ApiError('upload_failed');
      final fix = await location.freshFix(maxAge: const Duration(seconds: 5));
      if (fix == null) throw const ApiError('low_accuracy');
      final photo = await api.postNowPhoto(widget.drop.id, jpeg, fix, heading: _angle.heading, pitch: _angle.pitch);
      nav.pop(photo);
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.code == 'too_far' ? 'Now photos have to be taken right here.' : e.message)));
    } on CameraException {
      messenger.showSnackBar(const SnackBar(content: Text('The camera didn’t take that one. Try again.')));
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _camera;
    final aligned = _aligned;
    final guide = aligned ? TraceColors.mint : TraceColors.text;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.previewSize!.height,
                  height: c.value.previewSize!.width,
                  child: CameraPreview(c),
                ),
              ),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: _cameraError == null
                    ? const CircularProgressIndicator(color: TraceColors.text)
                    : Text(_cameraError!, textAlign: TextAlign.center, style: serif(size: 20)),
              ),
            ),
          // The past, as a ghost over the present.
          IgnorePointer(
            child: Opacity(
              opacity: _ghost,
              child: TraceImage(url: widget.drop.mediaUrl, bytes: widget.drop.localImage),
            ),
          ),
          // Reticle.
          IgnorePointer(
            child: Center(
              child: AnimatedContainer(
                duration: Motion.medium,
                width: aligned ? 120 : 150,
                height: aligned ? 120 : 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: guide.withValues(alpha: 0.85), width: aligned ? 3 : 1.5),
                  boxShadow: aligned ? [BoxShadow(color: TraceColors.mint.withValues(alpha: 0.5), blurRadius: 30)] : null,
                ),
                child: Center(
                  child: _Guidance(dHeading: _dHeading, dPitch: _dPitch, aligned: aligned, hasTarget: _target != null),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: Row(
                    children: [
                      OrbButton(icon: Icons.close_rounded, onTap: () => Navigator.pop(context), tooltip: 'Close'),
                      const SizedBox(width: Space.sm + 4),
                      Expanded(
                        child: Text(
                          widget.drop.teaser ?? 'Then',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: serif(size: 18, style: FontStyle.italic, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: Row(
                    children: [
                      const Text('NOW', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)),
                      Expanded(
                        child: Slider(
                          value: _ghost,
                          onChanged: (v) => setState(() => _ghost = v),
                          activeColor: TraceColors.sun,
                          inactiveColor: Colors.white24,
                        ),
                      ),
                      const Text('THEN', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)),
                    ],
                  ),
                ),
                const SizedBox(height: Space.sm),
                Pressable(
                  onTap: c == null ? null : _capture,
                  scale: 0.9,
                  child: AnimatedContainer(
                    duration: Motion.medium,
                    width: 78,
                    height: 78,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: guide, width: 3)),
                    child: Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: aligned ? TraceColors.mint : Colors.white),
                      alignment: Alignment.center,
                      child: _capturing
                          ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: TraceColors.ink))
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: Space.lg),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Guidance extends StatelessWidget {
  const _Guidance({required this.dHeading, required this.dPitch, required this.aligned, required this.hasTarget});

  final double? dHeading;
  final double? dPitch;
  final bool aligned;
  final bool hasTarget;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, shadows: [Shadow(blurRadius: 6)]);
    if (!hasTarget) return const Text('Match the ghost', style: style);
    if (aligned) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, color: TraceColors.mint, size: 30),
          Text('Aligned', style: TextStyle(color: TraceColors.mint, fontWeight: FontWeight.w800)),
        ],
      );
    }
    final h = dHeading;
    final p = dPitch;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (h == null || p == null)
          const Text('Finding your angle…', style: style)
        else ...[
          if (h.abs() > alignTolerance)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(h < 0 ? Icons.rotate_left_rounded : Icons.rotate_right_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 4),
                Text('${h.abs().round()}°', style: style),
              ],
            ),
          if (p.abs() > alignTolerance)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(p > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 4),
                Text('${p.abs().round()}°', style: style),
              ],
            ),
        ],
      ],
    );
  }
}
