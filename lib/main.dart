import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:brutus_app/app.dart';
import 'package:brutus_app/core/constants/api_constants.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
