import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';

import 'app.dart';
import 'appdata.dart';
import 'log.dart';

/// Launcher (home-screen / app-drawer) icon presets the user can switch
/// between. This is the OS-level app icon, not the in-app logo.
///
/// Only iOS and Android support alternate launcher icons at runtime; on desktop
/// the taskbar/Dock icon is fixed at build time, so the settings entry is
/// hidden there (see [LauncherIconService.isSupported]).
enum LauncherIconPreset {
  /// Current illustrated logo — the app's primary icon (baked into the bundle).
  defaultIcon('default'),

  /// The original Venera icon (pre-rebrand).
  orig('orig'),

  /// Flat icon variant (issue #120).
  flat('flat');

  const LauncherIconPreset(this.id);

  /// Stable id stored in settings (`appLauncherIcon`).
  final String id;

  static LauncherIconPreset fromId(String? id) {
    return LauncherIconPreset.values.firstWhere(
      (e) => e.id == id,
      orElse: () => LauncherIconPreset.defaultIcon,
    );
  }

  /// Android activity-alias name (fully-qualified) this preset maps to.
  ///
  /// The plugin resolves the name with `ComponentName(context, name)`, and the
  /// manifest namespace equals applicationId, so a fully-qualified name matches
  /// the declared alias exactly on every device.
  String get _androidAlias {
    const pkg = 'io.github.kyosee.venera';
    return switch (this) {
      LauncherIconPreset.defaultIcon => '$pkg.IconDefault',
      LauncherIconPreset.orig => '$pkg.IconOrig',
      LauncherIconPreset.flat => '$pkg.IconFlat',
    };
  }

  /// iOS alternate-icon key (from `CFBundleAlternateIcons` in Info.plist).
  ///
  /// Null means the primary icon: iOS restores it via a null iconName, so the
  /// default preset carries no alternate key.
  String? get _iosIconName {
    return switch (this) {
      LauncherIconPreset.defaultIcon => null,
      LauncherIconPreset.orig => 'IconOrig',
      LauncherIconPreset.flat => 'IconFlat',
    };
  }
}

abstract final class LauncherIconService {
  /// Whether this platform can switch launcher icons at runtime.
  static bool get isSupported => App.isAndroid || App.isIOS;

  /// The preset currently stored in settings.
  static LauncherIconPreset get current =>
      LauncherIconPreset.fromId(appdata.settings['appLauncherIcon'] as String?);

  /// Apply [preset] as the launcher icon and persist the choice.
  ///
  /// Returns true on success. On Android the visual change is applied by the
  /// plugin when the app is next removed from recents (it does not switch
  /// instantly); on iOS the system shows its own "icon changed" alert.
  static Future<bool> apply(LauncherIconPreset preset) async {
    if (!isSupported) return false;

    try {
      if (!await FlutterDynamicIconPlus.supportsAlternateIcons) {
        Log.warning('LauncherIcon', 'Alternate icons not supported on device');
        return false;
      }

      // Android matches an activity-alias name; iOS matches an Info.plist key
      // (null = primary icon).
      final iconName = App.isAndroid ? preset._androidAlias : preset._iosIconName;
      await FlutterDynamicIconPlus.setAlternateIconName(iconName: iconName);

      appdata.settings['appLauncherIcon'] = preset.id;
      appdata.saveData();
      return true;
    } catch (e, s) {
      Log.error('LauncherIcon', 'Failed to set launcher icon: $e', s);
      return false;
    }
  }
}
