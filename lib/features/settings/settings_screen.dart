import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:brutus_app/core/theme/app_colors.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Configure your Brutus experience',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms),
            ),

            // ── Profile Card ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppColors.heroGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppColors.primaryGlow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text(
                            'AP',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Aditya Pandey',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Brutus Premium',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Pro',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 100.ms).scale(
                begin: const Offset(0.95, 0.95),
              ),
            ),

            // ── Settings Groups ──
            _buildGroup(
              context,
              'General',
              [
                _SettingItem(
                  icon: Iconsax.key,
                  title: 'API Keys',
                  subtitle: 'Manage your API keys',
                  color: AppColors.primary,
                  onTap: () => context.go('/settings/api-keys'),
                ),
                _SettingItem(
                  icon: Iconsax.user,
                  title: 'Personality',
                  subtitle: 'Customize Brutus\' behavior',
                  color: AppColors.automation,
                  onTap: () {},
                ),
                _SettingItem(
                  icon: Iconsax.notification,
                  title: 'Notifications',
                  subtitle: 'Push and sound settings',
                  color: AppColors.warning,
                  onTap: () {},
                ),
              ],
              delay: 200,
            ),

            _buildGroup(
              context,
              'Security',
              [
                _SettingItem(
                  icon: Iconsax.finger_scan,
                  title: 'Biometric Lock',
                  subtitle: 'Fingerprint / Face unlock',
                  color: AppColors.success,
                  onTap: () {},
                  trailing: Switch(
                    value: true,
                    onChanged: (v) {},
                  ),
                ),
                _SettingItem(
                  icon: Iconsax.shield_tick,
                  title: 'Privacy',
                  subtitle: 'Data and permissions',
                  color: AppColors.info,
                  onTap: () {},
                ),
              ],
              delay: 300,
            ),

            _buildGroup(
              context,
              'Connection',
              [
                _SettingItem(
                  icon: Iconsax.monitor,
                  title: 'Desktop Bridge',
                  subtitle: 'Connect to Brutus Desktop',
                  color: AppColors.maps,
                  onTap: () {},
                ),
                _SettingItem(
                  icon: Iconsax.cloud_connection,
                  title: 'Cloud Sync',
                  subtitle: 'Sync data across devices',
                  color: AppColors.weather,
                  onTap: () {},
                ),
              ],
              delay: 400,
            ),

            _buildGroup(
              context,
              'About',
              [
                _SettingItem(
                  icon: Iconsax.info_circle,
                  title: 'About Brutus',
                  subtitle: 'Version 1.0.0',
                  color: AppColors.textSecondary,
                  onTap: () {},
                ),
              ],
              delay: 500,
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildGroup(
    BuildContext context,
    String title,
    List<_SettingItem> items, {
    int delay = 0,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border, width: 0.5),
                boxShadow: AppColors.cardShadow,
              ),
              child: Column(
                children: items.asMap().entries.map((entry) {
                  final item = entry.value;
                  final isLast = entry.key == items.length - 1;

                  return Column(
                    children: [
                      InkWell(
                        onTap: item.onTap,
                        borderRadius: BorderRadius.vertical(
                          top: entry.key == 0
                              ? const Radius.circular(16)
                              : Radius.zero,
                          bottom: isLast
                              ? const Radius.circular(16)
                              : Radius.zero,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: item.color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  item.icon,
                                  size: 18,
                                  color: item.color,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.subtitle,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              item.trailing ??
                                  const Icon(
                                    Iconsax.arrow_right_3,
                                    size: 16,
                                    color: AppColors.textTertiary,
                                  ),
                            ],
                          ),
                        ),
                      ),
                      if (!isLast)
                        Divider(
                          height: 0.5,
                          indent: 68,
                          color: AppColors.border.withValues(alpha: 0.5),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms, delay: Duration(milliseconds: delay)).slideY(begin: 0.03),
    );
  }
}

class _SettingItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SettingItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.trailing,
  });
}
