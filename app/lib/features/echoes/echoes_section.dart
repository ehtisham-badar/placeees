import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/api/social.dart';
import '../../core/api/trace_api.dart';
import '../../core/format.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';

/// Replies left by people who stood in the same spot (spec F-11).
class EchoesSection extends StatefulWidget {
  const EchoesSection({super.key, required this.dropId});

  final String dropId;

  @override
  State<EchoesSection> createState() => _EchoesSectionState();
}

class _EchoesSectionState extends State<EchoesSection> {
  final _input = TextEditingController();
  List<Echo>? _echoes;
  bool _sending = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<TraceApi>().echoes(widget.dropId);
      if (mounted) setState(() => _echoes = list);
    } on ApiError {
      if (mounted) setState(() => _echoes = const []);
    }
  }

  Future<void> _send() async {
    final api = context.read<TraceApi>();
    final location = context.read<LocationService>();
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _hint = null;
    });
    try {
      final fix = await location.freshFix(maxAge: const Duration(seconds: 5));
      if (fix == null) throw const ApiError('low_accuracy');
      final echo = await api.postEcho(widget.dropId, _input.text, fix);
      HapticFeedback.mediumImpact();
      _input.clear();
      setState(() => _echoes = [...?_echoes, echo]);
      // Pick up the moderated state.
      Future.delayed(const Duration(seconds: 4), _load);
    } on ApiError catch (e) {
      setState(() => _hint = e.code == 'too_far' ? 'Echoes can only be left in person. Come back here to reply.' : e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final echoes = _echoes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Echoes', style: serif(size: 24, weight: FontWeight.w500)),
            const SizedBox(width: Space.sm),
            if (echoes != null && echoes.isNotEmpty)
              Text('${echoes.length}', style: const TextStyle(color: TraceColors.textMuted, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        Text('Left by people who stood right here.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TraceColors.textMuted)),
        const SizedBox(height: Space.md),
        if (echoes == null)
          const Padding(
            padding: EdgeInsets.all(Space.md),
            child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (echoes.isEmpty)
          Text(
            'No echoes yet. Be the first to answer.',
            style: serif(size: 17, style: FontStyle.italic, color: TraceColors.textFaint),
          )
        else
          for (final (i, e) in echoes.indexed) _EchoTile(echo: e, last: i == echoes.length - 1),
        const SizedBox(height: Space.md),
        Container(
          padding: const EdgeInsets.fromLTRB(Space.md, 4, 6, 4),
          decoration: BoxDecoration(
            color: TraceColors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: TraceColors.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 280,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Leave an echo…',
                    counterText: '',
                    filled: false,
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              _sending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : OrbButton(
                      icon: Icons.arrow_upward_rounded,
                      size: 40,
                      tooltip: 'Send echo',
                      onTap: _input.text.trim().isEmpty ? null : _send,
                    ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: Motion.fast,
          child: Text(
            key: ValueKey(_hint),
            _hint ?? 'You can only echo while you’re here.',
            style: TextStyle(color: _hint == null ? TraceColors.textFaint : TraceColors.amber, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _EchoTile extends StatelessWidget {
  const _EchoTile({required this.echo, required this.last});

  final Echo echo;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final e = echo;
    final handle = e.authorHandle ?? 'someone';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A thin thread connecting visits over time.
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (e.mine ? TraceColors.ember : TraceColors.mint).withValues(alpha: 0.14),
                  ),
                  child: Text(
                    handle.characters.first.toUpperCase(),
                    style: TextStyle(
                      color: e.mine ? TraceColors.ember : TraceColors.mint,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (!last) Expanded(child: Container(width: 1.2, color: TraceColors.line)),
              ],
            ),
          ),
          const SizedBox(width: Space.sm + 4),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : Space.md + 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('@$handle', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(width: 6),
                      Text(
                        'was here ${timeAgo(e.createdAt)}',
                        style: const TextStyle(color: TraceColors.textFaint, fontSize: 12),
                      ),
                      if (e.pending) ...[
                        const SizedBox(width: 6),
                        const Text('· in review', style: TextStyle(color: TraceColors.amber, fontSize: 12)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(e.body, style: serif(size: 17, height: 1.4, color: const Color(0xFFE7E1D6))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
