enum SourcePlatformKind {
  local('local'),
  remote('remote'),
  virtual('virtual');

  const SourcePlatformKind(this.value);

  final String value;
}

enum SourceAliasType {
  canonicalKey('canonical_key'),
  displayName('display_name'),
  pluginKey('plugin_key'),
  legacyKey('legacy_key'),
  legacyInt('legacy_int');

  const SourceAliasType(this.value);

  final String value;
}

class SourcePlatformRef {
  const SourcePlatformRef({
    required this.platformId,
    required this.canonicalKey,
    required this.displayName,
    required this.kind,
    required this.matchedAlias,
    required this.matchedAliasType,
    this.legacyIntType,
  });

  final String platformId;
  final String canonicalKey;
  final String displayName;
  final SourcePlatformKind kind;
  final String matchedAlias;
  final SourceAliasType matchedAliasType;
  final int? legacyIntType;
}

class SourcePlatformResolver {
  static const localPlatformId = 'local';
  static const localCanonicalKey = 'local';
  static const localDisplayName = 'Local';
  static const _unknownPrefix = 'Unknown:';

  /// Maps a legacy integer source type to its string key. Plugin sources
  /// register their own `key.hashCode -> key` mapping at load time (see
  /// [registerLegacyIntSourceKey]); that learned mapping is persisted per-device
  /// (and exported with backups) and is the sole source of truth.
  static final _runtimeLegacySourceKeys = <int, String>{};

  /// Persistence hook invoked whenever a new `legacyIntType -> sourceKey`
  /// mapping is learned, so it can be stored per-device (and exported with
  /// backups). Wired up by the storage layer to avoid a dependency cycle.
  static void Function(int legacyIntType, String sourceKey)? onLegacyKeyLearned;

  static const local = SourcePlatformRef(
    platformId: localPlatformId,
    canonicalKey: localCanonicalKey,
    displayName: localDisplayName,
    kind: SourcePlatformKind.local,
    matchedAlias: localCanonicalKey,
    matchedAliasType: SourceAliasType.canonicalKey,
  );

  static bool isLocalKey(String key) => key == localCanonicalKey;

  static void registerLegacyIntSourceKey(int legacyIntType, String sourceKey) {
    if (legacyIntType == 0 ||
        sourceKey.isEmpty ||
        sourceKey == localCanonicalKey) {
      return;
    }
    final existing = _runtimeLegacySourceKeys[legacyIntType];
    _runtimeLegacySourceKeys[legacyIntType] = sourceKey;
    if (existing != sourceKey) {
      onLegacyKeyLearned?.call(legacyIntType, sourceKey);
    }
  }

  static void registerLegacyIntSourceKeys(Map<int, String> sourceKeys) {
    for (var entry in sourceKeys.entries) {
      registerLegacyIntSourceKey(entry.key, entry.value);
    }
  }

  static String? sourceKeyFromLegacyInt(int legacyIntType) {
    return _runtimeLegacySourceKeys[legacyIntType];
  }

  static int? legacyIntFromSourceKey(String sourceKey) {
    if (isLocalKey(sourceKey)) {
      return 0;
    }
    for (var entry in _runtimeLegacySourceKeys.entries) {
      if (entry.value == sourceKey) {
        return entry.key;
      }
    }
    return null;
  }

  static SourcePlatformRef? fromLegacyInt(int legacyIntType, {String? name}) {
    final sourceKey = sourceKeyFromLegacyInt(legacyIntType);
    if (sourceKey == null) {
      return null;
    }
    return SourcePlatformRef(
      platformId: 'remote:$sourceKey',
      canonicalKey: sourceKey,
      displayName: name ?? sourceKey,
      kind: SourcePlatformKind.remote,
      matchedAlias: legacyIntType.toString(),
      matchedAliasType: SourceAliasType.legacyInt,
      legacyIntType: legacyIntType,
    );
  }

  static SourcePlatformRef? fromTypeValue(int typeValue, {String? name}) {
    if (typeValue == 0) {
      return local;
    }
    final legacy = fromLegacyInt(typeValue, name: name);
    if (legacy != null) {
      return legacy;
    }
    return SourcePlatformRef(
      platformId: 'legacy:$typeValue',
      canonicalKey: '$_unknownPrefix$typeValue',
      displayName: name ?? '$_unknownPrefix$typeValue',
      kind: SourcePlatformKind.remote,
      matchedAlias: typeValue.toString(),
      matchedAliasType: SourceAliasType.legacyInt,
      legacyIntType: typeValue,
    );
  }

  static SourcePlatformRef fromSourceKey(String sourceKey, {String? name}) {
    if (isLocalKey(sourceKey)) {
      return local;
    }
    if (sourceKey.startsWith(_unknownPrefix)) {
      final typeValue = int.tryParse(
        sourceKey.substring(_unknownPrefix.length),
      );
      if (typeValue != null) {
        return fromTypeValue(typeValue, name: name)!;
      }
    }
    return SourcePlatformRef(
      platformId: 'remote:$sourceKey',
      canonicalKey: sourceKey,
      displayName: name ?? sourceKey,
      kind: SourcePlatformKind.remote,
      matchedAlias: sourceKey,
      matchedAliasType: SourceAliasType.pluginKey,
    );
  }
}
