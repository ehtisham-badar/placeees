import 'dart:io';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/api/api_error.dart';
import '../../core/auth/session.dart';
import '../../core/config.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/pulse_rings.dart';

enum _Provider { apple, google, demo, dev }

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> with SingleTickerProviderStateMixin {
  _Provider? _busy;
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  static bool _googleReady = false;

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Future<void> _signIn(_Provider provider) async {
    final session = context.read<Session>();
    setState(() => _busy = provider);
    try {
      final result = switch (provider) {
        _Provider.demo => await session.api.signInDemo('demo'),
        _Provider.dev => await session.api.signInDemo(await _devName() ?? (throw const _Cancelled())),
        _Provider.apple => await session.api.signInWithApple(await _appleToken()),
        _Provider.google => await session.api.signInWithGoogle(await _googleToken()),
      };
      await session.completeSignIn(result);
    } on _Cancelled {
      // closed the name prompt
    } on ApiError catch (e) {
      _toast(e.message);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled) _toast('Sign in with Apple failed.');
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) _toast('Google sign-in failed.');
    } catch (_) {
      _toast('Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<String> _appleToken() async {
    final cred = await SignInWithApple.getAppleIDCredential(scopes: const []);
    return cred.identityToken ?? (throw const ApiError('invalid_identity_token'));
  }

  Future<String> _googleToken() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(
        clientId: AppConfig.googleIosClientId.isEmpty ? null : AppConfig.googleIosClientId,
        serverClientId: AppConfig.googleServerClientId.isEmpty ? null : AppConfig.googleServerClientId,
      );
      _googleReady = true;
    }
    final account = await google.authenticate();
    return account.authentication.idToken ?? (throw const ApiError('invalid_identity_token'));
  }

  void _toast(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _reveal(double start, Widget child) {
    final anim = CurvedAnimation(parent: _intro, curve: Interval(start, (start + 0.5).clamp(0, 1), curve: Motion.curve));
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(anim),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      body: Stack(
        children: [
          // Warm glow bleeding in from the top.
          Positioned(
            top: -size.width * 0.6,
            left: -size.width * 0.3,
            right: -size.width * 0.3,
            child: Container(
              height: size.width * 1.4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [TraceColors.ember.withValues(alpha: 0.22), TraceColors.ink.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: Space.md),
                  _reveal(0, Text('trace', style: serif(size: 26, weight: FontWeight.w600, style: FontStyle.italic))),
                  Expanded(
                    child: Center(
                      child: FadeTransition(
                        opacity: _intro,
                        child: PulseRings(size: min(size.width * 0.82, 340), child: const EmberDot(size: 22)),
                      ),
                    ),
                  ),
                  _reveal(
                    0.15,
                    Text(
                      'Some things,\nyou have to be there for.',
                      style: serif(size: 32, weight: FontWeight.w500, height: 1.1),
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  _reveal(
                    0.3,
                    Text(
                      'Leave notes and photos at real places. Others can only open them by walking there.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: TraceColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                  _reveal(0.45, _buttons()),
                  const SizedBox(height: Space.md),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Dev sign-in: the name is the account (same name = same account).
  Future<String?> _devName() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TraceColors.surfaceHigh,
        title: Text('Developer sign-in', style: serif(size: 22)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Any name, e.g. ehtisham'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Continue')),
        ],
      ),
    );
    controller.dispose();
    return name == null || name.isEmpty ? null : name;
  }

  Widget _buttons() {
    if (AppConfig.devLogin && !AppConfig.isDemo) {
      return Column(
        children: [
          PrimaryButton(
            label: 'Developer sign-in',
            icon: Icons.terminal_rounded,
            loading: _busy == _Provider.dev,
            onPressed: _busy == null ? () => _signIn(_Provider.dev) : null,
          ),
          const SizedBox(height: Space.sm + 4),
          Text(
            'Connected to ${AppConfig.apiUrl}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TraceColors.textFaint),
          ),
        ],
      );
    }
    if (AppConfig.isDemo) {
      return Column(
        children: [
          PrimaryButton(
            label: 'Explore the demo',
            icon: Icons.explore_rounded,
            loading: _busy == _Provider.demo,
            onPressed: _busy == null ? () => _signIn(_Provider.demo) : null,
          ),
          const SizedBox(height: Space.sm + 4),
          Text(
            'Demo mode · simulated drops around you, no account needed',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TraceColors.textFaint),
          ),
        ],
      );
    }
    return Column(
      children: [
        if (Platform.isIOS) ...[
          _AppleButton(loading: _busy == _Provider.apple, onPressed: _busy == null ? () => _signIn(_Provider.apple) : null),
          const SizedBox(height: Space.sm + 4),
        ],
        GhostButton(
          label: 'Continue with Google',
          icon: Icons.g_mobiledata_rounded,
          onPressed: _busy == null ? () => _signIn(_Provider.google) : null,
        ),
        const SizedBox(height: Space.md),
        Text(
          'Your live location is never shared with anyone.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TraceColors.textFaint),
        ),
      ],
    );
  }
}



class _AppleButton extends StatelessWidget {
  const _AppleButton({required this.loading, this.onPressed});

  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      child: Container(
        height: 58,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Radii.md)),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.apple, color: Colors.black, size: 24),
                  SizedBox(width: 8),
                  Text('Sign in with Apple', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 16)),
                ],
              ),
      ),
    );
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
