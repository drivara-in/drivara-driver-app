import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeString = prefs.getString('theme_mode');
    if (modeString != null) {
      if (modeString == 'light') _themeMode = ThemeMode.light;
      else if (modeString == 'dark') _themeMode = ThemeMode.dark;
      else _themeMode = ThemeMode.system;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    String modeString = 'system';
    if (mode == ThemeMode.light) modeString = 'light';
    else if (mode == ThemeMode.dark) modeString = 'dark';
    
    await prefs.setString('theme_mode', modeString);
    notifyListeners();
  }
}
