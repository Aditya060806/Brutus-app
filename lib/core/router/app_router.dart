import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:brutus_app/features/home/home_screen.dart';
import 'package:brutus_app/features/chat/chat_screen.dart';
import 'package:brutus_app/features/tools/tools_screen.dart';
import 'package:brutus_app/features/settings/settings_screen.dart';
import 'package:brutus_app/features/email/email_inbox_screen.dart';
import 'package:brutus_app/features/gallery/gallery_screen.dart';
import 'package:brutus_app/features/maps/map_screen.dart';
import 'package:brutus_app/features/weather/weather_screen.dart';
import 'package:brutus_app/features/stocks/stock_screen.dart';
import 'package:brutus_app/features/notes/notes_screen.dart';
import 'package:brutus_app/features/automation/automation_screen.dart';
import 'package:brutus_app/features/oracle/oracle_screen.dart';
import 'package:brutus_app/features/research/deep_research_screen.dart';
import 'package:brutus_app/features/search/web_search_screen.dart';
import 'package:brutus_app/features/robot/robot_control_screen.dart';
import 'package:brutus_app/features/robot_eyes/robot_eyes_screen.dart';
import 'package:brutus_app/features/settings/api_keys_screen.dart';
import 'package:brutus_app/core/widgets/app_shell.dart';

/// Brutus Mobile — GoRouter configuration
final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    // Shell route wraps the bottom navigation
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) => _buildPage(
            state,
            const HomeScreen(),
          ),
        ),
        GoRoute(
          path: '/chat',
          pageBuilder: (context, state) => _buildPage(
            state,
            const ChatScreen(),
          ),
        ),
        GoRoute(
          path: '/tools',
          pageBuilder: (context, state) => _buildPage(
            state,
            const ToolsScreen(),
          ),
          routes: [
            GoRoute(
              path: 'email',
              pageBuilder: (context, state) => _slideUpPage(
                state,
                const EmailInboxScreen(),
              ),
            ),
            GoRoute(
              path: 'weather',
              pageBuilder: (context, state) => _slideUpPage(
                state,
                const WeatherScreen(),
              ),
            ),
            GoRoute(
              path: 'stocks',
              pageBuilder: (context, state) => _slideUpPage(
                state,
                const StockScreen(),
              ),
            ),
            GoRoute(
              path: 'notes',
              pageBuilder: (context, state) => _slideUpPage(
                state,
                const NotesScreen(),
              ),
            ),
            GoRoute(
              path: 'automation',
              pageBuilder: (context, state) => _slideUpPage(
                state,
                const AutomationScreen(),
              ),
            ),
            GoRoute(
              path: 'research',
              pageBuilder: (context, state) => _slideUpPage(
                state,
                const DeepResearchScreen(),
              ),
            ),
            GoRoute(
              path: 'search',
              pageBuilder: (context, state) => _slideUpPage(
                state,
                const WebSearchScreen(),
              ),
            ),
            GoRoute(
              path: 'oracle',
              pageBuilder: (context, state) => _slideUpPage(
                state,
                const OracleScreen(),
              ),
            ),
            GoRoute(
              path: 'gallery',
              pageBuilder: (context, state) => _slideUpPage(
                state,
                const GalleryScreen(),
              ),
            ),
            GoRoute(
              path: 'maps',
              pageBuilder: (context, state) => _slideUpPage(
                state,
                const MapScreen(),
              ),
            ),
            GoRoute(
              path: 'robot',
              pageBuilder: (context, state) => _slideUpPage(
                state,
                const RobotControlScreen(),
              ),
            ),
            GoRoute(
              path: 'robot-eyes',
              pageBuilder: (context, state) => _slideUpPage(
                state,
                const RobotEyesScreen(),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => _buildPage(
            state,
            const SettingsScreen(),
          ),
          routes: [
            GoRoute(
              path: 'api-keys',
              pageBuilder: (context, state) => _slideUpPage(
                state,
                const ApiKeysScreen(),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Fade transition for tab pages
CustomTransitionPage _buildPage(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 250),
  );
}

/// Slide-up transition for sub-pages
CustomTransitionPage _slideUpPage(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(
          opacity: curve,
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 300),
  );
}
