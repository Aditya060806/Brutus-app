import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:brutus_app/core/theme/app_colors.dart';

/// Main navigation shell with frosted-glass bottom nav
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/chat')) return 1;
    if (location.startsWith('/tools')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final index = _currentIndex(context);

    return Scaffold(
      body: child,
      extendBody: true,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: AppColors.border.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => _onTap(context, i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Iconsax.home_2),
                  selectedIcon: Icon(Iconsax.home_2, color: AppColors.primary),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Iconsax.message),
                  selectedIcon: Icon(Iconsax.message, color: AppColors.primary),
                  label: 'Chat',
                ),
                NavigationDestination(
                  icon: Icon(Iconsax.category),
                  selectedIcon: Icon(Iconsax.category, color: AppColors.primary),
                  label: 'Tools',
                ),
                NavigationDestination(
                  icon: Icon(Iconsax.setting_2),
                  selectedIcon: Icon(Iconsax.setting_2, color: AppColors.primary),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context, int index) {
    HapticFeedback.selectionClick();
    switch (index) {
      case 0:
        context.go('/home');
      case 1:
        context.go('/chat');
      case 2:
        context.go('/tools');
      case 3:
        context.go('/settings');
    }
  }
}
