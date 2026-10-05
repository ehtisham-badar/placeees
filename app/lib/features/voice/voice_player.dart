import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import 'waveform.dart';

/// Plays an opened voice drop over its waveform.
class VoicePlayer extends StatefulWidget {
  const VoicePlayer({super.key, required this.dropId, this.url, this.bytes, this.waveform});

  final String dropId;
  final String? url;
  final Uint8List? bytes;
  final List<double>? waveform;

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  final _player = AudioPlayer();
  Duration? _duration;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _failed = false;

  /// Older recordings without a stored waveform still get a calm, stable shape.
  late final List<double> _levels = widget.waveform ??
      List.generate(waveformBars, (i) {
        final r = math.Random(widget.dropId.hashCode + i);
        return 0.25 + 0.6 * r.nextDouble();
      });

  @override
  void initState() {
    super.initState();
    _load();
    _player.positionStream.listen((p) => mounted ? setState(() => _position = p) : null);
    _player.playerStateStream.listen((s) {
      if (!mounted) return;
      final done = s.processingState == ProcessingState.completed;
      setState(() => _playing = s.playing && !done);
      if (done) {
        _player.pause();
        _player.seek(Duration.zero);
      }
    });
  }

  Future<void> _load() async {
    try {
      if (widget.bytes != null) {
        final file = File('${(await getTemporaryDirectory()).path}/trace-play-${widget.dropId}.m4a');
        await file.writeAsBytes(widget.bytes!);
        _duration = await _player.setFilePath(file.path);
      } else if (widget.url != null) {
        _duration = await _player.setUrl(widget.url!);
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration;
    final progress = total == null || total.inMilliseconds == 0 ? 0.0 : _position.inMilliseconds / total.inMilliseconds;
    return Container(
      padding: const EdgeInsets.all(Space.md + 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F1B18), Color(0xFF16171D)],
        ),
        border: Border.all(color: TraceColors.ember.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Pressable(
            onTap: total == null || _failed ? null : () => _playing ? _player.pause() : _player.play(),
            scale: 0.9,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: TraceColors.emberGradient,
                boxShadow: [BoxShadow(color: TraceColors.ember.withValues(alpha: 0.4), blurRadius: 18)],
              ),
              child: total == null && !_failed
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: TraceColors.ink),
                    )
                  : Icon(
                      _failed ? Icons.error_outline_rounded : _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: TraceColors.ink,
                      size: 32,
                    ),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WaveformBars(
                  levels: _levels,
                  progress: progress,
                  height: 48,
                  onSeek: total == null ? null : (f) => _player.seek(total * f),
                ),
                const SizedBox(height: 6),
                Text(
                  _failed
                      ? 'Couldn’t play this one.'
                      : total == null
                          ? 'Loading…'
                          : '${clock(_position)} / ${clock(total)}',
                  style: const TextStyle(
                    color: TraceColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
