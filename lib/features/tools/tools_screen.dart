import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:brutus_app/core/theme/app_colors.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

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
                      'Tools',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Everything Brutus can do for you',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.03),
            ),

            // ── Communication ──
            _buildSectionHeader(context, 'Communication', Iconsax.message),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  children: [
                    _ToolCard(
                      icon: Iconsax.sms,
                      title: 'Email',
                      subtitle: 'Read, send, and manage your Gmail',
                      color: AppColors.email,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFEF2F2), Color(0xFFFEE2E2)],
                      ),
                      onTap: () => context.go('/tools/email'),
                    ),
                  ].animate(interval: 80.ms).fadeIn(duration: 300.ms).slideX(begin: 0.03),
                ),
              ),
            ),

            // ── Information ──
            _buildSectionHeader(context, 'Information', Iconsax.chart_2),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  children: [
                    _ToolCard(
                      icon: Iconsax.global_search,
                      title: 'Web Search',
                      subtitle: 'Real-time results powered by Tavily',
                      color: AppColors.info,
                      gradient: AppColors.coolGradient,
                      onTap: () => context.go('/tools/search'),
                    ),
                    const SizedBox(height: 10),
                    _ToolCard(
                      icon: Iconsax.cloud_sunny,
                      title: 'Weather',
                      subtitle: 'Real-time weather for any city',
                      color: AppColors.weather,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
                      ),
                      onTap: () => context.go('/tools/weather'),
                    ),
                    const SizedBox(height: 10),
                    _ToolCard(
                      icon: Iconsax.chart_2,
                      title: 'Stocks',
                      subtitle: 'Live market data and charts',
                      color: AppColors.stocks,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
                      ),
                      onTap: () => context.go('/tools/stocks'),
                    ),
                  ].animate(interval: 80.ms).fadeIn(duration: 300.ms).slideX(begin: 0.03),
                ),
              ),
            ),

            // ── Productivity ──
            _buildSectionHeader(context, 'Productivity', Iconsax.note),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  children: [
                    _ToolCard(
                      icon: Iconsax.note,
                      title: 'Notes',
                      subtitle: 'Create and organize your notes',
                      color: AppColors.notes,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
                      ),
                      onTap: () => context.go('/tools/notes'),
                    ),
                    const SizedBox(height: 10),
                    _ToolCard(
                      icon: Iconsax.search_normal_1,
                      title: 'Research',
                      subtitle: 'Web research with cited synthesis',
                      color: AppColors.research,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFDF2F8), Color(0xFFFCE7F3)],
                      ),
                      onTap: () => context.go('/tools/research'),
                    ),
                    const SizedBox(height: 10),
                    _ToolCard(
                      icon: Iconsax.book,
                      title: 'RAG Oracle',
                      subtitle: 'Ask questions against your saved knowledge',
                      color: AppColors.primary,
                      gradient: AppColors.subtleGradient,
                      onTap: () => context.go('/tools/oracle'),
                    ),
                    const SizedBox(height: 10),
                    _ToolCard(
                      icon: Iconsax.gallery_edit,
                      title: 'AI Gallery',
                      subtitle: 'Generate images on demand · HuggingFace',
                      color: AppColors.research,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFEF3F2), Color(0xFFFDE8E8)],
                      ),
                      onTap: () => context.go('/tools/gallery'),
                    ),
                    const SizedBox(height: 10),
                    _ToolCard(
                      icon: Iconsax.location,
                      title: 'Maps',
                      subtitle: 'Find places · OpenStreetMap',
                      color: AppColors.maps,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
                      ),
                      onTap: () => context.go('/tools/maps'),
                    ),
                  ].animate(interval: 80.ms).fadeIn(duration: 300.ms).slideX(begin: 0.03),
                ),
              ),
            ),

            // ── Automation ──
            _buildSectionHeader(context, 'Automation', Iconsax.cpu),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                child: Column(
                  children: [
                    _ToolCard(
                      icon: Iconsax.cpu,
                      title: 'Phone Automation',
                      subtitle: 'Control your device with voice',
                      color: AppColors.automation,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF5F3FF), Color(0xFFEDE9FE)],
                      ),
                      onTap: () => context.go('/tools/automation'),
                    ),
                    const SizedBox(height: 10),
                    _ToolCard(
                      icon: Iconsax.bluetooth,
                      title: 'Robot Control',
                      subtitle: 'Drive the Brutus animatronic head',
                      color: AppColors.primary,
                      gradient: AppColors.subtleGradient,
                      onTap: () => context.go('/tools/robot'),
                    ),
                    const SizedBox(height: 10),
                    _ToolCard(
                      icon: Iconsax.eye,
                      title: 'Robot Eyes',
                      subtitle: 'ESP32-CAM live view · let Brutus see',
                      color: AppColors.info,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
                      ),
                      onTap: () => context.go('/tools/robot-eyes'),
                      badge: 'New',
                    ),
                    const SizedBox(height: 10),
                    _ToolCard(
                      icon: Iconsax.link,
                      title: 'Desktop Bridge',
                      subtitle: 'Connect to Brutus on your PC',
                      color: AppColors.info,
                      gradient: AppColors.coolGradient,
                      onTap: () {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text(
                                '🖥️ Desktop Bridge is on the roadmap — coming soon!',
                              ),
                              duration: Duration(seconds: 2),
                            ),
                          );
                      },
                      badge: 'Coming Soon',
                    ),
                  ].animate(interval: 80.ms).fadeIn(duration: 300.ms).slideX(begin: 0.03),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textTertiary),
            const SizedBox(width: 8),
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textTertiary,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Gradient? gradient;
  final VoidCallback onTap;
  final String? badge;

  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.gradient,
    required this.onTap,
    this.badge,
  });

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _pressed
                  ? widget.color.withValues(alpha: 0.35)
                  : AppColors.border,
              width: _pressed ? 1 : 0.5,
            ),
            boxShadow: _pressed
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.15),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : AppColors.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: widget.gradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icon, size: 22, color: widget.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (widget.badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.badge!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Iconsax.arrow_right_3,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
