import 'package:flutter/material.dart';

class OpenCodeThemeProvider {
  static final _notifier = ValueNotifier<ThemeMode>(ThemeMode.system);

  static ValueNotifier<ThemeMode> get notifier => _notifier;

  static void setThemeMode(ThemeMode mode) {
    _notifier.value = mode;
  }
}
