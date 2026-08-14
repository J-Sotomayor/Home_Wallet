import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  ThemeController._(this._preferences, this._userId, this._themeMode);

  factory ThemeController.memory({ThemeMode mode = defaultThemeMode}) {
    return ThemeController._(null, 'guest', mode);
  }

  static const _keyPrefix = 'homewallet_theme_mode_';
  static const defaultThemeMode = ThemeMode.light;

  final SharedPreferences? _preferences;
  String _userId;
  ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;
  String get userId => _userId;

  static Future<ThemeController> load({String userId = 'guest'}) async {
    final preferences = await SharedPreferences.getInstance();
    final value =
        userId == 'guest' ? null : preferences.getString('$_keyPrefix$userId');
    return ThemeController._(
      preferences,
      userId,
      _decode(value) ?? defaultThemeMode,
    );
  }

  Future<void> select(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _preferences?.setString('$_keyPrefix$_userId', mode.name);
  }

  Future<void> switchUser(String userId) async {
    if (userId == _userId) return;
    _userId = userId;
    final storedMode =
        userId == 'guest'
            ? null
            : _decode(_preferences?.getString('$_keyPrefix$userId'));
    if (storedMode != null) {
      _themeMode = storedMode;
    } else {
      _themeMode = defaultThemeMode;
      if (userId != 'guest') {
        await _preferences?.setString('$_keyPrefix$userId', _themeMode.name);
      }
    }
    notifyListeners();
  }

  static ThemeMode? _decode(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => null,
    };
  }
}
