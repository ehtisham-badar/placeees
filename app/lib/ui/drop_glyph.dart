import 'package:flutter/material.dart';

import '../core/api/models.dart';
import '../core/theme/tokens.dart';

IconData dropIcon(DropType t) => switch (t) {
      DropType.text => Icons.edit_note_rounded,
      DropType.photo => Icons.photo_camera_rounded,
      DropType.voice => Icons.graphic_eq_rounded,
    };

String dropNoun(DropType t) => switch (t) {
      DropType.text => 'Note',
      DropType.photo => 'Photo',
      DropType.voice => 'Voice',
    };

/// Type icon in a tinted disc.
class DropGlyph extends StatelessWidget {
  const DropGlyph({super.key, required this.type, this.color = TraceColors.ember, this.size = 44});

  final DropType type;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Icon(dropIcon(type), color: color, size: size * 0.48),
    );
  }
}

/// Small rounded label, e.g. "3 days ago" or "In review".
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, this.icon, this.color = TraceColors.textMuted});

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 5)],
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
