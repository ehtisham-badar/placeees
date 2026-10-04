import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/api/models.dart';
import '../../core/api/trace_api.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/drop_glyph.dart';
import '../../ui/pulse_rings.dart';
import '../../core/alerts/nearby_alerts.dart';
import '../circles/circles_page.dart';
import '../trails/stamp.dart';
import '../trails/trail_builder_page.dart';
import '../trails/trail_page.dart';
import '../unlock/drop_detail_page.dart';

/// Private record of everything you've found and left. Never visible to anyone else.
class PassportPage extends StatefulWidget {
  const PassportPage({super.key});

  @override
  State<PassportPage> createState() => _PassportPageState();
}

class _PassportPageState extends State<PassportPage> {
  Passport? _passport;
  ApiError? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await context.read<TraceApi>().passport();
      if (mounted) {
        setState(() {
          _passport = p;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _settings() async {
    final session = context.read<Session>();
    final nav = Navigator.of(context);
    final signOut = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(Space.sm + 4),
          decoration: BoxDecoration(color: TraceColors.surfaceHigh, borderRadius: BorderRadius.circular(Radii.lg)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _AlertsTile(),
              const Divider(height: 1, color: TraceColors.line),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: TraceColors.rose),
                title: const Text('Sign out', style: TextStyle(color: TraceColors.rose, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (signOut == true) {
      nav.popUntil((r) => r.isFirst);
      await session.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = context.watch<Session>().user?.handle;
    final p = _passport;
    final entries = p == null ? const <PassportEntry>[] : (_tab == 0 ? p.unlocked : p.created);

    return Scaffold(
      body: RefreshIndicator(
        color: TraceColors.ember,
        backgroundColor: TraceColors.surfaceHigh,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      OrbButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context), tooltip: 'Back'),
                      const Spacer(),
                      OrbButton(
                        icon: Icons.group_rounded,
                        tooltip: 'Circles',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CirclesPage())),
                      ),
                      const SizedBox(width: Space.sm),
                      OrbButton(icon: Icons.tune_rounded, onTap: _settings, tooltip: 'Settings'),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Passport', style: serif(size: 40, weight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      '@${handle ?? ''}  ·  only you can see this',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: Space.lg),
                    Row(
                      children: [
                        _Stat(value: p?.unlocked.length, label: 'Found', color: TraceColors.mint),
                        const SizedBox(width: Space.sm),
                        _Stat(value: p?.created.length, label: 'Left', color: TraceColors.ember),
                        const SizedBox(width: Space.sm),
                        _Stat(value: p?.peopleReached, label: 'Reached', color: TraceColors.sun),
                      ],
                    ),
                    if (p != null && p.stamps.isNotEmpty) ...[
                      const SizedBox(height: Space.lg),
                      const Text(
                        'STAMPS',
                        style: TextStyle(color: TraceColors.textFaint, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                      ),
                      const SizedBox(height: Space.sm),
                      SizedBox(
                        height: 128,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: p.stamps.length,
                          separatorBuilder: (_, _) => const SizedBox(width: Space.md),
                          itemBuilder: (_, i) => Pressable(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => TrailPage(trailId: p.stamps[i].trailId)),
                            ),
                            child: TrailStamp(
                              title: p.stamps[i].title,
                              date: p.stamps[i].completedAt,
                              size: 116,
                              tilt: i.isEven ? -0.12 : 0.08,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.lg),
                    _Tabs(index: _tab, onChanged: (i) => setState(() => _tab = i)),
                    if (_tab == 1 && p != null && p.created.where((e) => !e.rejected).length >= 3) ...[
                      const SizedBox(height: Space.md),
                      GhostButton(
                        label: 'Make a trail from your drops',
                        icon: Icons.route_rounded,
                        color: TraceColors.sun,
                        onPressed: () async {
                          final made = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(builder: (_) => TrailBuilderPage(drops: p.created)),
                          );
                          if (made == true) _load();
                        },
                      ),
                    ],
                    const SizedBox(height: Space.md),
                  ],
                ),
              ),
            ),
            if (p == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: _error != null
                      ? Text(_error!.message, style: Theme.of(context).textTheme.bodyLarge)
                      : const CircularProgressIndicator(color: TraceColors.ember),
                ),
              )
            else if (entries.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _Empty(found: _tab == 0))
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, MediaQuery.paddingOf(context).bottom + Space.lg),
                sliver: SliverList.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.sm + 4),
                  itemBuilder: (_, i) => _EntryCard(
                    entry: entries[i],
                    found: _tab == 0,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => DropDetailPage.load(dropId: entries[i].id)),
                      );
                      _load();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});

  final int? value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: TraceColors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: TraceColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (value ?? 0).toDouble()),
              duration: const Duration(milliseconds: 900),
              curve: Motion.curve,
              builder: (_, v, _) => Text(
                value == null ? '–' : v.round().toString(),
                style: serif(size: 30, weight: FontWeight.w600, color: color),
              ),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TraceColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: TraceColors.surface, borderRadius: BorderRadius.circular(100)),
      child: Row(
        children: [
          for (final (i, label) in const ['Found', 'Left by me'].indexed)
            Expanded(
              child: Pressable(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: Motion.medium,
                  curve: Motion.curve,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? TraceColors.surfaceHigh : Colors.transparent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: i == index ? TraceColors.text : TraceColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.found, required this.onTap});

  final PassportEntry entry;
  final bool found;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final color = found ? TraceColors.mint : TraceColors.ember;
    final excerpt = e.teaser ?? e.body ?? dropNoun(e.type);

    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: TraceColors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: TraceColors.line),
        ),
        child: Row(
          children: [
            DropGlyph(type: e.type, color: color),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(size: 18, weight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          found
                              ? 'Found ${timeAgo(e.unlockedAt ?? e.createdAt)}${e.authorHandle != null ? '  ·  @${e.authorHandle}' : ''}'
                              : 'Left ${timeAgo(e.createdAt)}  ·  ${e.unlockCount} found',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TraceColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (e.inReview)
              const TagChip(label: 'In review', color: TraceColors.amber)
            else if (e.rejected)
              const TagChip(label: 'Not approved', color: TraceColors.rose)
            else
              const Icon(Icons.chevron_right_rounded, color: TraceColors.textFaint),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.found});

  final bool found;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PulseRings(
            size: 120,
            rings: 2,
            color: found ? TraceColors.mint : TraceColors.ember,
            child: Icon(found ? Icons.explore_rounded : Icons.add_location_alt_rounded,
                color: found ? TraceColors.mint : TraceColors.ember),
          ),
          const SizedBox(height: Space.md),
          Text(found ? 'Nothing found yet' : 'Nothing left yet', style: serif(size: 22)),
          const SizedBox(height: Space.sm),
          Text(
            found
                ? 'Follow a glow on the map. When you get there, it’s yours to keep.'
                : 'Stand somewhere that matters to you and leave something behind.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Opt-in "you just walked past a drop" alerts (spec F-15).
class _AlertsTile extends StatefulWidget {
  const _AlertsTile();

  @override
  State<_AlertsTile> createState() => _AlertsTileState();
}

class _AlertsTileState extends State<_AlertsTile> {
  bool _busy = false;

  Future<void> _toggle(NearbyAlerts alerts, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    if (on) {
      final ok = await alerts.enable();
      if (!ok) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Nearby alerts need location set to “Allow all the time”. You can change it in Settings.'),
        ));
      }
    } else {
      await alerts.disable();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<NearbyAlerts>();
    return SwitchListTile.adaptive(
      secondary: const Icon(Icons.notifications_active_rounded, color: TraceColors.sun),
      title: const Text('Nearby alerts', style: TextStyle(fontWeight: FontWeight.w700)),
      subtitle: const Text(
        'A quiet nudge when you walk past a drop, at most 3 a day. Your location stays on your phone.',
        style: TextStyle(color: TraceColors.textMuted, fontSize: 12),
      ),
      value: alerts.enabled,
      activeTrackColor: TraceColors.sun,
      onChanged: _busy ? null : (v) => _toggle(alerts, v),
    );
  }
}
