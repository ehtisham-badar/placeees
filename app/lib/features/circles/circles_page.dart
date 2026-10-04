import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/api/social.dart';
import '../../core/api/trace_api.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/pulse_rings.dart';

/// Your private groups (spec F-12). Circle drops only glow on members' maps.
class CirclesPage extends StatefulWidget {
  const CirclesPage({super.key});

  @override
  State<CirclesPage> createState() => _CirclesPageState();
}

class _CirclesPageState extends State<CirclesPage> {
  List<Circle>? _circles;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<TraceApi>().circles();
      if (mounted) setState(() => _circles = list);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() => _circles = const []);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _create() async {
    final circle = await showModalBottomSheet<Circle>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateSheet(),
    );
    if (circle == null || !mounted) return;
    await _load();
    if (!mounted) return;
    showModalBottomSheet<void>(context: context, builder: (_) => InviteSheet(circle: circle, fresh: true));
  }

  Future<void> _join() async {
    final circle = await showModalBottomSheet<Circle>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _JoinSheet(),
    );
    if (circle == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Welcome to ${circle.name}.')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final circles = _circles;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: TraceColors.iris,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OrbButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context), tooltip: 'Back'),
                    ),
                    const SizedBox(height: Space.lg),
                    Text('Circles', style: serif(size: 40, weight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      'Small private groups. Drops left for a circle only glow for its members.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: Space.lg),
                    if (circles == null)
                      const Padding(
                        padding: EdgeInsets.all(Space.xl),
                        child: Center(child: CircularProgressIndicator(color: TraceColors.iris)),
                      )
                    else if (circles.isEmpty)
                      const _Empty()
                    else
                      for (final c in circles)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm + 4),
                          child: _CircleCard(
                            circle: c,
                            onTap: () async {
                              final left = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(builder: (_) => CircleDetailPage(circleId: c.id)),
                              );
                              if (left == true) _load();
                            },
                          ),
                        ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
              child: Row(
                children: [
                  Expanded(child: GhostButton(label: 'Join with code', icon: Icons.vpn_key_rounded, onPressed: _join)),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: PrimaryButton(
                      label: 'New circle',
                      icon: Icons.add_rounded,
                      gradient: const LinearGradient(colors: [TraceColors.iris, Color(0xFFD7CCFF)]),
                      onPressed: _create,
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

class _CircleCard extends StatelessWidget {
  const _CircleCard({required this.circle, required this.onTap});

  final Circle circle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = circle;
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
            _Monogram(name: c.name),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: serif(size: 20, weight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    '${c.memberCount} ${c.memberCount == 1 ? 'member' : 'members'}${c.isOwner ? ' · you started it' : ''}',
                    style: const TextStyle(color: TraceColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: TraceColors.textFaint),
          ],
        ),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.name, this.size = 46});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: TraceColors.iris.withValues(alpha: 0.14),
          border: Border.all(color: TraceColors.iris.withValues(alpha: 0.4)),
        ),
        child: Text(
          name.characters.first.toUpperCase(),
          style: serif(size: size * 0.42, weight: FontWeight.w600, color: TraceColors.iris),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xl),
      child: Column(
        children: [
          const PulseRings(size: 130, rings: 2, color: TraceColors.iris, child: Icon(Icons.group_rounded, color: TraceColors.iris)),
          const SizedBox(height: Space.md),
          Text('No circles yet', style: serif(size: 22)),
          const SizedBox(height: Space.sm),
          Text(
            'Start one for your friends, your hostel or your running club, or join one with an invite code.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Sheet chrome shared by the create, join and invite sheets.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(Space.sm + 4),
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            color: TraceColors.surfaceHigh,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: TraceColors.line),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}

class _CreateSheet extends StatefulWidget {
  const _CreateSheet();

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final c = await context.read<TraceApi>().createCircle(_name.text.trim());
      if (mounted) Navigator.pop(context, c);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      children: [
        Text('New circle', style: serif(size: 26, weight: FontWeight.w500)),
        const SizedBox(height: Space.md),
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Hostel 4 crew', counterText: ''),
          onSubmitted: (_) => _name.text.trim().isEmpty ? null : _save(),
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.sm),
          Text(_error!, style: const TextStyle(color: TraceColors.rose)),
        ],
        const SizedBox(height: Space.md),
        PrimaryButton(
          label: 'Create',
          loading: _saving,
          gradient: const LinearGradient(colors: [TraceColors.iris, Color(0xFFD7CCFF)]),
          onPressed: _name.text.trim().isEmpty ? null : _save,
        ),
      ],
    );
  }
}

