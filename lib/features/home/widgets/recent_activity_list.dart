import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/shared_widgets.dart';
import 'package:brutus_app/providers/chat_provider.dart';

/// Recent Activity — derived from the real chat history (last messages and
/// tool calls), not placeholder data. Tapping any row jumps into Chat.
class RecentActivityList extends ConsumerWidget {
  const RecentActivityList({super.key});

  static const _maxItems = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild only when the message list changes — not on live transcript
    // or audio-level churn.
    final messages = ref.watch(chatProvider.select((s) => s.messages));

    if (messages.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                shape: BoxShape.circle,
                boxShadow: AppColors.primaryGlow,
              ),
              child: const Icon(Iconsax.microphone_2,
                  size: 22, color: Colors.white),
            ),
            const SizedBox(height: 14),
            const Text(
              'No activity yet',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap the orb and say hi — your conversations\nand tool runs will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                context.go('/chat');
              },
              icon: const Icon(Iconsax.message, size: 16),
              label: const Text('Start chatting'),
            ),
          ],
        ),
      );
    }

    final items = messages.reversed.take(_maxItems).toList();

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _ActivityRow(message: items[i]),
            if (i != items.length - 1)
              Divider(
                height: 0.5,
                indent: 70,
                color: AppColors.border.withValues(alpha: 0.5),
              ),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final ChatMessage message;
  const _ActivityRow({required this.message});

  @override
  Widget build(BuildContext context) {
    final look = _lookFor(message);

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        context.go('/chat');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: look.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(look.icon, size: 18, color: look.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    look.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _preview(message.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              relativeTime(message.timestamp),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _preview(String raw) {
    // Strip the tool-emoji prefix and markdown noise for a clean one-liner.
    return raw
        .replaceFirst(RegExp(r'^🔧\s*\w+:\s*'), '')
        .replaceAll(RegExp(r'[*_`#>]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  _ActivityLook _lookFor(ChatMessage m) {
    if (m.role == MessageRole.user) {
      return const _ActivityLook(
        icon: Iconsax.microphone_2,
        color: AppColors.primary,
        title: 'You said',
      );
    }
    if (m.role == MessageRole.assistant) {
      return const _ActivityLook(
        icon: Iconsax.message,
        color: AppColors.voice,
        title: 'Brutus replied',
      );
    }
    // Tool call — pick an icon per tool family.
    final tool = m.toolName ?? '';
    return switch (tool) {
      'get_weather' => const _ActivityLook(
          icon: Iconsax.cloud_sunny, color: AppColors.weather, title: 'Weather'),
      'get_stock_price' || 'compare_stocks' => const _ActivityLook(
          icon: Iconsax.chart_2, color: AppColors.stocks, title: 'Stocks'),
      'read_emails' || 'send_email' => const _ActivityLook(
          icon: Iconsax.sms, color: AppColors.email, title: 'Email'),
      'web_search' || 'google_search' => const _ActivityLook(
          icon: Iconsax.global_search, color: AppColors.info, title: 'Web search'),
      'deep_research' => const _ActivityLook(
          icon: Iconsax.search_normal_1,
          color: AppColors.research,
          title: 'Deep research'),
      'ask_oracle' => const _ActivityLook(
          icon: Iconsax.book, color: AppColors.primary, title: 'Oracle'),
      'save_note' || 'create_note' || 'read_notes' => const _ActivityLook(
          icon: Iconsax.note, color: AppColors.notes, title: 'Notes'),
      'generate_image' => const _ActivityLook(
          icon: Iconsax.gallery_edit, color: AppColors.research, title: 'AI Gallery'),
      'find_place' => const _ActivityLook(
          icon: Iconsax.location, color: AppColors.maps, title: 'Maps'),
      'play_animation' || 'play_movement_trick' => const _ActivityLook(
          icon: Iconsax.bluetooth, color: AppColors.primary, title: 'Robot'),
      'set_timer' => const _ActivityLook(
          icon: Iconsax.timer_1, color: AppColors.warning, title: 'Timer'),
      'send_whatsapp' || 'send_sms' || 'call' || 'find_contact' =>
        const _ActivityLook(
            icon: Iconsax.call, color: AppColors.success, title: 'Contact'),
      _ => const _ActivityLook(
          icon: Iconsax.cpu, color: AppColors.automation, title: 'Automation'),
    };
  }
}

class _ActivityLook {
  final IconData icon;
  final Color color;
  final String title;
  const _ActivityLook({
    required this.icon,
    required this.color,
    required this.title,
  });
}

/// "just now" / "5 min ago" / "2 hr ago" / "Yesterday" / "12 Mar".
String relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${t.day} ${months[t.month - 1]}';
}
