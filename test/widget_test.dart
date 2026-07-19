import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:brutus_app/features/settings/settings_screen.dart';
import 'package:brutus_app/features/tools/tools_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Plain Hive.init (no path_provider platform channel) for tests.
    final dir = await Directory.systemTemp.createTemp('brutus_test_');
    Hive.init(dir.path);
    await Hive.openBox('preferences');
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('Tools screen renders every section and the coming-soon bridge',
      (tester) async {
    // Tall viewport so every lazily-built sliver section is on screen.
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ToolsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('Web Search'), findsOneWidget);
    expect(find.text('RAG Oracle'), findsOneWidget);
    expect(find.text('Robot Control'), findsOneWidget);
    expect(find.text('Desktop Bridge'), findsOneWidget);

    // Desktop Bridge is honest about its status: tapping shows a
    // coming-soon snackbar instead of doing nothing.
    await tester.tap(find.text('Desktop Bridge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('coming soon'), findsOneWidget);

    // Let the snackbar's auto-dismiss timer elapse so no timers leak.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('Settings shows the persisted user profile and edits it',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final box = Hive.box('preferences');
    // Hive writes are real I/O — run them outside the fake-async test zone
    // or the awaited future never completes and the test deadlocks.
    await tester.runAsync(() async {
      await box.put('brutus_user_name', 'Test Pilot');
      await box.put('brutus_voice_profile', 'FEMALE');
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Real persisted data, not placeholders.
    expect(find.text('Test Pilot'), findsOneWidget);
    expect(find.textContaining('Aoede'), findsOneWidget);
    expect(find.text('TP'), findsOneWidget); // initials chip

    // Open the Personality sheet and change the name.
    await tester.tap(find.text('Personality'));
    await tester.pumpAndSettle();
    expect(find.text('YOUR NAME'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Neo Anderson');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // UI + in-memory Hive keystore both updated — the same key the Gemini
    // system prompt reads on the next connect.
    expect(find.text('Neo Anderson'), findsOneWidget);
    expect(box.get('brutus_user_name'), 'Neo Anderson');
  });
}
