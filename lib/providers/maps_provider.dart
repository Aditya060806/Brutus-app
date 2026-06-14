import 'dart:async';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:brutus_app/data/services/network_guard.dart';
import 'package:brutus_app/data/services/places_service.dart';

export 'package:brutus_app/data/services/places_service.dart'
    show PlaceHit, PlacesException;
export 'package:latlong2/latlong.dart' show LatLng;

class MapsState {
  final LatLng? userLocation;
  final String? userPlace; // reverse-geocoded label of userLocation
  final LatLng center;
  final double zoom;
  final List<PlaceHit> searchResults;
  final PlaceHit? selectedHit;
  final bool isSearching;
  final bool isLocating;
  final String? errorMessage;
  final bool needsLocationPermission;

  const MapsState({
    this.userLocation,
    this.userPlace,
    this.center = const LatLng(20.5937, 78.9629), // India centroid by default
    this.zoom = 4.5,
    this.searchResults = const [],
    this.selectedHit,
    this.isSearching = false,
    this.isLocating = false,
    this.errorMessage,
    this.needsLocationPermission = false,
  });

  MapsState copyWith({
    LatLng? userLocation,
    String? userPlace,
    LatLng? center,
    double? zoom,
    List<PlaceHit>? searchResults,
    PlaceHit? selectedHit,
    bool? isSearching,
    bool? isLocating,
    String? errorMessage,
    bool? needsLocationPermission,
    bool clearSelection = false,
    bool clearError = false,
  }) {
    return MapsState(
      userLocation: userLocation ?? this.userLocation,
      userPlace: userPlace ?? this.userPlace,
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
      searchResults: searchResults ?? this.searchResults,
      selectedHit: clearSelection ? null : (selectedHit ?? this.selectedHit),
      isSearching: isSearching ?? this.isSearching,
      isLocating: isLocating ?? this.isLocating,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      needsLocationPermission:
          needsLocationPermission ?? this.needsLocationPermission,
    );
  }
}

class MapsNotifier extends StateNotifier<MapsState> {
  MapsNotifier({PlacesService? service})
      : _places = service ?? PlacesService(),
        super(const MapsState());

  final PlacesService _places;
  CancelToken? _searchToken;

  void _log(String msg) => dev.log('[Maps] $msg', name: 'BrutusAI');

  // ── User location ───────────────────────────────────────────────────────

  Future<void> locateUser({bool moveCamera = true}) async {
    state = state.copyWith(
      isLocating: true,
      clearError: true,
      needsLocationPermission: false,
    );

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      state = state.copyWith(
        isLocating: false,
        errorMessage:
            'Location services are off. Enable them in system settings.',
      );
      return;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      state = state.copyWith(
        isLocating: false,
        needsLocationPermission: true,
        errorMessage:
            'Location permission was permanently denied. Open Settings to allow.',
      );
      return;
    }
    if (perm == LocationPermission.denied) {
      state = state.copyWith(
        isLocating: false,
        errorMessage: 'Location permission denied.',
      );
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final point = LatLng(pos.latitude, pos.longitude);
      state = state.copyWith(
        userLocation: point,
        isLocating: false,
        center: moveCamera ? point : state.center,
        zoom: moveCamera ? 13 : state.zoom,
      );
      // Best-effort reverse-geocode for the "you're at..." pill.
      final place = await _places.reverse(point.latitude, point.longitude);
      if (place != null) {
        state = state.copyWith(userPlace: place);
      }
    } catch (e) {
      _log('locate failed: $e');
      state = state.copyWith(
        isLocating: false,
        errorMessage: 'Could not get your location: $e',
      );
    }
  }

  Future<void> openLocationSettings() => Geolocator.openAppSettings();

  // ── Search ──────────────────────────────────────────────────────────────

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    _searchToken?.cancel('user-cancel');
    final token = CancelToken();
    _searchToken = token;

    state = state.copyWith(isSearching: true, clearError: true);
    try {
      final hits = await _places.search(trimmed, cancelToken: token);
      if (token.isCancelled) return;
      state = state.copyWith(
        searchResults: hits,
        isSearching: false,
      );
    } on OfflineException catch (e) {
      state = state.copyWith(
        isSearching: false,
        errorMessage: e.toString(),
      );
    } on PlacesException catch (e) {
      state = state.copyWith(
        isSearching: false,
        errorMessage: e.toString(),
      );
    } catch (e) {
      state = state.copyWith(
        isSearching: false,
        errorMessage: 'Search failed: $e',
      );
    }
  }

  void selectHit(PlaceHit hit) {
    state = state.copyWith(
      selectedHit: hit,
      center: LatLng(hit.latitude, hit.longitude),
      zoom: 14,
    );
  }

  void clearSelection() {
    state = state.copyWith(clearSelection: true, searchResults: const []);
  }

  void setCamera(LatLng center, double zoom) {
    state = state.copyWith(center: center, zoom: zoom);
  }

  // ── Voice tool ──────────────────────────────────────────────────────────

  /// Voice tool: "find me a place / location of X".
  Future<Map<String, dynamic>> runForTool(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      return {'error': 'find_place needs a non-empty `query`.'};
    }
    try {
      final hits = await _places.search(clean, maxResults: 3);
      if (hits.isEmpty) {
        return {
          'count': 0,
          'message': 'No places matched "$clean".',
        };
      }
      // Move the map to the top hit so opening Maps after the voice call
      // shows what the user was just asking about.
      selectHit(hits.first);
      state = state.copyWith(searchResults: hits);
      return {
        'count': hits.length,
        'top': {
          'name': hits.first.displayName,
          'lat': hits.first.latitude,
          'lng': hits.first.longitude,
        },
        'all': hits
            .map((h) => {
                  'name': h.displayName,
                  'lat': h.latitude,
                  'lng': h.longitude,
                })
            .toList(),
        'message':
            'Open Tools → Maps to see ${hits.first.displayName} pinned.',
      };
    } catch (e) {
      return {'error': 'Place lookup failed: $e'};
    }
  }

  @override
  void dispose() {
    _searchToken?.cancel('dispose');
    super.dispose();
  }
}

final mapsProvider = StateNotifierProvider<MapsNotifier, MapsState>(
  (ref) {
    final n = MapsNotifier();
    ref.onDispose(n.dispose);
    return n;
  },
);
