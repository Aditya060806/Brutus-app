import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/providers/ai_engine_provider.dart';
import 'package:brutus_app/providers/user_prefs_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(userPrefsProvider);

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

            // ── Profile Card (real data — tap to edit name) ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _showPersonalitySheet(context, ref);
                  },
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
                          child: Center(
                            child: Text(
                              prefs.initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                prefs.userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Voice: ${prefs.voice.label}',
                                style: const TextStyle(
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
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Iconsax.edit_2, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Edit',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.go('/settings/api-keys');
                  },
                ),
                _SettingItem(
                  icon: Iconsax.magicpen,
                  title: 'AI Providers',
                  subtitle: 'Voice & text engines · Gemini / Sarvam',
                  color: AppColors.info,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _showAiProvidersSheet(context, ref);
                  },
                ),
                _SettingItem(
                  icon: Iconsax.user,
                  title: 'Personality',
                  subtitle: 'Your name · Brutus\' voice',
                  color: AppColors.automation,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _showPersonalitySheet(context, ref);
                  },
                ),
              ],
              delay: 200,
            ),

            _buildGroup(
              context,
              'Privacy & Data',
              [
                _SettingItem(
                  icon: Iconsax.shield_tick,
                  title: 'Privacy',
                  subtitle: 'How your data is stored and used',
                  color: AppColors.info,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _showPrivacyDialog(context);
                  },
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
                  title: 'Phone Bridge',
                  subtitle: 'Link with Brutus on your PC · sync chat & state',
                  color: AppColors.maps,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.go('/settings/pc-link');
                  },
                ),
                _SettingItem(
                  icon: Iconsax.cloud_connection,
                  title: 'Cloud Sync',
                  subtitle: 'Sync data across devices',
                  color: AppColors.weather,
                  badge: 'Soon',
                  onTap: () => _comingSoon(context, 'Cloud Sync'),
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
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _showAboutDialog(context);
                  },
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

  void _comingSoon(BuildContext context, String feature) {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$feature is on the roadmap — coming soon!'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _showPersonalitySheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PersonalitySheet(),
    );
  }

  void _showAiProvidersSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AiProvidersSheet(),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy'),
        content: const SingleChildScrollView(
          child: Text(
            'Where your data lives:\n\n'
            '•  Chats, notes, and research history are stored only on this '
            'device (local Hive database).\n\n'
            '•  API keys are stored in Android\'s encrypted secure storage — '
            'never in plain text.\n\n'
            '•  Voice audio streams directly to Google\'s Gemini API over an '
            'encrypted WebSocket while Brutus is powered on. Nothing is '
            'recorded when the system is off or muted.\n\n'
            '•  Web search (Tavily), research synthesis (Groq), and image '
            'generation (HuggingFace) only receive the specific query you '
            'make.\n\n'
            '•  The accessibility and notification services run only after '
            'you explicitly enable them in Android Settings, and can be '
            'turned off there at any time.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Text('🤖', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text('Brutus AI'),
          ],
        ),
        content: const Text(
          'Version 1.0.0\n\n'
          'Your AI assistant — with a physical face.\n\n'
          'Real-time voice via Gemini Live, 25+ tools, and a servo-driven '
          'robot head over Bluetooth LE.\n\n'
          'Built with ❤️ by Aditya Pandey using Flutter, Gemini, and Arduino.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
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
                                    Row(
                                      children: [
                                        Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        if (item.badge != null) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primarySurface,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              item.badge!,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
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

/// Bottom sheet: edit the user's name + pick Brutus' voice.
/// Writes the same Hive keys the Gemini services read on connect.
class _PersonalitySheet extends ConsumerStatefulWidget {
  const _PersonalitySheet();

  @override
  ConsumerState<_PersonalitySheet> createState() => _PersonalitySheetState();
}

class _PersonalitySheetState extends ConsumerState<_PersonalitySheet> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: ref.read(userPrefsProvider).userName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(userPrefsProvider);
    final notifier = ref.read(userPrefsProvider.notifier);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Personality', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Brutus greets you by name and speaks in the voice you pick. '
            'Changes apply the next time you power Brutus on.',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary, height: 1.4),
          ),
          const SizedBox(height: 18),
          const Text(
            'YOUR NAME',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g. Aditya Pandey'),
            onSubmitted: (v) => notifier.setUserName(v),
          ),
          const SizedBox(height: 18),
          const Text(
            'BRUTUS\' VOICE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _VoiceOption(
                  label: 'Puck',
                  sub: 'Male',
                  emoji: '🧔',
                  selected: prefs.voice == VoicePref.male,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.setVoice(VoicePref.male);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _VoiceOption(
                  label: 'Aoede',
                  sub: 'Female',
                  emoji: '👩',
                  selected: prefs.voice == VoicePref.female,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.setVoice(VoicePref.female);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                notifier.setUserName(_nameController.text);
                HapticFeedback.mediumImpact();
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceOption extends StatelessWidget {
  final String label;
  final String sub;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  const _VoiceOption({
    required this.label,
    required this.sub,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySurface : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.4 : 0.5,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            Text(
              sub,
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
}

/// Bottom sheet: pick the TTS engine (Speak-for-me voice) and the text-LLM
/// engine (Deep Research + Oracle). When Sarvam TTS is selected, extra
/// dropdowns appear for the Bulbul voice + language. Writes straight through
/// [aiEngineProvider] (which persists to Hive), so selections stick.
class _AiProvidersSheet extends ConsumerWidget {
  const _AiProvidersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiEngineProvider);
    final notifier = ref.read(aiEngineProvider.notifier);

    // Guard dropdown values against any stale stored value not in the list.
    final voiceValue = AiEnginePrefs.sarvamVoices.contains(state.sarvamVoice)
        ? state.sarvamVoice
        : AiEnginePrefs.sarvamVoices.first;
    final langValue =
        AiEnginePrefs.sarvamLanguages.containsKey(state.sarvamLanguage)
            ? state.sarvamLanguage
            : 'en-IN';

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('AI Providers', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Choose which engine speaks for you and which one powers Deep '
              'Research and the Oracle. Add the matching key in Settings → '
              'API Keys.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // ── Brain: cloud vs on-device ──
            _label('BRAIN'),
            const SizedBox(height: 8),
            for (final m in BrainMode.values)
              _EngineTile(
                title: m.label,
                subtitle: m.blurb,
                selected: state.brainMode == m,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.setBrainMode(m);
                },
              ),
            const SizedBox(height: 20),

            // ── Text-to-speech ──
            _label('SPEAK FOR ME · VOICE'),
            const SizedBox(height: 8),
            for (final e in TtsEngine.values)
              _EngineTile(
                title: e.label,
                subtitle: _ttsSubtitle(e),
                selected: state.ttsEngine == e,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.setTtsEngine(e);
                },
              ),

            // Sarvam-only voice + language pickers.
            if (state.ttsEngine == TtsEngine.sarvam) ...[
              const SizedBox(height: 12),
              _label('SARVAM VOICE'),
              const SizedBox(height: 8),
              _Dropdown(
                value: voiceValue,
                items: [
                  for (final v in AiEnginePrefs.sarvamVoices)
                    DropdownMenuItem(value: v, child: Text(_capitalize(v))),
                ],
                onChanged: (v) {
                  if (v != null) notifier.setSarvamVoice(v);
                },
              ),
              const SizedBox(height: 14),
              _label('SARVAM LANGUAGE'),
              const SizedBox(height: 8),
              _Dropdown(
                value: langValue,
                items: [
                  for (final entry in AiEnginePrefs.sarvamLanguages.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: (v) {
                  if (v != null) notifier.setSarvamLanguage(v);
                },
              ),
            ],

            const SizedBox(height: 22),

            // ── Text LLM ──
            _label('RESEARCH & ORACLE · TEXT AI'),
            const SizedBox(height: 8),
            for (final e in LlmEngine.values)
              _EngineTile(
                title: e.label,
                subtitle: _llmSubtitle(e),
                selected: state.llmEngine == e,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.setLlmEngine(e);
                },
              ),

            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.of(context).pop();
                },
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textTertiary,
          letterSpacing: 1.2,
        ),
      );

  static String _ttsSubtitle(TtsEngine e) => switch (e) {
        TtsEngine.gemini => 'Brutus\' live voice (Puck / Aoede)',
        TtsEngine.sarvam => '30+ natural Indic voices · needs Sarvam key',
        TtsEngine.system => 'Android built-in · works offline',
      };

  static String _llmSubtitle(LlmEngine e) => switch (e) {
        LlmEngine.groq => 'Fast default · needs Groq key',
        LlmEngine.sarvam => 'Tuned for Indic reasoning · needs Sarvam key',
      };

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Radio-style selectable tile used for engine choices in [_AiProvidersSheet].
class _EngineTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _EngineTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color:
                selected ? AppColors.primarySurface : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.4 : 0.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textTertiary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dark-themed dropdown wrapper matching the sheet's surface styling.
class _Dropdown extends StatelessWidget {
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textTertiary,
          ),
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _SettingItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final String? badge;

  const _SettingItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.badge,
  });
}
