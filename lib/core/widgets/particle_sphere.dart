import 'dart:math';
import 'package:flutter/material.dart';

/// Audio-reactive 3D particle sphere — Flutter port of the desktop reference's
/// `Sphere.tsx` (Three.js / react-three-fiber).
///
/// Key parity with the Three.js original:
///   • Marsaglia uniform sphere distribution (3000 points)
///   • Slow Y + Z rotation
///   • Additive blending — overlapping particles brighten the core
///   • Crisp small points (no blur) — the "premium" look comes from density
///   • Particles expand outward with audio level, color lerps red → white
class ParticleSphere extends StatefulWidget {
  final double audioLevel; // 0..1
  final bool isActive;
  final double size;
  final int particleCount;
  /// When true, the sphere pulses on its own (used when we don't have a real
  /// output level signal). The driving level is now Brutus's voice, so this
  /// is only a fallback.
  final bool selfPulse;

  const ParticleSphere({
    super.key,
    required this.audioLevel,
    required this.isActive,
    this.size = 240,
    this.particleCount = 3000,
    this.selfPulse = false,
  });

  @override
  State<ParticleSphere> createState() => _ParticleSphereState();
}

class _ParticleSphereState extends State<ParticleSphere>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  late final List<_Particle> _particles;
  // Smoothed audio level — avoids jitter from raw RMS chunks.
  double _smoothedLevel = 0.0;

  @override
  void initState() {
    super.initState();
    final rng = Random(42);
    _particles = List.generate(widget.particleCount, (_) {
      // Uniform random point on a unit sphere (Marsaglia method)
      double x, y, z, s;
      do {
        x = rng.nextDouble() * 2 - 1;
        y = rng.nextDouble() * 2 - 1;
        z = rng.nextDouble() * 2 - 1;
        s = x * x + y * y + z * z;
      } while (s > 1.0 || s == 0.0);
      final norm = 1.0 / sqrt(s);
      return _Particle(
        x: x * norm,
        y: y * norm,
        z: z * norm,
        spread: rng.nextDouble(),
      );
    });

    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        // Synthetic pulse only when explicitly requested (no playback signal)
        double target = widget.audioLevel;
        if (widget.selfPulse) {
          final pulse = (sin(_ticker.value * 2 * pi * 3) + 1) / 2 * 0.35;
          target = max(target, pulse);
        }
        // Exponential smoothing — sphere glides between volumes instead of
        // snapping. Gives the "breathing" feel of the desktop reference.
        _smoothedLevel = _smoothedLevel * 0.78 + target * 0.22;

        return CustomPaint(
          size: Size.square(widget.size),
          painter: _SpherePainter(
            particles: _particles,
            phase: _ticker.value,
            audioLevel: _smoothedLevel,
            isActive: widget.isActive,
          ),
        );
      },
    );
  }
}

class _Particle {
  final double x, y, z;
  final double spread; // 0..1 multiplier for outward expansion
  const _Particle({
    required this.x,
    required this.y,
    required this.z,
    required this.spread,
  });
}

class _SpherePainter extends CustomPainter {
  final List<_Particle> particles;
  final double phase; // 0..1 looping
  final double audioLevel; // 0..1
  final bool isActive;

  _SpherePainter({
    required this.particles,
    required this.phase,
    required this.audioLevel,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width / 2 * 0.78;

    // Match the desktop's slow rotation — Y and Z axes
    final ay = phase * 2 * pi; // Y rotation
    final az = phase * 2 * pi * 0.6; // Z rotation
    final cosY = cos(ay), sinY = sin(ay);
    final cosZ = cos(az), sinZ = sin(az);

    final t = audioLevel.clamp(0.0, 1.0);

    final Color baseColor;
    if (!isActive) {
      // Darker slate so the idle sphere reads clearly on a light background.
      baseColor = const Color(0xFF475569); // slate-600
    } else {
      // red-600 → white as level rises (deeper red than red-500 = more bite)
      baseColor = Color.lerp(
        const Color(0xFFDC2626),
        Colors.white,
        t,
      )!;
    }

    // Build per-pass batches with three subtly different sizes for visual
    // density (large soft + medium + bright core dot — additive overdraw makes
    // the centre glow). Avoids any blur filter; crispness from raw geometry.
    final positions = <Offset>[];
    final depths = <double>[];

    for (final p in particles) {
      final expansion = isActive ? (1.0 + audioLevel * p.spread * 0.55) : 1.0;

      // Rotate around Y
      final x1 = p.x * cosY + p.z * sinY;
      final z1 = -p.x * sinY + p.z * cosY;
      final y1 = p.y;

      // Rotate around Z
      final x2 = x1 * cosZ - y1 * sinZ;
      final y2 = x1 * sinZ + y1 * cosZ;
      final z2 = z1;

      positions.add(Offset(
        cx + x2 * radius * expansion,
        cy + y2 * radius * expansion,
      ));
      depths.add(z2);
    }

    // Pass 1 — soft halo (additive). Cheap, makes the sphere feel volumetric.
    if (isActive) {
      final haloPaint = Paint()
        ..blendMode = BlendMode.plus
        ..style = PaintingStyle.fill
        ..color = baseColor.withValues(alpha: 0.18);
      for (int i = 0; i < positions.length; i++) {
        final depth = 0.4 + (depths[i] + 1.0) * 0.3;
        final r = (1.6 + audioLevel * 1.4) * depth;
        canvas.drawCircle(positions[i], r, haloPaint);
      }
    }

    // Pass 2 — crisp core dots. These are what give the "HD" look.
    final corePaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < positions.length; i++) {
      final depth = 0.35 + (depths[i] + 1.0) * 0.325; // 0.35..1.0
      final pointSize = (isActive ? 0.95 : 0.85) * depth + audioLevel * 0.4;
      final alpha = (depth * (isActive ? 0.95 : 0.7)).clamp(0.0, 1.0);
      corePaint.color = baseColor.withValues(alpha: alpha);
      canvas.drawCircle(positions[i], pointSize, corePaint);
    }

    // Pass 3 — bright highlights only on the front-facing particles when
    // the sphere is active. Adds the "studio specular" touch.
    if (isActive && audioLevel > 0.05) {
      final highlightPaint = Paint()
        ..blendMode = BlendMode.plus
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.25 * audioLevel);
      for (int i = 0; i < positions.length; i++) {
        if (depths[i] > 0.4) {
          canvas.drawCircle(positions[i], 0.7, highlightPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpherePainter old) =>
      old.phase != phase ||
      old.audioLevel != audioLevel ||
      old.isActive != isActive;
}
