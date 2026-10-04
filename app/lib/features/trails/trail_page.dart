import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/api/social.dart';
import '../../core/api/trace_api.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/pulse_rings.dart';
import '../unlock/drop_detail_page.dart';
import 'stamp.dart';

/// A trail with your progress (spec F-10). Clues reveal one stop at a time.
class TrailPage extends StatefulWidget {
  const TrailPage({super.key, required this.trailId});

  final String trailId;

  @override
  State<TrailPage> createState() => _TrailPageState();
}

class _TrailPageState extends State<TrailPage> {
  Trail? _trail;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await context.read<TraceApi>().trail(widget.trailId);
      if (mounted) setState(() => _trail = t);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _trail;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: t == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator(color: TraceColors.ember)
                    : Text(_error!.message, style: serif(size: 20)),
              )
            : RefreshIndicator(
                color: TraceColors.ember,
                onRefresh: _load,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, MediaQuery.paddingOf(context).bottom + Space.xl),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OrbButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context), tooltip: 'Back'),
                    ),
                    const SizedBox(height: Space.lg),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('TRAIL', style: const TextStyle(color: TraceColors.sun, fontWeight: FontWeight.w800, letterSpacing: 1.6, fontSize: 12)),
                              const SizedBox(height: 6),
                              Text(t.title, style: serif(size: 34, weight: FontWeight.w500, height: 1.05)),
                              const SizedBox(height: 6),
                              Text(
                                '${t.mine ? 'Your trail' : 'By @${t.creatorHandle ?? 'someone'}'} · ${t.stops.length} stops',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        if (t.completedAt != null) TrailStamp(title: t.title, date: t.completedAt!, size: 104),
                      ],
                    ),
                    const SizedBox(height: Space.lg),
                    _Progress(found: t.found, total: t.stops.length),
                    const SizedBox(height: Space.xl),
                    for (final (i, s) in t.stops.indexed)
                      _StopTile(stop: s, last: i == t.stops.length - 1, onOpen: s.dropId == null || !(s.unlocked || t.mine)
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => DropDetailPage.load(dropId: s.dropId!)),
                              )),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.found, required this.total});

  final int found;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < total; i++)
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: i < found ? 1 : 0),
                  duration: Duration(milliseconds: 500 + i * 120),
                  curve: Motion.curve,
                  builder: (_, v, _) => Container(
                    height: 6,
                    margin: EdgeInsets.only(right: i == total - 1 ? 0 : 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: Color.lerp(TraceColors.surfaceHigh, TraceColors.mint, v),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        Text(
          found == total ? 'Complete. Every stop found.' : '$found of $total found',
          style: TextStyle(color: found == total ? TraceColors.mint : TraceColors.textMuted, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({required this.stop, required this.last, this.onOpen});

  final TrailStop stop;
  final bool last;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = stop;
    final current = s.reached && !s.unlocked;
    final color = s.unlocked ? TraceColors.mint : current ? TraceColors.ember : TraceColors.textFaint;

    final Widget node = s.unlocked
        ? _Node(color: color, filled: true, child: const Icon(Icons.check_rounded, size: 16, color: TraceColors.ink))
        : current
            ? PulseRings(size: 44, rings: 2, color: color, child: _Node(color: color, child: Text('${s.seq}', style: TextStyle(color: color, fontWeight: FontWeight.w800))))
            : _Node(color: color, child: Icon(Icons.lock_rounded, size: 14, color: color));

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                SizedBox(height: 44, child: Center(child: node)),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: s.unlocked ? TraceColors.mint.withValues(alpha: 0.4) : TraceColors.line),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 10, bottom: last ? 0 : Space.lg),
              child: Pressable(
                onTap: onOpen,
                scale: 0.98,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.unlocked ? 'STOP ${s.seq} · FOUND' : current ? 'STOP ${s.seq} · LOOKING' : 'STOP ${s.seq}',
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    if (s.clue != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(Space.md),
                        decoration: BoxDecoration(
                          color: current ? TraceColors.ember.withValues(alpha: 0.08) : TraceColors.surface,
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(color: current ? TraceColors.ember.withValues(alpha: 0.35) : TraceColors.line),
                        ),
                        child: Text('“${s.clue}”', style: serif(size: 18, style: FontStyle.italic, height: 1.35)),
                      ),
                    if (s.teaser != null) ...[
                      const SizedBox(height: Space.sm),
                      Text(s.teaser!, style: serif(size: 16, color: TraceColors.textMuted)),
                    ],
                    if (current) ...[
                      const SizedBox(height: Space.sm),
                      const Text('It’s glowing on your map.', style: TextStyle(color: TraceColors.textMuted, fontSize: 13)),
                    ],
                    if (!s.reached)
                      Text(
                        'Find stop ${s.seq - 1} to reveal this clue.',
                        style: const TextStyle(color: TraceColors.textFaint, fontSize: 13),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.color, required this.child, this.filled = false});

  final Color color;
  final Widget child;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? color : TraceColors.ink,
          border: Border.all(color: color, width: 1.6),
        ),
        child: child,
      );
}
