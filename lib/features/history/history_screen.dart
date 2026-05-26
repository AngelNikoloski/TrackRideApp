import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../shared/theme/app_theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _rides = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRides();
  }

  //Data fetching
  Future<void> _loadRides() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final userId = _supabase.auth.currentUser!.id;
      final data = await _supabase
          .from('rides')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _rides = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  //Delete ride
  Future<void> _deleteRide(String rideId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Ride',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'This will permanently delete this ride and all its GPS data. This action cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              minimumSize: const Size(90, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final userId = _supabase.auth.currentUser!.id;
      await _supabase.from('rides').delete().eq('id', rideId);
      await _supabase
          .rpc('update_profile_stats', params: {'p_user_id': userId});

      if (mounted) {
        setState(() => _rides.removeWhere((r) => r['id'] == rideId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ride deleted'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openDetail(Map<String, dynamic> ride) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RideDetailSheet(
        ride: ride,
        onDelete: () {
          Navigator.pop(context);
          _deleteRide(ride['id'] as String);
        },
      ),
    );
  }

  String _formatDuration(String? raw) {
    if (raw == null) return '0m';
    final parts = raw.split(':');
    if (parts.length < 3) return raw;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _formatDate(String? raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(String? raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Ride History',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            tooltip: 'Refresh',
            onPressed: _loadRides,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: Colors.red.shade400),
              const SizedBox(height: 12),
              Text('Failed to load rides',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16)),
              const SizedBox(height: 8),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loadRides,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_rides.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.directions_bike_rounded,
                  size: 40, color: AppTheme.primary.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 16),
            const Text(
              'No rides yet',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18),
            ),
            const SizedBox(height: 6),
            const Text(
              'Complete a ride to see it here',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 180,
              child: ElevatedButton.icon(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/ride'),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Riding'),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRides,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _rides.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final ride = _rides[i];
          return _RideListCard(
            ride: ride,
            formatDuration: _formatDuration,
            formatDate: _formatDate,
            formatTime: _formatTime,
            onTap: () => _openDetail(ride),
            onDelete: () => _deleteRide(ride['id'] as String),
          );
        },
      ),
    );
  }
}

class _RideListCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  final String Function(String?) formatDuration;
  final String Function(String?) formatDate;
  final String Function(String?) formatTime;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RideListCard({
    required this.ride,
    required this.formatDuration,
    required this.formatDate,
    required this.formatTime,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = ride['name'] ?? 'Ride';
    final date = formatDate(ride['started_at'] as String?);
    final time = formatTime(ride['started_at'] as String?);
    final distanceKm = (ride['distance_km'] as num? ?? 0).toDouble();
    final duration = formatDuration(ride['duration'] as String?);
    final avgSpeed = (ride['avg_speed_kmh'] as num? ?? 0).toDouble();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.directions_bike_rounded,
                color: AppTheme.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            // Name + date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$date · $time',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _MiniStat(
                          icon: Icons.route_rounded,
                          text: '${distanceKm.toStringAsFixed(2)} km'),
                      const SizedBox(width: 8),
                      _MiniStat(
                          icon: Icons.timer_outlined, text: duration),
                      const SizedBox(width: 8),
                      _MiniStat(
                          icon: Icons.speed_rounded,
                          text:
                              '${avgSpeed.toStringAsFixed(1)} km/h'),
                    ],
                  ),
                ],
              ),
            ),

            const Icon(Icons.chevron_right_rounded,
                color: AppTheme.textSecondary, size: 22),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniStat({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppTheme.textSecondary),
        const SizedBox(width: 3),
        Text(text,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 11)),
      ],
    );
  }
}

class _RideDetailSheet extends StatefulWidget {
  final Map<String, dynamic> ride;
  final VoidCallback onDelete;

  const _RideDetailSheet({required this.ride, required this.onDelete});

  @override
  State<_RideDetailSheet> createState() => _RideDetailSheetState();
}

class _RideDetailSheetState extends State<_RideDetailSheet> {
  final _supabase = Supabase.instance.client;
  final _mapKey = GlobalKey<_StaticLeafletMapState>();

  
  bool _pointsLoaded = false;

  Future<void> _loadPoints() async {
    if (_pointsLoaded) return;
    _pointsLoaded = true;

    try {
      final data = await _supabase
          .from('ride_points')
          .select('latitude, longitude, altitude_m, speed_kmh, recorded_at')
          .eq('ride_id', widget.ride['id'] as String)
          .order('recorded_at', ascending: true);

      final points = List<Map<String, dynamic>>.from(data);
      if (mounted) {
        _mapKey.currentState?.loadPoints(points);
      }
    } catch (_) {
      // Map stays empty on error
    }
  }

