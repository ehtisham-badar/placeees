import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/api/models.dart';
import '../../core/api/trace_api.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/drop_glyph.dart';

const _minStops = 3;
const _maxStops = 15;

/// Turn your own drops into a trail (spec F-10): pick them in order, then write the clues.
/// Pops `true` when a trail was created.
class TrailBuilderPage extends StatefulWidget {
  const TrailBuilderPage({super.key, required this.drops});

  /// Your drops, newest first (from the passport).
  final List<PassportEntry> drops;

  @override
  State<TrailBuilderPage> createState() => _TrailBuilderPageState();
}

class _TrailBuilderPageState extends State<TrailBuilderPage> {
  final _title = TextEditingController();
  final _order = <String>[];
  final _clues = <String, TextEditingController>{};
  int _step = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    for (final c in _clues.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<PassportEntry> get _eligible => widget.drops.where((d) => !d.rejected).toList();

  void _toggle(String id) {
    setState(() {
      if (_order.contains(id)) {
        _order.remove(id);
      } else if (_order.length < _maxStops) {
        _order.add(id);
      }
    });
  }

  Future<void> _create() async {
    final api = context.read<TraceApi>();
    setState(() => _saving = true);
    try {
      await api.createTrail(_title.text.trim(), [
        for (final id in _order) (dropId: id, clue: _clues[id]?.text.trim()),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trail created. Let the hunt begin.')));
      Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _order.length >= _minStops && _title.text.trim().isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
              child: Row(
                children: [
                  OrbButton(
                    icon: _step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded,
                    onTap: () => _step == 0 ? Navigator.pop(context) : setState(() => _step = 0),
                    tooltip: _step == 0 ? 'Cancel' : 'Back',
                  ),
                  const Spacer(),
                  Text('Step ${_step + 1} of 2', style: const TextStyle(color: TraceColors.textMuted, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.medium,
                child: _step == 0 ? _pickStops() : _writeClues(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
              child: _step == 0
                  ? PrimaryButton(
                      label: _order.length < _minStops ? 'Pick at least $_minStops stops' : 'Next: write the clues',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: canContinue ? () => setState(() => _step = 1) : null,
                    )
                  : PrimaryButton(label: 'Create trail', icon: Icons.route_rounded, loading: _saving, onPressed: _create),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickStops() {
    final drops = _eligible;
    return ListView(
      key: const ValueKey('pick'),
      padding: const EdgeInsets.all(Space.lg),
      children: [
        Text('Make a trail', style: serif(size: 32, weight: FontWeight.w500)),
        const SizedBox(height: Space.sm),
        Text(
          'Tap your drops in the order people should find them. Each one stays hidden until the one before it is found.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: Space.lg),
        TextField(
          controller: _title,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          style: serif(size: 20),
          decoration: const InputDecoration(hintText: 'Name your trail, e.g. “Old City Hunt”', counterText: ''),
        ),
        const SizedBox(height: Space.lg),
        if (drops.length < _minStops)
          Text(
            'You need at least $_minStops public drops to make a trail. Leave a few more around a place you love.',
            style: serif(size: 18, style: FontStyle.italic, color: TraceColors.textMuted),
          ),
        for (final d in drops)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: _PickTile(entry: d, order: _order.indexOf(d.id), onTap: () => _toggle(d.id)),
          ),
      ],
    );
  }

  Widget _writeClues() {
    final byId = {for (final d in _eligible) d.id: d};
    return ListView(
      key: const ValueKey('clues'),
      padding: const EdgeInsets.all(Space.lg),
      children: [
        Text('Write the clues', style: serif(size: 32, weight: FontWeight.w500)),
        const SizedBox(height: Space.sm),
        Text(
          'Each clue appears once the previous stop is found. Make them hints, not directions.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: Space.lg),
        for (final (i, id) in _order.indexed) ...[
          Text(
            i == 0 ? 'STOP 1 · WHERE IT BEGINS' : 'STOP ${i + 1}',
            style: const TextStyle(color: TraceColors.sun, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(byId[id]?.teaser ?? byId[id]?.body ?? 'Drop', maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(size: 16, color: TraceColors.textMuted)),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _clues.putIfAbsent(id, TextEditingController.new),
            maxLength: 200,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: i == 0 ? 'How do people find the start?' : 'A clue that leads from stop $i to here',
              counterText: '',
            ),
          ),
          const SizedBox(height: Space.lg),
        ],
      ],
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile({required this.entry, required this.order, required this.onTap});

  final PassportEntry entry;

  /// Position in the trail, or -1 if not picked.
  final int order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final picked = order >= 0;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: picked ? TraceColors.sun.withValues(alpha: 0.08) : TraceColors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: picked ? TraceColors.sun.withValues(alpha: 0.5) : TraceColors.line),
        ),
        child: Row(
          children: [
            DropGlyph(type: entry.type, size: 38),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                entry.teaser ?? entry.body ?? dropNoun(entry.type),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: serif(size: 17),
              ),
            ),
            AnimatedSwitcher(
              duration: Motion.fast,
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: picked
                  ? Container(
                      key: ValueKey(order),
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: TraceColors.emberGradient),
                      child: Text('${order + 1}', style: const TextStyle(color: TraceColors.ink, fontWeight: FontWeight.w800)),
                    )
                  : Container(
                      key: const ValueKey('empty'),
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: TraceColors.textFaint)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
