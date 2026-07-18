import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:brutus_app/app.dart';
import 'package:brutus_app/core/constants/api_constants.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Offline resilience. google_fonts pulls Inter / Outfit from Google's CDN on
  // first use. With no network that fetch fails and, in this version, surfaces
  // as an unhandled async error that spams the log (the app itself keeps
  // running on the default font). We swallow ONLY those font fetch failures so
  // Brutus runs clean offline, which is the whole point of the on-device path.
  // Every other error still reports normally. To keep the exact fonts offline,
  // bundle them under assets (see the README note).
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    final msg = error.toString();
    if (msg.contains('gstatic.com') || msg.contains('google_fonts')) {
      return true; // handled: ignore the offline font fetch failure
    }
    return false; // not handled: let Flutter report it as usual
  };

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Open storage boxes
  await Hive.openBox(ApiConstants.boxChatHistory);
  await Hive.openBox(ApiConstants.boxNotes);
  await Hive.openBox(ApiConstants.boxPreferences);
  // Phase 3 boxes — research history, RAG vector store, oracle Q&A.
  await Hive.openBox(ApiConstants.boxResearchHistory);
  await Hive.openBox(ApiConstants.boxRagDocuments);
  await Hive.openBox(ApiConstants.boxOracleHistory);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    const ProviderScope(
      child: BrutusApp(),
    ),
  );
}
