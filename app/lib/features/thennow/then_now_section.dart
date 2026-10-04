import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/api/models.dart';
import '../../core/api/signature.dart';
import '../../core/api/trace_api.dart';
import '../../core/format.dart';
import '../../core/sensors/angle_sensor.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/trace_image.dart';
import 'align_camera_page.dart';

/// Below a Then/Now photo: line up today's view, and everyone's "now" over time (spec F-14).
class ThenNowSection extends StatefulWidget {
  const ThenNowSection({super.key, required this.drop});

  final DropContent drop;

  @override
  State<ThenNowSection> createState() => _ThenNowSectionState();
}

class _ThenNowSectionState extends State<ThenNowSection> {
  List<NowPhoto>? _photos;

  @override
  void initState() {
    super.initState();
    context.read<TraceApi>().nowPhotos(widget.drop.id).then(
          (p) => mounted ? setState(() => _photos = p) : null,
          onError: (Object e) => mounted && e is ApiError ? setState(() => _photos = const []) : null,
        );
  }

  Future<void> _lineUp() async {
    final photo = await Navigator.of(context).push<NowPhoto>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => AlignCameraPage(drop: widget.drop)),
    );
    if (photo == null || !mounted) return;
    setState(() => _photos = [photo, ...?_photos]);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to this place’s timeline.')));
  }

  @override
  Widget build(BuildContext context) {
    final angle = widget.drop.angle;
    final photos = _photos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (angle != null)
          Text(
            'Taken facing ${compassPoint(angle.heading)} (${angle.heading.round()}°), '
            '${angle.pitch.abs() < 3 ? 'level' : '${angle.pitch.abs().round()}° ${angle.pitch > 0 ? 'up' : 'down'}'}.',
            style: const TextStyle(color: TraceColors.textMuted, fontSize: 13),
          ),
        const SizedBox(height: Space.md),
        PrimaryButton(label: 'Line it up', icon: Icons.center_focus_strong_rounded, onPressed: _lineUp),
        const SizedBox(height: Space.xl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Now', style: serif(size: 24, weight: FontWeight.w500)),
            const SizedBox(width: Space.sm),
            if (photos != null && photos.isNotEmpty)
              Text('${photos.length}', style: const TextStyle(color: TraceColors.textMuted, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        Text('The same view, by everyone who stood here since.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TraceColors.textMuted)),
        const SizedBox(height: Space.md),
        if (photos == null)
          const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else if (photos.isEmpty)
          Text('No one has added today’s view yet.', style: serif(size: 17, style: FontStyle.italic, color: TraceColors.textFaint))
        else
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.sm + 4),
              itemBuilder: (_, i) => _NowThumb(
                photo: photos[i],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ComparePage(then: widget.drop, now: photos[i])),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NowThumb extends StatelessWidget {
  const _NowThumb({required this.photo, required this.onTap});

  final NowPhoto photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm),
              child: SizedBox(width: 120, height: 150, child: TraceImage(url: photo.url, bytes: photo.bytes)),
            ),
            const SizedBox(height: 6),
            Text('@${photo.authorHandle ?? 'someone'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            Text(
              photo.pending ? 'in review' : timeAgo(photo.createdAt),
              style: TextStyle(color: photo.pending ? TraceColors.amber : TraceColors.textFaint, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Then and now, one over the other. Drag to fade between them.
class ComparePage extends StatefulWidget {
  const ComparePage({super.key, required this.then, required this.now});

  final DropContent then;
  final NowPhoto now;

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  double _then = 0.5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onHorizontalDragUpdate: (d) =>
            setState(() => _then = (_then + d.delta.dx / MediaQuery.sizeOf(context).width).clamp(0.0, 1.0)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            TraceImage(url: widget.now.url, bytes: widget.now.bytes),
            Opacity(opacity: _then, child: TraceImage(url: widget.then.mediaUrl, bytes: widget.then.localImage)),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: Row(
                      children: [
                        OrbButton(icon: Icons.close_rounded, onTap: () => Navigator.pop(context), tooltip: 'Close'),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _Label(title: 'NOW', sub: '@${widget.now.authorHandle ?? 'someone'} · ${timeAgo(widget.now.createdAt)}', on: _then < 0.5),
                            _Label(title: 'THEN', sub: widget.then.teaser ?? '', on: _then >= 0.5, end: true),
                          ],
                        ),
                        Slider(
                          value: _then,
                          onChanged: (v) => setState(() => _then = v),
                          activeColor: TraceColors.sun,
                          inactiveColor: Colors.white24,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.title, required this.sub, required this.on, this.end = false});

  final String title;
  final String sub;
  final bool on;
  final bool end;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: Motion.fast,
      opacity: on ? 1 : 0.5,
      child: Column(
        crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.4, shadows: [Shadow(blurRadius: 8)])),
          Text(sub, style: serif(size: 14, style: FontStyle.italic, color: Colors.white70)),
        ],
      ),
    );
  }
}
