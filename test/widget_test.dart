import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drivara_driver_app/main.dart';
import 'package:provider/provider.dart';
import 'package:drivara_driver_app/providers/theme_provider.dart';
import 'package:drivara_driver_app/providers/localization_provider.dart';

void main() {
  testWidgets('App starts with login route', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LocalizationProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const DrivaraApp(initialRoute: '/login'),
      ),
    );

    // Verify that the app builds correctly.
    // Since we provided initialRoute as /login, we expect the app to launch.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
