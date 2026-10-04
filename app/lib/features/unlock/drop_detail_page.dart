import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/api/models.dart';
import '../../core/api/trace_api.dart';
import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/drop_glyph.dart';
import '../../core/events.dart';
import '../../ui/trace_image.dart';
import '../echoes/echoes_section.dart';
import '../relays/relay_panel.dart';
import '../thennow/then_now_section.dart';
import '../trails/trail_banner.dart';

/// The opened drop. Reopenable from anywhere once unlocked. Pops `true` if the map should refresh.
class DropDetailPage extends StatefulWidget {
  const DropDetailPage({super.key, required DropContent this.content, this.justUnlocked = false}) : dropId = null;

  const DropDetailPage.load({super.key, required String this.dropId})
      : content = null,
        justUnlocked = false;

  final DropContent? content;
  final String? dropId;
  final bool justUnlocked;

  @override
  State<DropDetailPage> createState() => _DropDetailPageState();
}

class _DropDetailPageState extends State<DropDetailPage> {
  DropContent? _content;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    _content = widget.content;
    if (_content == null) _load();
  }

  Future<void> _load() async {
    try {
      final c = await context.read<TraceApi>().drop(widget.dropId ?? _content!.id);
      if (mounted) setState(() => _content = c);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _showMenu(DropContent c) async {
    final api = context.read<TraceApi>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => _Sheet(
        children: [
          _SheetItem(icon: Icons.flag_rounded, label: 'Report this drop', value: 'report'),
          if (!c.mine)
            _SheetItem(
              icon: Icons.block_rounded,
              label: c.authorHandle == null ? 'Block the author' : 'Block @${c.authorHandle}',
              value: 'block',
              color: TraceColors.rose,
            ),
        ],
      ),
    );
    if (!mounted || action == null) return;

    if (action == 'report') {
      final reason = await showModalBottomSheet<String>(
        context: context,
        builder: (_) => const _Sheet(
          title: 'What’s wrong with it?',
          children: [
            _SheetItem(icon: Icons.sentiment_very_dissatisfied_rounded, label: 'Harassment or hate', value: 'harassment'),
            _SheetItem(icon: Icons.no_adult_content_rounded, label: 'Sexual content', value: 'sexual'),
            _SheetItem(icon: Icons.warning_amber_rounded, label: 'Dangerous or violent', value: 'violence'),
            _SheetItem(icon: Icons.person_pin_circle_rounded, label: 'Reveals someone’s private info', value: 'privacy'),
            _SheetItem(icon: Icons.campaign_rounded, label: 'Spam', value: 'spam'),
          ],
        ),
      );
      if (reason == null) return;
      try {
        await api.reportDrop(c.id, reason: reason);
        messenger.showSnackBar(const SnackBar(content: Text("Thanks for telling us. We'll take a look.")));
      } on ApiError catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } else if (action == 'block') {
      try {
        await api.blockAuthor(c.id);
        messenger.showSnackBar(const SnackBar(content: Text("Blocked. You won't see their drops again.")));
        if (mounted) context.read<DataEvents>().changed();
        nav.pop(true);
      } on ApiError catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _content;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
              child: Row(
                children: [
                  OrbButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context), tooltip: 'Back'),
                  const Spacer(),
                  if (c != null) OrbButton(icon: Icons.more_horiz_rounded, onTap: () => _showMenu(c), tooltip: 'More'),
                ],
              ),
            ),
            Expanded(
              child: c != null
                  ? _Body(
                      content: c,
                      justUnlocked: widget.justUnlocked,
                      onChanged: () {
                        context.read<DataEvents>().changed();
                        _load();
                      },
                    )
                  : Center(
                      child: _error == null
                          ? const CircularProgressIndicator(color: TraceColors.ember)
                          : Padding(
                              padding: const EdgeInsets.all(Space.xl),
                              child: Text(_error!.message, textAlign: TextAlign.center, style: serif(size: 22)),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.content, required this.justUnlocked, required this.onChanged});

  final DropContent content;
  final bool justUnlocked;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = content;
    final theme = Theme.of(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, MediaQuery.paddingOf(context).bottom + Space.xl),
      children: [
        Row(
          children: [
            Text(
              '${dropNoun(c.type).toUpperCase()}  ·  LEFT ${timeAgo(c.createdAt).toUpperCase()}',
              style: theme.textTheme.labelSmall?.copyWith(color: TraceColors.textMuted, letterSpacing: 1.4),
            ),
            const Spacer(),
            if (c.pending) const TagChip(label: 'In review', icon: Icons.schedule_rounded, color: TraceColors.amber),
            if (c.circle != null) TagChip(label: c.circle!.name, icon: Icons.group_rounded, color: TraceColors.iris),
          ],
        ),
        if (c.teaser != null) ...[
          const SizedBox(height: Space.sm + 4),
          Text(c.teaser!, style: serif(size: 30, weight: FontWeight.w500, height: 1.12)),
        ],
        const SizedBox(height: Space.lg),
        if (c.type == DropType.photo || c.type == DropType.thenNow) _Photo(content: c),
        if ((c.type == DropType.photo || c.type == DropType.thenNow) && c.body != null) const SizedBox(height: Space.lg),
        if (c.body != null) _Note(text: c.body!, framed: c.type == DropType.text),
        if (c.type == DropType.thenNow && !c.pending) ...[
          const SizedBox(height: Space.md),
          ThenNowSection(drop: c),
        ],
        if (c.relay != null && !c.pending) ...[
          const SizedBox(height: Space.xl),
          RelayPanel(dropId: c.id, relay: c.relay!, onPickedUp: onChanged),
        ],
        const SizedBox(height: Space.lg),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            c.authorHandle == null ? '— someone who was here' : '— @${c.authorHandle}',
            style: serif(size: 18, style: FontStyle.italic, color: TraceColors.textMuted),
          ),
        ),
        if (c.trail != null) ...[
          const SizedBox(height: Space.xl),
          TrailBanner(trail: c.trail!, unlocked: c.mine || c.unlockedAt != null),
        ],
        const SizedBox(height: Space.xl),
        _Stamp(content: c, justUnlocked: justUnlocked),
        if (!c.pending) ...[
          const SizedBox(height: Space.xl + Space.sm),
          EchoesSection(dropId: c.id),
        ],
      ],
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.content});

  final DropContent content;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.lg),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TraceImage(url: content.mediaUrl, bytes: content.localImage),
            if (content.type == DropType.thenNow)
              const Positioned(
                left: 12,
                top: 12,
                child: TagChip(label: 'THEN', icon: Icons.history_rounded, color: TraceColors.sun),
              ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.framed});

  final String text;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final body = Text(text, style: serif(size: 21, height: 1.5, color: const Color(0xFFEDE7DA)));
    if (!framed) return body;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.lg + 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F1B18), Color(0xFF16171D)],
        ),
        border: Border.all(color: TraceColors.sun.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('“', style: serif(size: 56, height: 0.6, color: TraceColors.ember)),
          const SizedBox(height: Space.sm),
          body,
        ],
      ),
    );
  }
}

