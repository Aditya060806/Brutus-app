import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/providers/maps_provider.dart';

/// Brutus Mobile — Maps screen.
///
/// Free OpenStreetMap tiles + Nominatim search. No Google Maps key needed.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _searchCtrl = TextEditingController();
  final _mapController = MapController();

  bool _watching = false;

  @override
  void initState() {
    super.initState();
    // Try to centre on the user as the screen opens. Permission errors flow
    // into the provider's state.errorMessage and become a visible card.
    Future.microtask(() => ref.read(mapsProvider.notifier).locateUser());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mapsProvider);

    // Listen for state-driven camera changes (e.g. user taps a search hit
    // or voice tool moved the camera).
    ref.listen<MapsState>(mapsProvider, (prev, next) {
      if (prev?.center != next.center || prev?.zoom != next.zoom) {
        _mapController.move(next.center, next.zoom);
      }
    });

    if (!_watching) {
      _watching = true;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Maps'),
        actions: [
          IconButton(
            tooltip: 'My location',
            icon: state.isLocating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Iconsax.gps),
            onPressed: state.isLocating
                ? null
                : () => ref.read(mapsProvider.notifier).locateUser(),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: state.center,
              initialZoom: state.zoom,
              minZoom: 2,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.adityapandey.brutus_app',
                tileProvider: NetworkTileProvider(),
              ),
              MarkerLayer(
                markers: [
                  if (state.userLocation != null)
                    Marker(
                      point: state.userLocation!,
                      width: 30,
                      height: 30,
                      child: _UserDot(),
                    ),
                  if (state.selectedHit != null)
                    Marker(
                      point: LatLng(
                        state.selectedHit!.latitude,
                        state.selectedHit!.longitude,
                      ),
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: _Pin(),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

          // ── Search bar ──
          Positioned(
            left: 16,
            right: 16,
            top: 12,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppColors.elevatedShadow,
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(
                      Iconsax.search_normal_1,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: 'Search places…',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 14),
                          isDense: true,
                        ),
                        onSubmitted: (v) =>
                            ref.read(mapsProvider.notifier).search(v),
                      ),
                    ),
                    if (state.isSearching)
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_searchCtrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Iconsax.close_circle, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(mapsProvider.notifier).clearSelection();
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Search results ──
          if (state.searchResults.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              top: 88,
              child: SafeArea(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppColors.elevatedShadow,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: state.searchResults.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 50),
                    itemBuilder: (context, i) {
                      final hit = state.searchResults[i];
                      return ListTile(
                        leading: const Icon(
                          Iconsax.location,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        title: Text(
                          hit.displayName.split(',').first,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          hit.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () {
                          ref.read(mapsProvider.notifier).selectHit(hit);
                          _searchCtrl.text = hit.displayName.split(',').first;
                          // Hide the dropdown by clearing the result list,
                          // but keep the selected pin via re-selectHit.
                          ref.read(mapsProvider.notifier).clearSelection();
                          ref.read(mapsProvider.notifier).selectHit(hit);
                          FocusScope.of(context).unfocus();
                        },
                      );
                    },
                  ),
                ),
              ),
            ),

          // ── Selected place card ──
          if (state.selectedHit != null && state.searchResults.isEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                child: _SelectedCard(
                  hit: state.selectedHit!,
                  onDirections: () => _openExternalDirections(state.selectedHit!),
                  onClose: () =>
                      ref.read(mapsProvider.notifier).clearSelection(),
                ).animate().slideY(begin: 0.2, duration: 220.ms).fadeIn(),
              ),
            ),

          // ── Error / hint banner ──
          if (state.errorMessage != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: state.selectedHit != null ? 130 : 16,
              child: SafeArea(
                child: _ErrorBanner(
                  message: state.errorMessage!,
                  needsSettings: state.needsLocationPermission,
                  onSettings: () => ref
                      .read(mapsProvider.notifier)
                      .openLocationSettings(),
                ),
              ),
            ),

          // ── User location banner pill ──
          if (state.userPlace != null && state.selectedHit == null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                child: _UserPill(label: state.userPlace!),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openExternalDirections(PlaceHit hit) async {
    // Universal geo: URI works on Android + iOS; falls back to Google Maps web.
    final geo = Uri.parse(
      'geo:${hit.latitude},${hit.longitude}?q=${Uri.encodeComponent(hit.displayName)}',
    );
    final web = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${hit.latitude},${hit.longitude}',
    );
    if (await canLaunchUrl(geo)) {
      await launchUrl(geo);
    } else {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }
}

class _UserDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 12,
            spreadRadius: 4,
          ),
        ],
        border: Border.all(color: Colors.white, width: 2.4),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            shape: BoxShape.circle,
            boxShadow: AppColors.primaryGlow,
          ),
          child: const Icon(Iconsax.location, color: Colors.white, size: 16),
        ),
        Container(
          width: 2,
          height: 8,
          color: AppColors.primary,
        ),
      ],
    );
  }
}

class _SelectedCard extends StatelessWidget {
  final PlaceHit hit;
  final VoidCallback onDirections;
  final VoidCallback onClose;
  const _SelectedCard({
    required this.hit,
    required this.onDirections,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.elevatedShadow,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Iconsax.location,
                  color: AppColors.primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.displayName.split(',').first,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      hit.displayName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Iconsax.close_circle, size: 18),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${hit.latitude.toStringAsFixed(4)}, ${hit.longitude.toStringAsFixed(4)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: onDirections,
                icon: const Icon(Iconsax.routing, size: 14),
                label: const Text('Directions'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final bool needsSettings;
  final VoidCallback onSettings;
  const _ErrorBanner({
    required this.message,
    required this.needsSettings,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Iconsax.warning_2, size: 14, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (needsSettings)
            TextButton(
              onPressed: onSettings,
              child: const Text('Settings'),
            ),
        ],
      ),
    );
  }
}

class _UserPill extends StatelessWidget {
  final String label;
  const _UserPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Iconsax.gps, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
