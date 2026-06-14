import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/providers/automation_provider.dart';

/// Bottom sheet showing every user-installed app, searchable. Tap to launch.
class AppLauncherSheet extends ConsumerStatefulWidget {
  const AppLauncherSheet({super.key});

  static Future<void> show(BuildContext context, WidgetRef ref) {
    // Kick off the load before the sheet animates in so the list is ready
    // by the time the user looks at it.
    ref.read(automationProvider.notifier).loadApps();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AppLauncherSheet(),
    );
  }

  @override
  ConsumerState<AppLauncherSheet> createState() => _AppLauncherSheetState();
}

class _AppLauncherSheetState extends ConsumerState<AppLauncherSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(automationProvider);
    final filtered = _query.isEmpty
        ? state.installedApps
        : state.installedApps
            .where((a) => a.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Text(
                    'Apps',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  if (state.installedApps.isNotEmpty)
                    Text(
                      '${state.installedApps.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Reload',
                    icon: const Icon(Iconsax.refresh, size: 18),
                    onPressed: () => ref
                        .read(automationProvider.notifier)
                        .loadApps(force: true),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search…',
                  prefixIcon:
                      const Icon(Iconsax.search_normal_1, size: 18),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: state.loadingApps && state.installedApps.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            _query.isEmpty
                                ? 'No installed apps found.'
                                : 'No matches for "$_query"',
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final app = filtered[i];
                            return _AppRow(
                              app: app,
                              onTap: () async {
                                final ok = await ref
                                    .read(automationProvider.notifier)
                                    .launchApp(app.packageName);
                                if (ok && context.mounted) {
                                  Navigator.pop(context);
                                }
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  final InstalledApp app;
  final VoidCallback onTap;
  const _AppRow({required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: app.iconBytes != null
                    ? Image.memory(
                        Uint8List.fromList(app.iconBytes!),
                        fit: BoxFit.cover,
                      )
                    : const Icon(
                        Iconsax.box_1,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      app.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Iconsax.arrow_right_3,
                size: 14,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
