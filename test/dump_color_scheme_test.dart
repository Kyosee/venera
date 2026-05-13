// test/dump_color_scheme_test.dart
// One-shot "test" that emits the Flutter-generated ColorScheme as JSON to a fixture file.
// Run via: flutter test test/dump_color_scheme_test.dart
// (Routed through `flutter test` instead of `dart run` to avoid SDK pattern-exhaustiveness issues.)
import 'dart:convert';
import 'dart:io';
import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  test('dump color scheme fixture', () {
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
    final json = const JsonEncoder.withIndent('  ').convert(out);
    File('web/src/theme/__tests__/fixtures/color-scheme.json').writeAsStringSync(json);
  });
}
