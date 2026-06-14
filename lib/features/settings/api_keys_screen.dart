import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/shared_widgets.dart';
import 'package:brutus_app/data/services/secure_storage_service.dart';
import 'package:brutus_app/providers/chat_provider.dart';

enum _KeyKind { gemini, groq, tavily, huggingface }

class _ApiKeyDef {
  final _KeyKind kind;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  const _ApiKeyDef({
    required this.kind,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class ApiKeysScreen extends ConsumerStatefulWidget {
  const ApiKeysScreen({super.key});
  @override
  ConsumerState<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends ConsumerState<ApiKeysScreen> {
  final _defs = const [
    _ApiKeyDef(
      kind: _KeyKind.gemini,
      name: 'Gemini API Key',
      description: 'Google AI Studio — required for voice + text',
      icon: Iconsax.cpu,
      color: AppColors.primary,
    ),
    _ApiKeyDef(
      kind: _KeyKind.groq,
      name: 'Groq API Key',
      description: 'Fast inference engine',
      icon: Iconsax.flash_1,
      color: AppColors.success,
    ),
    _ApiKeyDef(
      kind: _KeyKind.tavily,
      name: 'Tavily API Key',
      description: 'Web search engine',
      icon: Iconsax.search_normal_1,
      color: AppColors.research,
    ),
    _ApiKeyDef(
      kind: _KeyKind.huggingface,
      name: 'HuggingFace Token',
      description: 'Image generation',
      icon: Iconsax.image,
      color: AppColors.warning,
    ),
  ];

  Map<_KeyKind, bool> _isSet = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final status = await SecureStorageService.getKeyStatus();
    if (!mounted) return;
    setState(() {
      _isSet = {
        _KeyKind.gemini: status['gemini'] ?? false,
        _KeyKind.groq: status['groq'] ?? false,
        _KeyKind.tavily: status['tavily'] ?? false,
        _KeyKind.huggingface: status['huggingface'] ?? false,
      };
      _loading = false;
    });
  }

  Future<void> _save(_KeyKind kind, String value) async {
    final trimmed = value.trim();
    switch (kind) {
      case _KeyKind.gemini:
        await SecureStorageService.setGeminiKey(trimmed);
        break;
      case _KeyKind.groq:
        await SecureStorageService.setGroqKey(trimmed);
        break;
      case _KeyKind.tavily:
        await SecureStorageService.setTavilyKey(trimmed);
        break;
      case _KeyKind.huggingface:
        await SecureStorageService.setHuggingFaceKey(trimmed);
        break;
    }

    if (kind == _KeyKind.gemini) {
      // Force a fresh connection so the new key is picked up immediately.
      await ref.read(chatProvider.notifier).powerOff();
      await Future.delayed(const Duration(milliseconds: 100));
      await ref.read(chatProvider.notifier).powerOn();
    }
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('API Keys')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.infoLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Iconsax.shield_tick, color: AppColors.info, size: 20),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Keys are stored securely on-device with encrypted storage. They are never sent to any server other than the provider you set them for.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 300.ms),
                  const SizedBox(height: 20),
                  ..._defs.asMap().entries.map((entry) {
                    final def = entry.value;
                    final isSet = _isSet[def.kind] ?? false;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.all(16),
                        onTap: () => _showKeyDialog(def, isSet),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: def.color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(def.icon, size: 20, color: def.color),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    def.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    def.description,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            StatusBadge(
                              label: isSet ? 'Active' : 'Not Set',
                              color: isSet ? AppColors.success : AppColors.textTertiary,
                              pulse: isSet,
                            ),
                          ],
                        ),
                      ),
                    ).animate(delay: Duration(milliseconds: 80 * entry.key))
                        .fadeIn(duration: 300.ms)
                        .slideX(begin: 0.03);
                  }),
                ],
              ),
            ),
    );
  }

  void _showKeyDialog(_ApiKeyDef def, bool currentlySet) {
    final controller = TextEditingController();
    bool obscure = true;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(currentlySet ? 'Update ${def.name}' : 'Set ${def.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Paste your API key here...',
                  prefixIcon: Icon(def.icon, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Iconsax.eye : Iconsax.eye_slash,
                      size: 18,
                    ),
                    onPressed: () => setLocalState(() => obscure = !obscure),
                  ),
                ),
              ),
              if (def.kind == _KeyKind.gemini) ...[
                const SizedBox(height: 12),
                const Text(
                  'Get a free key at aistudio.google.com — sign in, click "Get API key", and paste it here.',
                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            ],
          ),
          actions: [
            if (currentlySet)
              TextButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  await _save(def.kind, '');
                  messenger.showSnackBar(
                    SnackBar(content: Text('${def.name} cleared')),
                  );
                },
                child: const Text(
                  'Clear',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final v = controller.text.trim();
                if (v.isEmpty) {
                  Navigator.pop(context);
                  return;
                }
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                await _save(def.kind, v);
                messenger.showSnackBar(
                  SnackBar(content: Text('${def.name} saved')),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
