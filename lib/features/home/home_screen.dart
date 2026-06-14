
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/shared_widgets.dart';
import 'package:brutus_app/features/home/widgets/ai_orb_widget.dart';
import 'package:brutus_app/features/home/widgets/quick_actions_grid.dart';
import 'package:brutus_app/features/home/widgets/status_cards.dart';
import 'package:brutus_app/providers/chat_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final isAiActive = chatState.isConnected ||
        chatState.status == VoiceStatus.connecting ||
        chatState.status == VoiceStatus.listening ||
        chatState.status == VoiceStatus.thinking ||
        chatState.status == VoiceStatus.speaking;

    final greeting = _getGreeting();

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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.05),
                          const SizedBox(height: 4),
                          Text(
                            'Aditya',
                            style: Theme.of(context).textTheme.displaySmall,
                          ).animate().fadeIn(duration: 500.ms, delay: 100.ms).slideX(begin: -0.05),
                        ],
                      ),
                    ),
                    // Connection indicator
                    if (chatState.isConnected)
                      Container(
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            const Text('AI Online', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success)),
                          ],
                        ),
                      ).animate().fadeIn(duration: 300.ms),
                    GestureDetector(
                      onTap: () => context.go('/settings'),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: AppColors.heroGradient,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: AppColors.primaryGlow,
                        ),
                        child: const Center(
                          child: Text(
                            'AP',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ).animate().fadeIn(duration: 400.ms, delay: 200.ms).scale(begin: const Offset(0.8, 0.8)),
                  ],
                ),
              ),
            ),

            // ── AI Orb Section ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: GestureDetector(
                  onLongPress: () {
                    if (chatState.isConnected) {
                      ref.read(chatProvider.notifier).powerOff();
                    }
                  },
                  child: AiOrbWidget(
                    isActive: isAiActive,
                    statusText: _orbStatusText(chatState),
                    audioLevel: chatState.audioLevel,
                    isSpeaking: chatState.status == VoiceStatus.speaking,
                    onToggle: () => _handleOrbTap(chatState),
                  ),
                ),
              ).animate().fadeIn(duration: 600.ms, delay: 200.ms).scale(
                begin: const Offset(0.9, 0.9),
                curve: Curves.easeOutBack,
              ),
            ),

            // ── Live transcript caption (visible while you speak / Brutus speaks) ──
            if (chatState.isConnected && chatState.liveTranscript.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _LiveCaption(
                      key: ValueKey(chatState.liveOwner),
                      text: chatState.liveTranscript,
                      isAi: chatState.liveOwner == LiveTranscriptOwner.ai,
                    ),
                  ),
                ),
              ),

            // ── Error banner ──
            if (chatState.errorMessage != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Iconsax.warning_2, size: 16, color: AppColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            chatState.errorMessage!,
                            style: const TextStyle(fontSize: 12, color: AppColors.error),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => ref.read(chatProvider.notifier).powerOn(),
                          child: const Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.error)),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.02),
              ),

            // ── Status Cards ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: const StatusCards(),
              ).animate().fadeIn(duration: 500.ms, delay: 300.ms).slideY(begin: 0.05),
            ),

            // ── Quick Actions ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: const SectionHeader(
                  title: 'Quick Actions',
                  subtitle: 'Access Brutus tools instantly',
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 400.ms),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: const QuickActionsGrid(),
              ).animate().fadeIn(duration: 500.ms, delay: 450.ms).slideY(begin: 0.05),
            ),

            // ── Recent Activity ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: const SectionHeader(
                  title: 'Recent Activity',
                  subtitle: 'Your latest interactions',
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 500.ms),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                child: _buildRecentActivity(),
              ).animate().fadeIn(duration: 500.ms, delay: 550.ms).slideY(begin: 0.05),
            ),
          ],
        ),
      ),
    );
  }

  void _handleOrbTap(ChatState state) {
    final notifier = ref.read(chatProvider.notifier);
    if (state.isConnected) {
      // Already powered on — tap toggles mic mute so the user can pause
      // listening without leaving the home page.
      notifier.toggleMic();
    } else {
      // Power the system on in place. The user stays on the home page and
      // can speak directly. Long-press fully disconnects.
      notifier.powerOn();
    }
  }

  String _orbStatusText(ChatState state) {
    switch (state.status) {
      case VoiceStatus.connecting:
        return 'Powering on...';
      case VoiceStatus.thinking:
        return 'Brutus is thinking...';
      case VoiceStatus.speaking:
        return 'Brutus is speaking...';
      case VoiceStatus.error:
        return 'Tap to retry';
      case VoiceStatus.listening:
      case VoiceStatus.idle:
        if (!state.isConnected) return 'Tap to wake Brutus';
        if (state.isMicMuted) return 'Mic off — tap to listen';
        return state.isLiveMode
            ? 'Listening — just speak'
            : 'Online — open Chat to talk';
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning ☀️';
    if (hour < 17) return 'Good Afternoon 🌤️';
    if (hour < 21) return 'Good Evening 🌅';
    return 'Good Night 🌙';
  }

  Widget _buildRecentActivity() {
    final activities = [
      _ActivityItem(
        icon: Iconsax.message,
        color: AppColors.primary,
        title: 'Voice conversation',
        subtitle: 'Asked about weather in Delhi',
        time: '2 min ago',
      ),
      _ActivityItem(
        icon: Iconsax.sms,
        color: AppColors.email,
        title: 'Email read',
        subtitle: '3 new messages from Gmail',
        time: '15 min ago',
      ),
      _ActivityItem(
        icon: Iconsax.chart_2,
        color: AppColors.stocks,
        title: 'Stock check',
        subtitle: 'AAPL +2.3% today',
        time: '1 hour ago',
      ),
    ];

    return GlassCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: activities.asMap().entries.map((entry) {
          final item = entry.value;
          final isLast = entry.key == activities.length - 1;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(item.icon, size: 18, color: item.color),
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
                    Text(
                      item.time,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(
                  height: 0.5,
                  indent: 70,
                  color: AppColors.border.withValues(alpha: 0.5),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _ActivityItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String time;

  const _ActivityItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.time,
  });
}

/// Live transcript caption shown under the orb on the home page.
/// Lights up red when Brutus speaks (matching the desktop accent), neutral
/// when echoing the user's voice.
class _LiveCaption extends StatelessWidget {
  final String text;
  final bool isAi;
  const _LiveCaption({super.key, required this.text, required this.isAi});

  /// Strip markdown formatting that doesn't belong in a single-line live
  /// transcript bubble. Gemini sometimes streams `**bold**` or `# heading`
  /// in its text response and the asterisks/hashes look broken when shown
  /// as plain text. Same approach the TTS path uses.
  String _stripMd(String raw) {
    return raw
        .replaceAll(RegExp(r'\*\*'), '')
        .replaceAll(RegExp(r'__'), '')
        .replaceAll(RegExp(r'`'), '')
        .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^[-*]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final accent = isAi ? const Color(0xFFEF4444) : AppColors.textPrimary;
    final clean = _stripMd(text);
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(alpha: 0.2),
          width: 0.6,
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pad the dot down so it visually sits on the cap-height of
          // the first line of text instead of dangling above it.
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Flexible(
            child: Text(
              clean,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
