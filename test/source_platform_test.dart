import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/source_platform.dart';

void main() {
  test('resolves local source identity centrally', () {
    final platform = SourcePlatformResolver.fromSourceKey('local');

    expect(platform.platformId, 'local');
    expect(platform.canonicalKey, 'local');
    expect(platform.kind, SourcePlatformKind.local);
    expect(platform.matchedAliasType, SourceAliasType.canonicalKey);
  });

  test('preserves remote plugin source keys as canonical keys', () {
    final platform = SourcePlatformResolver.fromSourceKey(
      'source_a',
      name: 'Source A',
    );

    expect(platform.platformId, 'remote:source_a');
    expect(platform.canonicalKey, 'source_a');
    expect(platform.displayName, 'Source A');
    expect(platform.kind, SourcePlatformKind.remote);
    expect(platform.matchedAliasType, SourceAliasType.pluginKey);
  });

  test('resolves ancient enum source ints only as alias metadata', () {
    // Enum values 1-6 are the only hardcoded legacy mapping kept (for one-time
    // migration of very old backups); they are not key.hashCode values.
    final platform = SourcePlatformResolver.fromLegacyInt(5);

    expect(platform?.matchedAlias, '5');
    expect(platform?.matchedAliasType, SourceAliasType.legacyInt);
    expect(platform?.legacyIntType, 5);
    expect(platform?.canonicalKey, isNotEmpty);
  });

  test('learns hashCode-based source mappings at runtime', () {
    // Plugin sources register their own key.hashCode -> key mapping when
    // loaded; there is no hardcoded per-source table anymore.
    final intKey = 'source_b'.hashCode;
    expect(SourcePlatformResolver.sourceKeyFromLegacyInt(intKey), isNull);

    SourcePlatformResolver.registerLegacyIntSourceKey(intKey, 'source_b');

    expect(SourcePlatformResolver.sourceKeyFromLegacyInt(intKey), 'source_b');
    expect(SourcePlatformResolver.legacyIntFromSourceKey('source_b'), intKey);
  });

  test('ComicType falls back to key.hashCode without a learned mapping', () {
    // With nothing registered, fromKey uses the key's hashCode directly, so a
    // round-trip through the type value stays stable.
    expect(ComicType.fromKey('source_c').value, 'source_c'.hashCode);
  });

  test('keeps unknown legacy source ints as stable platform refs', () {
    final platform = SourcePlatformResolver.fromTypeValue(999)!;

    expect(platform.platformId, 'legacy:999');
    expect(platform.canonicalKey, 'Unknown:999');
    expect(platform.matchedAliasType, SourceAliasType.legacyInt);
    expect(platform.legacyIntType, 999);
  });
}
