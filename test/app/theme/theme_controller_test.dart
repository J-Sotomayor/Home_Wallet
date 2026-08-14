import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/app/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a new verified user keeps the default light theme', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await ThemeController.load();

    await controller.switchUser('verified-user');

    expect(controller.themeMode, ThemeMode.light);
  });

  test('a new user starts light even after another user chose dark', () async {
    SharedPreferences.setMockInitialValues({
      'homewallet_theme_mode_guest': ThemeMode.dark.name,
    });
    final controller = await ThemeController.load();

    expect(controller.themeMode, ThemeMode.light);
    await controller.select(ThemeMode.dark);

    await controller.switchUser('verified-user');

    expect(controller.themeMode, ThemeMode.light);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('homewallet_theme_mode_verified-user'),
      ThemeMode.light.name,
    );
  });

  test('a verified user keeps an existing theme preference', () async {
    SharedPreferences.setMockInitialValues({
      'homewallet_theme_mode_verified-user': ThemeMode.dark.name,
    });
    final controller = await ThemeController.load();

    await controller.switchUser('verified-user');

    expect(controller.themeMode, ThemeMode.dark);
  });
}
