import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/auth/session.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import 'onboarding_scaffold.dart';

enum _Availability { idle, checking, available, taken, invalid }

class HandlePage extends StatefulWidget {
  const HandlePage({super.key});

  @override
  State<HandlePage> createState() => _HandlePageState();
}

class _HandlePageState extends State<HandlePage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _state = _Availability.idle;
  bool _saving = false;

  static final _valid = RegExp(r'^[a-z0-9_.]{3,20}$');

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.isEmpty) return setState(() => _state = _Availability.idle);
    if (!_valid.hasMatch(value)) return setState(() => _state = _Availability.invalid);
    setState(() => _state = _Availability.checking);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final ok = await context.read<Session>().api.isHandleAvailable(value).catchError((_) => false);
      if (mounted && _controller.text == value) {
        setState(() => _state = ok ? _Availability.available : _Availability.taken);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<Session>().chooseHandle(_controller.text);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _state = _Availability.taken);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (hint, color) = switch (_state) {
      _Availability.idle => ('3–20 characters: letters, numbers, _ and .', TraceColors.textFaint),
      _Availability.checking => ('Checking…', TraceColors.textMuted),
      _Availability.available => ("It's yours.", TraceColors.mint),
      _Availability.taken => ('Taken. Try another.', TraceColors.rose),
      _Availability.invalid => ('3–20 characters: letters, numbers, _ and .', TraceColors.amber),
    };

    return OnboardingScaffold(
      step: 0,
      total: 3,
      title: 'What should\nwe call you?',
      body: 'Your handle appears on drops you sign. You can always leave one anonymously.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            inputFormatters: [
              LengthLimitingTextInputFormatter(20),
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')),
              TextInputFormatter.withFunction((_, v) => v.copyWith(text: v.text.toLowerCase())),
            ],
            decoration: InputDecoration(
              prefixText: '@ ',
              prefixStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TraceColors.ember),
              hintText: 'yourname',
              suffixIcon: AnimatedSwitcher(
                duration: Motion.fast,
                child: switch (_state) {
                  _Availability.checking => const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  _Availability.available => const Icon(Icons.check_circle_rounded, color: TraceColors.mint),
                  _Availability.taken => const Icon(Icons.cancel_rounded, color: TraceColors.rose),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
            onChanged: _onChanged,
            onSubmitted: (_) => _state == _Availability.available ? _save() : null,
          ),
          const SizedBox(height: Space.sm),
          AnimatedDefaultTextStyle(
            duration: Motion.fast,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
            child: Text(hint),
          ),
        ],
      ),
      actions: [
        PrimaryButton(
          label: 'Continue',
          loading: _saving,
          onPressed: _state == _Availability.available ? _save : null,
        ),
      ],
    );
  }
}
