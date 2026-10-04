import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';

/// Shared layout for onboarding steps: progress, hero visual, title, body, actions.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.step,
    required this.total,
    required this.title,
    required this.body,
    required this.actions,
    this.hero,
    this.content,
  });

  final int step;
  final int total;
  final String title;
  final String body;
  final Widget? hero;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: Space.md),
              _Progress(step: step, total: total),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: Space.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hero != null) ...[Center(child: hero), const SizedBox(height: Space.xl)],
                      Text(title, style: serif(size: 32, weight: FontWeight.w500, height: 1.1)),
                      const SizedBox(height: Space.sm + 4),
                      Text(body, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: TraceColors.textMuted)),
                      if (content != null) ...[const SizedBox(height: Space.lg), content!],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.md),
              ...actions,
              const SizedBox(height: Space.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++)
          Expanded(
            child: AnimatedContainer(
              duration: Motion.medium,
              curve: Motion.curve,
              height: 4,
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: i <= step ? TraceColors.ember : TraceColors.surfaceHigh,
              ),
            ),
          ),
      ],
    );
  }
}

/// A single privacy promise: icon + sentence.
class PromiseRow extends StatelessWidget {
  const PromiseRow({super.key, required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: TraceColors.surfaceHigh, borderRadius: BorderRadius.circular(Radii.sm)),
            child: Icon(icon, color: TraceColors.sun, size: 20),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(text, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
