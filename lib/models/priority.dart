import 'package:flutter/material.dart';

/// Reminder importance. Persisted by [name], so reordering is safe.
enum Priority {
  low,
  medium,
  high;

  static Priority fromName(String? value) => Priority.values.firstWhere(
        (p) => p.name == value,
        orElse: () => Priority.medium,
      );

  String get label => switch (this) {
        Priority.low => 'Low',
        Priority.medium => 'Medium',
        Priority.high => 'High',
      };

  /// Sort key: high first.
  int get rank => switch (this) {
        Priority.high => 0,
        Priority.medium => 1,
        Priority.low => 2,
      };

  /// The dot colour. Paired with a text label everywhere it appears, so colour
  /// is never the only way to tell two priorities apart.
  Color color(ColorScheme scheme) => switch (this) {
        Priority.high => const Color(0xFFEF4444),
        Priority.medium => const Color(0xFFF59E0B),
        Priority.low => scheme.outline,
      };
}