  String _formatDuration(String? raw) {
    if (raw == null) return '—';
    final parts = raw.split(':');
    if (parts.length < 3) return raw;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final s = int.tryParse(parts[2].split('.').first) ?? 0;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _formatDateLong(String? raw) {
    if (raw == null) return '—';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '—';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    final weekday = weekdays[(dt.weekday - 1) % 7];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$weekday, ${dt.day} ${months[dt.month - 1]} ${dt.year} · $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final name = ride['name'] ?? 'Ride';
    final distanceKm = (ride['distance_km'] as num? ?? 0).toDouble();
    final avgSpeedKmh = (ride['avg_speed_kmh'] as num? ?? 0).toDouble();
    final maxSpeedKmh = (ride['max_speed_kmh'] as num? ?? 0).toDouble();
    final elevationGainM = (ride['elevation_gain_m'] as num? ?? 0).toInt();
    final duration = _formatDuration(ride['duration'] as String?);
    final dateStr = _formatDateLong(ride['started_at'] as String?);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
 
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.directions_bike_rounded,
                        color: AppTheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateStr,
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    // Delete button
                    IconButton(
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: const Color(0xFFDC2626),
                      tooltip: 'Delete ride',
                    ),
                  ],
                ),
              ),

              //Scrollable content
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    // Map 
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        height: 240,
                        child: _StaticLeafletMap(
                          key: _mapKey,
                          onMapReady: () {
                            _loadPoints();
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    //Stats grid
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.6,
                      children: [
                        _DetailStatCard(
                          icon: Icons.route_rounded,
                          label: 'Distance',
                          value: '${distanceKm.toStringAsFixed(2)} km',
                          color: const Color(0xFF2563EB),
                        ),
                        _DetailStatCard(
                          icon: Icons.timer_outlined,
                          label: 'Duration',
                          value: duration,
                          color: const Color(0xFF0891B2),
                        ),
                        _DetailStatCard(
                          icon: Icons.speed_rounded,
                          label: 'Avg Speed',
                          value: '${avgSpeedKmh.toStringAsFixed(1)} km/h',
                          color: const Color(0xFF059669),
                        ),
                        _DetailStatCard(
                          icon: Icons.bolt_rounded,
                          label: 'Max Speed',
                          value: '${maxSpeedKmh.toStringAsFixed(1)} km/h',
                          color: const Color(0xFFF59E0B),
                        ),
                        _DetailStatCard(
                          icon: Icons.terrain_rounded,
                          label: 'Elevation Gain',
                          value: '$elevationGainM m',
                          color: const Color(0xFF7C3AED),
                        ),
                        _DetailStatCard(
                          icon: Icons.check_circle_rounded,
                          label: 'Status',
                          value: (ride['status'] as String? ?? 'completed')
                              .capitalize(),
                          color: const Color(0xFF16A34A),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    //Delete button 
                    OutlinedButton.icon(
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Color(0xFFDC2626)),
                      label: const Text(
                        'Delete this ride',
                        style: TextStyle(
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        side: const BorderSide(color: Color(0xFFDC2626)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _StaticLeafletMap extends StatefulWidget {
  final VoidCallback onMapReady;

  const _StaticLeafletMap({super.key, required this.onMapReady});

  @override
  State<_StaticLeafletMap> createState() => _StaticLeafletMapState();
}

class _StaticLeafletMapState extends State<_StaticLeafletMap> {
  late final WebViewController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('FlutterBridge', onMessageReceived: (_) {})
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _ready = true;
            widget.onMapReady();
          },
        ),
      )
      ..loadHtmlString(_mapHtml());
  }

  // Called after map is ready: draws the full polyline and fits bounds.
  void loadPoints(List<Map<String, dynamic>> points) {
    if (!_ready || points.isEmpty) return;

    final latlngs = points
        .map((p) =>
            '[${p['latitude']},${p['longitude']}]')
        .join(',');

    _controller.runJavaScript('''
      var pts = [$latlngs];
      polyline.setLatLngs(pts);

      // Start marker (green)
      var start = pts[0];
      L.circleMarker(start, {
        radius: 8, color: '#16A34A', fillColor: '#16A34A',
        fillOpacity: 1, weight: 3, opacity: 1
      }).addTo(map).bindTooltip('Start', {permanent: false});

      // End marker (red)
      var end = pts[pts.length - 1];
      L.circleMarker(end, {
        radius: 8, color: '#DC2626', fillColor: '#DC2626',
        fillOpacity: 1, weight: 3, opacity: 1
      }).addTo(map).bindTooltip('End', {permanent: false});

      // Fit map to route bounds with padding
      if (pts.length > 1) {
        map.fitBounds(polyline.getBounds(), { padding: [24, 24] });
      } else {
        map.setView(pts[0], 16);
      }
    ''');
  }

  String _mapHtml() => '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body, #map { width: 100%; height: 100%; background: #F1F5F9; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var map = L.map('map', {
      center: [0, 0],
      zoom: 14,
      zoomControl: false,
      attributionControl: false,
      dragging: false,
      touchZoom: false,
      scrollWheelZoom: false,
      doubleClickZoom: false,
      boxZoom: false,
      keyboard: false
    });

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19
    }).addTo(map);

    var polyline = L.polyline([], {
      color: '#2563EB',
      weight: 5,
      opacity: 0.9,
      lineJoin: 'round',
      lineCap: 'round'
    }).addTo(map);
  </script>
</body>
</html>
''';

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

extension StringCapitalize on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}