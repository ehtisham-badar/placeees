import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/api/conditions.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';

/// What a drop waits for (F-08) and when it opens (F-09), as chosen in the composer.
class DropRules {
  SunPhase? sun;
  WeatherKind? weather;
  TimeOfDay? hoursFrom;
  TimeOfDay? hoursTo;
  DateTimeRange? dates;
  bool reveal = false;

  DateTime? capsuleAt;
  final recipients = <String>[];

  bool get hasHours => hoursFrom != null && hoursTo != null;

  List<DropCondition> conditions(String tz) => [
        if (sun != null) SunCondition(sun!),
        if (weather != null) WeatherCondition(weather!),
        if (hasHours) TimeRangeCondition(_hhmm(hoursFrom!), _hhmm(hoursTo!), tz),
        if (dates != null) DateRangeCondition(dates!.start, dates!.end, tz),
      ];

  static String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class WaitSection extends StatelessWidget {
  const WaitSection({super.key, required this.rules, required this.tz, required this.onChanged});

  final DropRules rules;
  final String tz;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final r = rules;
    final active = r.conditions(tz);

    return _ExpandableCard(
      icon: Icons.auto_awesome_rounded,
      title: 'Make it wait for a moment',
      subtitle: active.isEmpty ? 'Opens any time' : 'Opens only ${describeConditions(active)}',
      active: active.isNotEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Caption('Light'),
          _Choices<SunPhase>(
            values: SunPhase.values,
            selected: r.sun,
            label: (p) => switch (p) {
              SunPhase.sunrise => 'Sunrise',
              SunPhase.goldenHour => 'Golden hour',
              SunPhase.sunset => 'Sunset',
              SunPhase.night => 'Night',
            },
            icon: (p) => switch (p) {
              SunPhase.sunrise => Icons.wb_twilight_rounded,
              SunPhase.goldenHour => Icons.wb_sunny_rounded,
              SunPhase.sunset => Icons.wb_twilight_rounded,
              SunPhase.night => Icons.nightlight_round,
            },
            onChanged: (v) {
              r.sun = v;
              onChanged();
            },
          ),
          const _Caption('Weather'),
          _Choices<WeatherKind>(
            values: WeatherKind.values,
            selected: r.weather,
            label: (w) => '${w.name[0].toUpperCase()}${w.name.substring(1)}',
            icon: (w) => switch (w) {
              WeatherKind.rain => Icons.water_drop_rounded,
              WeatherKind.clear => Icons.wb_sunny_outlined,
              WeatherKind.cloudy => Icons.cloud_rounded,
              WeatherKind.fog => Icons.foggy,
              WeatherKind.snow => Icons.ac_unit_rounded,
            },
            onChanged: (v) {
              r.weather = v;
              onChanged();
            },
          ),
          const _Caption('Hours'),
          Row(
            children: [
              _PickerPill(
                label: r.hoursFrom?.format(context) ?? 'From',
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: r.hoursFrom ?? const TimeOfDay(hour: 20, minute: 0));
                  if (t == null) return;
                  r.hoursFrom = t;
                  r.hoursTo ??= TimeOfDay(hour: (t.hour + 4) % 24, minute: t.minute);
                  onChanged();
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: Space.sm),
                child: Icon(Icons.arrow_forward_rounded, size: 16, color: TraceColors.textFaint),
              ),
              _PickerPill(
                label: r.hoursTo?.format(context) ?? 'To',
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: r.hoursTo ?? const TimeOfDay(hour: 4, minute: 0));
                  if (t == null) return;
                  r.hoursTo = t;
                  r.hoursFrom ??= TimeOfDay(hour: (t.hour + 20) % 24, minute: t.minute);
                  onChanged();
                },
              ),
              const Spacer(),
              if (r.hasHours)
                _Clear(onTap: () {
                  r.hoursFrom = r.hoursTo = null;
                  onChanged();
                }),
            ],
          ),
          const _Caption('Dates'),
          Row(
            children: [
              _PickerPill(
                icon: Icons.date_range_rounded,
                label: r.dates == null
                    ? 'Pick a date range'
                    : '${DateFormat.MMMd().format(r.dates!.start)} – ${DateFormat.MMMd().format(r.dates!.end)}',
                onTap: () async {
                  final now = DateTime.now();
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(now.year, now.month, now.day),
                    lastDate: DateTime(now.year + 5),
                    initialDateRange: r.dates,
                  );
                  if (range == null) return;
                  r.dates = range;
                  onChanged();
                },
              ),
              const Spacer(),
              if (r.dates != null)
                _Clear(onTap: () {
                  r.dates = null;
                  onChanged();
                }),
            ],
          ),
          const SizedBox(height: Space.md),
          _SwitchRow(
            title: 'Show the rule on the map',
            subtitle: r.reveal ? 'People know when to come back' : 'People only see that it’s waiting',
            value: r.reveal,
            onChanged: (v) {
              r.reveal = v;
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

class CapsuleSection extends StatefulWidget {
  const CapsuleSection({super.key, required this.rules, required this.onChanged});

  final DropRules rules;
  final VoidCallback onChanged;

  @override
  State<CapsuleSection> createState() => _CapsuleSectionState();
}

class _CapsuleSectionState extends State<CapsuleSection> {
  final _handle = TextEditingController();

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final r = widget.rules;
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 2);
    final day = await showDatePicker(
      context: context,
      firstDate: tomorrow,
      lastDate: DateTime(now.year + 25, now.month, now.day),
      initialDate: r.capsuleAt ?? DateTime(now.year + 1, now.month, now.day),
      helpText: 'Opens on',
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: r.capsuleAt == null ? const TimeOfDay(hour: 9, minute: 0) : TimeOfDay.fromDateTime(r.capsuleAt!),
      helpText: 'At',
    );
    r.capsuleAt = DateTime(day.year, day.month, day.day, time?.hour ?? 9, time?.minute ?? 0);
    widget.onChanged();
  }

  void _addRecipient(String raw) {
    final h = raw.trim().toLowerCase().replaceFirst('@', '');
    _handle.clear();
    if (!RegExp(r'^[a-z0-9_.]{3,20}$').hasMatch(h)) return;
    final list = widget.rules.recipients;
    if (list.contains(h) || list.length >= 20) return;
    list.add(h);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rules;
    final at = r.capsuleAt;

    return _ExpandableCard(
      icon: Icons.hourglass_top_rounded,
      title: 'Seal as a time capsule',
      subtitle: at == null
          ? 'Opens right away'
          : 'Opens ${DateFormat.yMMMMd().add_jm().format(at)}${r.recipients.isEmpty ? '' : ' · for ${r.recipients.length}'}',
      active: at != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Caption('Opens on'),
          Row(
            children: [
              _PickerPill(
                label: at == null ? 'Pick a date' : DateFormat.yMMMd().add_jm().format(at),
                icon: Icons.event_rounded,
                onTap: _pickDate,
              ),
              const Spacer(),
              if (at != null)
                _Clear(onTap: () {
                  r.capsuleAt = null;
                  r.recipients.clear();
                  widget.onChanged();
                }),
            ],
          ),
          if (at != null) ...[
            const _Caption('Only for (optional)'),
            TextField(
              controller: _handle,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[@a-zA-Z0-9_.]'))],
              decoration: const InputDecoration(prefixText: '@ ', hintText: 'add a handle, then return'),
              onSubmitted: _addRecipient,
            ),
            if (r.recipients.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final h in r.recipients)
                    InputChip(
                      label: Text('@$h'),
                      onDeleted: () {
                        r.recipients.remove(h);
                        widget.onChanged();
                      },
                      backgroundColor: TraceColors.surfaceHigh,
                      side: const BorderSide(color: TraceColors.line),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Space.sm),
            Text(
              r.recipients.isEmpty
                  ? 'Anyone who comes here after it opens can find it.'
                  : 'Only these people will see it, and they’ll be told when it opens.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TraceColors.textFaint),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpandableCard extends StatefulWidget {
  const _ExpandableCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final Widget child;

  @override
  State<_ExpandableCard> createState() => _ExpandableCardState();
}

class _ExpandableCardState extends State<_ExpandableCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.active ? TraceColors.sun : TraceColors.textMuted;
    return AnimatedContainer(
      duration: Motion.medium,
      decoration: BoxDecoration(
        color: TraceColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: widget.active ? TraceColors.sun.withValues(alpha: 0.35) : TraceColors.line),
      ),
      child: Column(
        children: [
          Pressable(
            scale: 0.99,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Row(
                children: [
                  Icon(widget.icon, color: accent),
                  const SizedBox(width: Space.sm + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: TextStyle(color: widget.active ? TraceColors.sun : TraceColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: Motion.medium,
                    child: const Icon(Icons.expand_more_rounded, color: TraceColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.medium,
            curve: Motion.curve,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md), child: widget.child)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.values,
    required this.selected,
    required this.label,
    required this.icon,
    required this.onChanged,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) label;
  final IconData Function(T) icon;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final v in values)
          Pressable(
            onTap: () => onChanged(v == selected ? null : v),
            child: AnimatedContainer(
              duration: Motion.fast,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: v == selected ? TraceColors.sun.withValues(alpha: 0.16) : TraceColors.surfaceHigh,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: v == selected ? TraceColors.sun.withValues(alpha: 0.6) : TraceColors.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon(v), size: 15, color: v == selected ? TraceColors.sun : TraceColors.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    label(v),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: v == selected ? TraceColors.text : TraceColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PickerPill extends StatelessWidget {
  const _PickerPill({required this.label, required this.onTap, this.icon = Icons.schedule_rounded});

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: TraceColors.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: TraceColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: TraceColors.textMuted),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _Clear extends StatelessWidget {
  const _Clear({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        child: const Text('Clear', style: TextStyle(color: TraceColors.textMuted)),
      );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.md, bottom: Space.sm),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(color: TraceColors.textFaint, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2),
        ),
      );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(subtitle, style: const TextStyle(color: TraceColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
        Switch.adaptive(value: value, onChanged: onChanged, activeTrackColor: TraceColors.sun),
      ],
    );
  }
}
