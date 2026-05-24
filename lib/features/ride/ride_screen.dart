// lib/features/ride/ride_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/gps_service.dart';
import '../../shared/theme/app_theme.dart';
import 'leaflet_map_widget.dart';
import 'ride_provider.dart';

class RideScreen extends ConsumerStatefulWidget {
  const RideScreen({super.key});

  @override
  ConsumerState<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends ConsumerState<RideScreen> {
  final _mapKey = GlobalKey<LeafletMapWidgetState>();
  final _supabase = Supabase.instance.client;

  bool _isSaving = false;

  // ── Route update ─────────────────────────────────────────────────────────────
  // Only push a JS update when a new point arrives (avoid flooding the WebView)
  int _lastPointCount = 0;

  void _maybeUpdateMap(RideState state) {
    if (state.points.length != _lastPointCount) {
      _lastPointCount = state.points.length;
      _mapKey.currentState?.updateRoute(state.points);
    }
  }

  // ── Save ride ────────────────────────────────────────────────────────────────
  Future<void> _showSaveDialog(RideState state) async {
    final nameCtrl = TextEditingController(text: 'My Ride');
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Save Ride',
          style: TextStyle(
              color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${state.distanceKm.toStringAsFixed(2)} km  ·  '
              '${_formatDuration(state.elapsed)}',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Ride name',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Discard',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(90, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _saveRide(nameCtrl.text.trim().isEmpty ? 'My Ride' : nameCtrl.text.trim(), state);
  }

  Future<void> _saveRide(String name, RideState state) async {
    setState(() => _isSaving = true);
    try {
      final userId = _supabase.auth.currentUser!.id;

      // 1. Insert ride row
      final rideRow = await _supabase.from('rides').insert({
        'user_id': userId,
        'name': name,
        'status': 'completed',
        'distance_km': state.distanceKm,
        'avg_speed_kmh': state.avgSpeedKmh,
        'max_speed_kmh': state.maxSpeedKmh,
        'duration': _durationToPostgres(state.elapsed),
        'elevation_gain_m': state.elevationGainM,
        'started_at': DateTime.now()
            .subtract(state.elapsed)
            .toIso8601String(),
        'ended_at': DateTime.now().toIso8601String(),
      }).select().single();

      final rideId = rideRow['id'] as String;

      // 2. Batch-insert GPS points (max 500 at a time)
      if (state.points.isNotEmpty) {
        final rows = state.points
            .map((p) => {
                  'ride_id': rideId,
                  'latitude': p.latitude,
                  'longitude': p.longitude,
                  'altitude_m': p.altitudeM,
                  'speed_kmh': p.speedKmh,
                  'recorded_at': p.recordedAt.toIso8601String(),
                })
            .toList();

        for (var i = 0; i < rows.length; i += 500) {
          final chunk = rows.sublist(
              i, i + 500 > rows.length ? rows.length : i + 500);
          await _supabase.from('ride_points').insert(chunk);
        }
      }

      // 3. Update profile aggregates
      await _supabase.rpc('update_profile_stats', params: {'p_user_id': userId});

      // 4. Reset service + navigate
      ref.read(gpsServiceProvider).reset();
      _mapKey.currentState?.clear();
      _lastPointCount = 0;

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/history');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: ${e.toString()}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _saveRide(name, state),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _durationToPostgres(Duration d) =>
      '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final rideAsync = ref.watch(rideStateProvider);
    final gps = ref.read(gpsServiceProvider);

    return Scaffold(
      body: rideAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (state) {
          // Side-effect: update map
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _maybeUpdateMap(state));

          return Stack(
            children: [
              // ── Full-screen map ────────────────────────────────────────────
              Positioned.fill(
                child: LeafletMapWidget(key: _mapKey),
              ),

              // ── Back button ────────────────────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 16,
                child: _GlassButton(
                  onTap: state.status == RideStatus.idle ||
                          state.status == RideStatus.stopped
                      ? () => Navigator.maybePop(context)
                      : null,
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 22),
                ),
              ),

              // ── Stats overlay ──────────────────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 72,
                right: 16,
                child: _StatsOverlay(state: state, formatDuration: _formatDuration),
              ),

              // ── Control bar ────────────────────────────────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ControlBar(
                  state: state,
                  isSaving: _isSaving,
                  onStart: () => gps.start(),
                  onPause: () => gps.pause(),
                  onResume: () => gps.resume(),
                  onStop: () {
                    gps.stop();
                    // Show dialog after state propagates
                    Future.delayed(const Duration(milliseconds: 200), () {
                      if (mounted) _showSaveDialog(gps.currentState);
                    });
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Stats overlay ────────────────────────────────────────────────────────────
class _StatsOverlay extends StatelessWidget {
  final RideState state;
  final String Function(Duration) formatDuration;

  const _StatsOverlay({required this.state, required this.formatDuration});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.58),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: Colors.white.withOpacity(0.12), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Stat(
              label: 'DIST',
              value: state.distanceKm.toStringAsFixed(2),
              unit: 'km',
            ),
            _Divider(),
            _Stat(
              label: 'TIME',
              value: formatDuration(state.elapsed),
              unit: '',
            ),
            _Divider(),
            _Stat(
              label: 'SPEED',
              value: state.currentSpeedKmh.toStringAsFixed(1),
              unit: 'km/h',
            ),
            _Divider(),
            _Stat(
              label: 'AVG',
              value: state.avgSpeedKmh.toStringAsFixed(1),
              unit: 'km/h',
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 32,
        color: Colors.white.withOpacity(0.2),
      );
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _Stat(
      {required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3)),
        if (unit.isNotEmpty)
          Text(unit,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 9)),
      ],
    );
  }
}

// ── Control bar ──────────────────────────────────────────────────────────────
class _ControlBar extends StatelessWidget {
  final RideState state;
  final bool isSaving;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  const _ControlBar({
    required this.state,
    required this.isSaving,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isIdle = state.status == RideStatus.idle;
    final isActive = state.status == RideStatus.active;
    final isPaused = state.status == RideStatus.paused;
    final isStopped = state.status == RideStatus.stopped;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomInset),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          )
        ],
      ),
      child: isStopped
          ? Center(
              child: isSaving
                  ? const CircularProgressIndicator()
                  : Text('Ride stopped',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 15)),
            )
          : isIdle
              ? // Only START
              _BigButton(
                  color: AppTheme.primary,
                  icon: Icons.play_arrow_rounded,
                  label: 'Start Ride',
                  onTap: onStart,
                )
              : Row(
                  children: [
                    // Pause / Resume
                    Expanded(
                      child: _ActionButton(
                        color: isPaused
                            ? const Color(0xFF059669)
                            : const Color(0xFFF59E0B),
                        icon: isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        label: isPaused ? 'Resume' : 'Pause',
                        onTap: isPaused ? onResume : onPause,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Stop
                    Expanded(
                      child: _ActionButton(
                        color: const Color(0xFFDC2626),
                        icon: Icons.stop_rounded,
                        label: 'Stop',
                        onTap: onStop,
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BigButton(
      {required this.color,
      required this.icon,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 6))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.color,
      required this.icon,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ── Frosted glass button (back arrow) ───────────────────────────────────────
class _GlassButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _GlassButton({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Center(child: child),
      ),
    );
  }
}