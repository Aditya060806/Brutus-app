import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:brutus_app/core/theme/app_theme.dart';
import 'package:brutus_app/core/router/app_router.dart';
import 'package:brutus_app/providers/robot_provider.dart';
import 'package:brutus_app/providers/desktop_bridge_provider.dart';

/// Brutus Mobile — Root application widget
class BrutusApp extends ConsumerWidget {
  const BrutusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eagerly construct the robot notifier so it subscribes to the chat
    // state machine and audio playback streams from the moment the app
    // starts. Without this, the notifier wouldn't exist until the user
    // opens the Robot Control screen — meaning expressions wouldn't
    // sync if the user connected, then went straight to chat.
    ref.watch(robotProvider);

    // Eagerly construct the desktop-bridge notifier so it can auto-reconnect to
    // a previously paired PC and mirror chat/state in the background, even
    // before the user opens the Phone Bridge screen.
    ref.watch(desktopBridgeProvider);

    return MaterialApp.router(
      title: 'Brutus AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
    );
  }
}
