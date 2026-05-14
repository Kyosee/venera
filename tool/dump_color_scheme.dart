// tool/dump_color_scheme.dart
// Dumps Flutter-generated ColorScheme for each preset/brightness to JSON
// for parity testing of the JS port (web/src/theme/seed-scheme.ts).
import 'dart:convert';
import 'dart:io';
import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart';

const presets = <String, Color>{
  'red':    Color(0xFFF44336),
  'pink':   Color(0xFFE91E63),
  'purple': Color(0xFF9C27B0),
  'green':  Color(0xFF4CAF50),
  'orange': Color(0xFFFF9800),
  'blue':   Color(0xFF2196F3),
  'yellow': Color(0xFFFFEB3B),
  'cyan':   Color(0xFF00BCD4),
};

String hex(Color c) {
  final argb = c.toARGB32();
  return '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

Map<String, String> schemeToMap(ColorScheme s) => {
  'primary': hex(s.primary), 'onPrimary': hex(s.onPrimary),
  'primaryContainer': hex(s.primaryContainer), 'onPrimaryContainer': hex(s.onPrimaryContainer),
  'secondary': hex(s.secondary), 'onSecondary': hex(s.onSecondary),
  'secondaryContainer': hex(s.secondaryContainer), 'onSecondaryContainer': hex(s.onSecondaryContainer),
  'tertiary': hex(s.tertiary), 'onTertiary': hex(s.onTertiary),
  'tertiaryContainer': hex(s.tertiaryContainer), 'onTertiaryContainer': hex(s.onTertiaryContainer),
  'error': hex(s.error), 'onError': hex(s.onError),
  'errorContainer': hex(s.errorContainer), 'onErrorContainer': hex(s.onErrorContainer),
  'surface': hex(s.surface), 'onSurface': hex(s.onSurface),
  'surfaceContainerHighest': hex(s.surfaceContainerHighest),
  'onSurfaceVariant': hex(s.onSurfaceVariant),
  'outline': hex(s.outline), 'outlineVariant': hex(s.outlineVariant),
  'inverseSurface': hex(s.inverseSurface), 'onInverseSurface': hex(s.onInverseSurface),
  'inversePrimary': hex(s.inversePrimary),
};

void main() {
  final out = <String, Map<String, Map<String, String>>>{};
  for (final entry in presets.entries) {
    out[entry.key] = {};
    for (final b in [Brightness.light, Brightness.dark]) {
      final scheme = SeedColorScheme.fromSeeds(
        primaryKey: entry.value, brightness: b,
        tones: FlexTones.vividBackground(b),
      );
      out[entry.key]![b == Brightness.light ? 'light' : 'dark'] = schemeToMap(scheme);
    }
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