/// The passport stamp: proof you were here.
class _Stamp extends StatelessWidget {
  const _Stamp({required this.content, required this.justUnlocked});

  final DropContent content;
  final bool justUnlocked;

  @override
  Widget build(BuildContext context) {
    final c = content;
    final line = c.mine
        ? (c.unlockCount == 0 ? 'No one has found this yet' : peopleCount(c.unlockCount).replaceFirst('been here', 'found it'))
        : peopleCount(c.unlockCount);
    final sub = c.mine
        ? 'You left this here'
        : justUnlocked
            ? 'Added to your passport. Reopen it anywhere.'
            : c.unlockedAt != null
                ? 'You were here ${timeAgo(c.unlockedAt!)}'
                : '';

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: TraceColors.mint.withValues(alpha: 0.3)),
        color: TraceColors.mint.withValues(alpha: 0.06),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: TraceColors.mint),
          const SizedBox(width: Space.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (sub.isNotEmpty) Text(sub, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TraceColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(Space.sm + 4),
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        decoration: BoxDecoration(
          color: TraceColors.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: TraceColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
                child: Align(alignment: Alignment.centerLeft, child: Text(title!, style: serif(size: 22))),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SheetItem extends StatelessWidget {
  const _SheetItem({required this.icon, required this.label, required this.value, this.color = TraceColors.text});

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      onTap: () => Navigator.pop(context, value),
    );
  }
}
