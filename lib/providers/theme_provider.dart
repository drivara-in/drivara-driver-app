import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  // We use a private variable to store the PREFERENCE (Light, Dark, or System/Auto)
  ThemeMode _preference = ThemeMode.system;

  // The getter returns the EFFECTIVE mode to be used by MaterialApp
  // If preference is System, we calculate based on Time (Day = Light, Night = Dark)
  // This satisfies the "Day as per clock" requirement.
  ThemeMode get themeMode {
    if (_preference == ThemeMode.system) {
      final hour = DateTime.now().hour;
      // Day is 6 AM to 6 PM (18:00)
      if (hour >= 6 && hour < 18) {
        return ThemeMode.light;
      } else {
        return ThemeMode.dark;
      }
    }
    return _preference;
  }

  // Also expose the raw preference for the settings UI if needed
  ThemeMode get preference => _preference;

  ThemeProvider() {
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeString = prefs.getString('theme_mode');
    if (modeString != null) {
      if (modeString == 'light') _preference = ThemeMode.light;
      else if (modeString == 'dark') _preference = ThemeMode.dark;
      else _preference = ThemeMode.system;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _preference = mode;
    final prefs = await SharedPreferences.getInstance();
    String modeString = 'system';
    if (mode == ThemeMode.light) modeString = 'light';
    else if (mode == ThemeMode.dark) modeString = 'dark';
    
    await prefs.setString('theme_mode', modeString);
    notifyListeners();
  }
}
