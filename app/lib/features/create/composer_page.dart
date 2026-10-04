
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/api/models.dart';
import '../../core/api/trace_api.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/drop_glyph.dart';
import '../../ui/pulse_rings.dart';
import 'image_compress.dart';

const _maxCreateAccuracy = 65.0;

/// Leave a drop at exactly where you're standing. Pops `true` when one was created.
class ComposerPage extends StatefulWidget {
  const ComposerPage({super.key});

  @override
  State<ComposerPage> createState() => _ComposerPageState();
}

class _ComposerPageState extends State<ComposerPage> {
  DropType _type = DropType.text;
  final _body = TextEditingController();
  final _teaser = TextEditingController();
  Uint8List? _photo;
  bool _anonymous = false;
  bool _posting = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _body.addListener(_rebuild);
    _teaser.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _body.dispose();
    _teaser.dispose();
    super.dispose();
  }

  bool get _hasContent => switch (_type) {
        DropType.text => _body.text.trim().isNotEmpty,
        DropType.photo => _photo != null,
        DropType.voice => false,
      };

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final source = picker.supportsImageSource(ImageSource.camera) ? ImageSource.camera : ImageSource.gallery;
    final XFile? file;
    try {
      file = await picker.pickImage(source: source, requestFullMetadata: false);
    } on PlatformException {
      _toast('Camera access is needed to take a photo.');
      return;
    }
    if (file == null) return;
    final bytes = await compressPhoto(file.path);
    if (bytes == null) return _toast("That photo couldn't be prepared. Try another.");
    setState(() => _photo = bytes);
  }

  Future<void> _post() async {
    final api = context.read<TraceApi>();
    final location = context.read<LocationService>();
    FocusScope.of(context).unfocus();
    setState(() => _posting = true);
    try {
      final fix = await location.freshFix(maxAge: const Duration(seconds: 5));
      if (fix == null) throw const ApiError('low_accuracy');
      if (fix.accuracy > _maxCreateAccuracy) throw const ApiError('low_accuracy');
      await api.createDrop(
        type: _type,
        fix: fix,
        body: _body.text.trim().isEmpty ? null : _body.text.trim(),
        photoJpeg: _type == DropType.photo ? _photo : null,
        teaser: _teaser.text.trim().isEmpty ? null : _teaser.text.trim(),
        isAnonymous: _anonymous,
      );
      HapticFeedback.heavyImpact();
      setState(() => _done = true);
      await Future.delayed(const Duration(milliseconds: 2200));
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final accuracy = context.watch<LocationService>().fix?.accuracy;
    final gpsOk = accuracy != null && accuracy <= _maxCreateAccuracy;

    return Scaffold(
      body: AnimatedSwitcher(
        duration: Motion.slow,
        child: _done
            ? const _Dropped()
            : SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
                      child: Row(
                        children: [
                          OrbButton(icon: Icons.close_rounded, onTap: () => Navigator.pop(context), tooltip: 'Cancel'),
                          const Spacer(),
                          _GpsPill(accuracy: accuracy),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(Space.lg),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          Text('Leave something\nfor whoever comes next.', style: serif(size: 30, weight: FontWeight.w500, height: 1.1)),
                          const SizedBox(height: Space.sm),
                          Text(
                            'It stays right here, where you’re standing. Only people who come here can open it.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: Space.lg),
                          _TypePicker(value: _type, onChanged: (t) => setState(() => _type = t)),
                          const SizedBox(height: Space.md),
                          AnimatedSwitcher(
                            duration: Motion.medium,
                            child: switch (_type) {
                              DropType.text => _NoteField(key: const ValueKey('text'), controller: _body),
                              DropType.photo => _PhotoField(
                                  key: const ValueKey('photo'),
                                  photo: _photo,
                                  caption: _body,
                                  onPick: _pickPhoto,
                                ),
                              DropType.voice => const SizedBox.shrink(),
                            },
                          ),
                          const SizedBox(height: Space.lg),
                          _Label('Hint for the map', trailing: '${_teaser.text.length}/60'),
                          const SizedBox(height: Space.sm),
                          TextField(
                            controller: _teaser,
                            maxLength: 60,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'e.g. “Best seat for the 6pm light.”',
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'People see this from afar. The rest stays sealed until they arrive.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TraceColors.textFaint),
                          ),
                          const SizedBox(height: Space.lg),
                          _AnonymousToggle(value: _anonymous, onChanged: (v) => setState(() => _anonymous = v)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
                      child: Column(
                        children: [
                          if (accuracy != null && !gpsOk)
                            const Padding(
                              padding: EdgeInsets.only(bottom: Space.sm + 4),
                              child: Text(
                                'Move to open sky for a better fix.',
                                style: TextStyle(color: TraceColors.amber, fontWeight: FontWeight.w600),
                              ),
                            ),
                          PrimaryButton(
                            label: 'Drop it here',
                            icon: Icons.place_rounded,
                            loading: _posting,
                            onPressed: _hasContent && gpsOk ? _post : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _GpsPill extends StatelessWidget {
  const _GpsPill({required this.accuracy});

  final double? accuracy;

  @override
  Widget build(BuildContext context) {
    final a = accuracy;
    final color = a == null
        ? TraceColors.textFaint
        : a <= 20
            ? TraceColors.mint
            : a <= _maxCreateAccuracy
                ? TraceColors.amber
                : TraceColors.rose;
    return TagChip(label: a == null ? 'Locating…' : 'GPS ±${a.round()} m', icon: Icons.gps_fixed_rounded, color: color);
  }
}

class _TypePicker extends StatelessWidget {
  const _TypePicker({required this.value, required this.onChanged});

  final DropType value;
  final ValueChanged<DropType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: TraceColors.surface, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        children: [
          for (final t in DropType.values)
            Expanded(
              child: Pressable(
                onTap: t == DropType.voice ? null : () => onChanged(t),
                child: AnimatedContainer(
                  duration: Motion.medium,
                  curve: Motion.curve,
                  height: 44,
                  decoration: BoxDecoration(
                    color: t == value ? TraceColors.surfaceHigh : Colors.transparent,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: t == value ? TraceColors.line : Colors.transparent),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        dropIcon(t),
                        size: 18,
                        color: t == value ? TraceColors.ember : t == DropType.voice ? TraceColors.textFaint : TraceColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        t == DropType.voice ? 'Voice · soon' : dropNoun(t),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: t == value ? TraceColors.text : t == DropType.voice ? TraceColors.textFaint : TraceColors.textMuted,
                        ),
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

class _NoteField extends StatelessWidget {
  const _NoteField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
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
        children: [
          TextField(
            controller: controller,
            minLines: 6,
            maxLines: 12,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            style: serif(size: 20, height: 1.5, color: const Color(0xFFEDE7DA)),
            decoration: InputDecoration(
              hintText: 'Write something only this place deserves…',
              hintStyle: serif(size: 20, height: 1.5, color: TraceColors.textFaint, style: FontStyle.italic),
              filled: false,
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              counterStyle: const TextStyle(color: TraceColors.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoField extends StatelessWidget {
  const _PhotoField({super.key, required this.photo, required this.caption, required this.onPick});

  final Uint8List? photo;
  final TextEditingController caption;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Pressable(
          onTap: onPick,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.lg),
            child: AspectRatio(
              aspectRatio: 4 / 5,
              child: photo != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(photo!, fit: BoxFit.cover),
                        const Positioned(
                          right: 12,
                          bottom: 12,
                          child: TagChip(label: 'Retake', icon: Icons.refresh_rounded, color: TraceColors.text),
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
                          const PulseRings(
                            size: 110,
                            rings: 2,
                            child: Icon(Icons.photo_camera_rounded, color: TraceColors.ember, size: 30),
                          ),
                          const SizedBox(height: Space.sm),
                          Text('Capture this place', style: serif(size: 20)),
                          const SizedBox(height: 4),
                          Text('What do you see, right now?', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: caption,
          maxLength: 500,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Add a caption (optional)', counterText: ''),
        ),
      ],
    );
  }
}

class _AnonymousToggle extends StatelessWidget {
  const _AnonymousToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
      decoration: BoxDecoration(color: TraceColors.surface, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        children: [
          const Icon(Icons.theater_comedy_rounded, color: TraceColors.textMuted),
          const SizedBox(width: Space.sm + 4),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Leave it anonymously', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('Your handle won’t be shown', style: TextStyle(color: TraceColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged, activeTrackColor: TraceColors.ember),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        const Spacer(),
        if (trailing != null) Text(trailing!, style: const TextStyle(color: TraceColors.textFaint, fontSize: 12)),
      ],
    );
  }
}

class _Dropped extends StatelessWidget {
  const _Dropped();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: -120, end: 0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.bounceOut,
                builder: (_, y, child) => Transform.translate(offset: Offset(0, y), child: child),
                child: const PulseRings(size: 200, child: EmberDot(size: 24)),
              ),
              const SizedBox(height: Space.lg),
              Text('Dropped.', style: serif(size: 34, weight: FontWeight.w500)),
              const SizedBox(height: Space.sm),
              Text(
                'It will glow on the map for others once it passes a quick review.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: TraceColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
