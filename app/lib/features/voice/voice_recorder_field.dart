import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/pulse_rings.dart';
import 'waveform.dart';

typedef VoiceTake = ({Uint8List bytes, List<double> waveform, Duration duration});

/// Record up to 30 seconds, hear it back, keep it or try again (voice drops).
class VoiceRecorderField extends StatefulWidget {
  const VoiceRecorderField({super.key, required this.take, required this.onChanged, required this.caption});

  final VoiceTake? take;
  final ValueChanged<VoiceTake?> onChanged;
  final TextEditingController caption;

  @override
  State<VoiceRecorderField> createState() => _VoiceRecorderFieldState();
}

class _VoiceRecorderFieldState extends State<VoiceRecorderField> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _levels = <double>[];
  StreamSubscription<Amplitude>? _amp;
  Timer? _ticker;
  String? _path;
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  double _playProgress = 0;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.positionStream.listen((p) {
      final total = _player.duration ?? widget.take?.duration;
      if (total == null || total.inMilliseconds == 0 || !mounted) return;
      setState(() => _playProgress = p.inMilliseconds / total.inMilliseconds);
    });
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

  @override
  void dispose() {
    _amp?.cancel();
    _ticker?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trace needs the microphone to record a voice drop.')),
        );
      }
      return;
    }
    await _player.stop();
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/trace-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    _levels.clear();
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1),
      path: _path!,
    );
    HapticFeedback.mediumImpact();
    widget.onChanged(null);
    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
    });
    _amp = _recorder.onAmplitudeChanged(const Duration(milliseconds: 80)).listen((a) {
      if (mounted) setState(() => _levels.add(levelFromDb(a.current)));
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(milliseconds: 100));
      if (_elapsed >= voiceMaxDuration) _stop();
    });
  }

  Future<void> _stop() async {
    if (!_recording) return;
    _ticker?.cancel();
    await _amp?.cancel();
    final path = await _recorder.stop() ?? _path;
    HapticFeedback.lightImpact();
    setState(() => _recording = false);
    if (path == null || _elapsed < const Duration(milliseconds: 800)) return; // a tap, not a take
    final bytes = await File(path).readAsBytes();
    await _player.setFilePath(path);
    widget.onChanged((bytes: bytes, waveform: downsample(_levels), duration: _elapsed));
  }

  Future<void> _togglePreview() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final take = widget.take;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.lg),
            color: TraceColors.surface,
            border: Border.all(color: _recording ? TraceColors.ember.withValues(alpha: 0.5) : TraceColors.line),
          ),
          child: AnimatedSwitcher(
            duration: Motion.medium,
            child: take != null && !_recording ? _review(take) : _recorderView(),
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: widget.caption,
          maxLength: 500,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Add a caption (optional)', counterText: ''),
        ),
      ],
    );
  }

  Widget _recorderView() {
    // The most recent levels scroll in from the right while recording.
    final live = _levels.length > waveformBars ? _levels.sublist(_levels.length - waveformBars) : _levels;
    final padded = [...List.filled(waveformBars - live.length, 0.04), ...live];
    return Column(
      key: const ValueKey('recorder'),
      children: [
        SizedBox(
          height: 56,
          child: _recording
              ? WaveformBars(levels: padded, progress: 1)
              : Center(child: Text('Say something only this place should hear.', style: serif(size: 18, style: FontStyle.italic, color: TraceColors.textMuted))),
        ),
        const SizedBox(height: Space.lg),
        Pressable(
          onTap: _recording ? _stop : _start,
          scale: 0.9,
          child: SizedBox.square(
            dimension: 112,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!_recording) const PulseRings(size: 112, rings: 2),
                if (_recording)
                  SizedBox.square(
                    dimension: 96,
                    child: CircularProgressIndicator(
                      value: _elapsed.inMilliseconds / voiceMaxDuration.inMilliseconds,
                      strokeWidth: 3,
                      color: TraceColors.ember,
                      backgroundColor: TraceColors.surfaceHigh,
                    ),
                  ),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: TraceColors.emberGradient,
                    boxShadow: [BoxShadow(color: TraceColors.ember.withValues(alpha: 0.45), blurRadius: 24)],
                  ),
                  child: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded, color: TraceColors.ink, size: 34),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        Text(
          _recording ? '${clock(_elapsed)} / ${clock(voiceMaxDuration)}' : 'Tap to record · up to 30 seconds',
          style: TextStyle(
            color: _recording ? TraceColors.ember : TraceColors.textMuted,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _review(VoiceTake take) {
    return Column(
      key: const ValueKey('review'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Pressable(
              onTap: _togglePreview,
              scale: 0.9,
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: TraceColors.emberGradient),
                child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: TraceColors.ink, size: 30),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: WaveformBars(
                levels: take.waveform,
                progress: _playProgress,
                onSeek: (f) => _player.seek(take.duration * f),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Text(clock(take.duration), style: const TextStyle(color: TraceColors.textMuted, fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.refresh_rounded, size: 18, color: TraceColors.textMuted),
              label: const Text('Record again', style: TextStyle(color: TraceColors.textMuted)),
            ),
          ],
        ),
      ],
    );
  }
}