class _JoinSheet extends StatefulWidget {
  const _JoinSheet();

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  final _code = TextEditingController();
  bool _joining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final c = await context.read<TraceApi>().joinCircle(_code.text);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, c);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _code.text.replaceAll(RegExp('[^A-Za-z0-9]'), '').length >= 6;
    return _SheetFrame(
      children: [
        Text('Join a circle', style: serif(size: 26, weight: FontWeight.w500)),
        const SizedBox(height: 4),
        const Text('Ask someone in the circle for its invite code.', style: TextStyle(color: TraceColors.textMuted)),
        const SizedBox(height: Space.md),
        TextField(
          controller: _code,
          autofocus: true,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 6, fontFamily: 'Courier'),
          inputFormatters: [
            LengthLimitingTextInputFormatter(12),
            TextInputFormatter.withFunction((_, v) => v.copyWith(text: v.text.toUpperCase())),
          ],
          decoration: const InputDecoration(hintText: 'CODE'),
          onSubmitted: (_) => ready ? _join() : null,
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.sm),
          Text(_error!, style: const TextStyle(color: TraceColors.rose)),
        ],
        const SizedBox(height: Space.md),
        PrimaryButton(
          label: 'Join',
          loading: _joining,
          gradient: const LinearGradient(colors: [TraceColors.iris, Color(0xFFD7CCFF)]),
          onPressed: ready ? _join : null,
        ),
      ],
    );
  }
}

/// The invite code, big enough to read across a table, with a copy button.
class InviteSheet extends StatelessWidget {
  const InviteSheet({super.key, required this.circle, this.fresh = false});

  final Circle circle;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final code = circle.inviteCode;
    final pretty = code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;
    return _SheetFrame(
      children: [
        Text(fresh ? '${circle.name} is ready.' : 'Invite to ${circle.name}', style: serif(size: 24, weight: FontWeight.w500)),
        const SizedBox(height: 4),
        const Text('Share this code. Anyone with it can join (up to 50 people).', style: TextStyle(color: TraceColors.textMuted)),
        const SizedBox(height: Space.lg),
        Container(
          padding: const EdgeInsets.symmetric(vertical: Space.lg),
          decoration: BoxDecoration(
            color: TraceColors.iris.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: TraceColors.iris.withValues(alpha: 0.4)),
          ),
          alignment: Alignment.center,
          child: SelectableText(
            pretty,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 5,
              color: TraceColors.iris,
              fontFamily: 'Courier',
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        GhostButton(
          label: 'Copy code',
          icon: Icons.copy_rounded,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite code copied.')));
          },
        ),
      ],
    );
  }
}

/// Members and invite code for one circle. Pops `true` if you left it.
class CircleDetailPage extends StatefulWidget {
  const CircleDetailPage({super.key, required this.circleId});

  final String circleId;

  @override
  State<CircleDetailPage> createState() => _CircleDetailPageState();
}

class _CircleDetailPageState extends State<CircleDetailPage> {
  Circle? _circle;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    context.read<TraceApi>().circle(widget.circleId).then(
          (c) => mounted ? setState(() => _circle = c) : null,
          onError: (Object e) => mounted && e is ApiError ? setState(() => _error = e) : null,
        );
  }

  Future<void> _leave(Circle c) async {
    final api = context.read<TraceApi>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => _SheetFrame(
        children: [
          Text('Leave ${c.name}?', style: serif(size: 24, weight: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text("Its drops will stop glowing on your map. You can rejoin with the code.", style: TextStyle(color: TraceColors.textMuted)),
          const SizedBox(height: Space.lg),
          GhostButton(label: 'Leave circle', color: TraceColors.rose, onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await api.leaveCircle(c.id);
      nav.pop(true);
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _circle;
    return Scaffold(
      body: SafeArea(
        child: c == null
            ? Center(
                child: _error == null ? const CircularProgressIndicator(color: TraceColors.iris) : Text(_error!.message),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
                children: [
                  Row(
                    children: [
                      OrbButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context), tooltip: 'Back'),
                      const Spacer(),
                      OrbButton(
                        icon: Icons.person_add_alt_1_rounded,
                        tooltip: 'Invite',
                        onTap: () => showModalBottomSheet<void>(context: context, builder: (_) => InviteSheet(circle: c)),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.lg),
                  Center(child: _Monogram(name: c.name, size: 84)),
                  const SizedBox(height: Space.md),
                  Text(c.name, textAlign: TextAlign.center, style: serif(size: 32, weight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(
                    '${c.memberCount} of 50 members',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: TraceColors.textMuted),
                  ),
                  const SizedBox(height: Space.xl),
                  const Text('MEMBERS', style: TextStyle(color: TraceColors.textFaint, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  const SizedBox(height: Space.sm),
                  for (final m in c.members)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: TraceColors.surfaceHigh,
                        child: Text(m.handle.characters.first.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      title: Text('@${m.handle}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: m.isOwner
                          ? const Text('started it', style: TextStyle(color: TraceColors.iris, fontWeight: FontWeight.w700, fontSize: 12))
                          : null,
                    ),
                  const SizedBox(height: Space.lg),
                  if (!c.isOwner) GhostButton(label: 'Leave circle', icon: Icons.logout_rounded, color: TraceColors.rose, onPressed: () => _leave(c)),
                ],
              ),
      ),
    );
  }
}
