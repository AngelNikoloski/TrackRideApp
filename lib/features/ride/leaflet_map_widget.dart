import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/gps_service.dart';

/// Full-screen Leaflet map.
/// Call [addPoint] to append a GPS breadcrumb and [updatePolyline] to redraw.
class LeafletMapWidget extends StatefulWidget {
  const LeafletMapWidget({super.key});

  @override
  State<LeafletMapWidget> createState() => LeafletMapWidgetState();
}

class LeafletMapWidgetState extends State<LeafletMapWidget> {
  late final WebViewController _controller;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (_) {},
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => setState(() => _mapReady = true),
        ),
      )
      ..loadHtmlString(_mapHtml());
  }

  //Public API
  //Update the full route polyline + move the marker to the latest point.
  void updateRoute(List<RidePoint> points) {
    if (!_mapReady || points.isEmpty) return;
    final latlngs = points
        .map((p) => '[${p.latitude},${p.longitude}]')
        .join(',');
    final last = points.last;
    _run('''
      polyline.setLatLngs([$latlngs]);
      marker.setLatLng([${last.latitude},${last.longitude}]);
      map.panTo([${last.latitude},${last.longitude}]);
    ''');
  }

  /// Pan the map to a position without changing zoom.
  void panTo(double lat, double lng) {
    if (!_mapReady) return;
    _run('map.panTo([$lat,$lng]);');
  }

  /// Reset everything for a new ride.
  void clear() {
    if (!_mapReady) return;
    _run('polyline.setLatLngs([]); marker.setLatLng([0,0]);');
  }

  void _run(String js) => _controller.runJavaScript(js);

  //HTML
  String _mapHtml() => '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body, #map { width: 100%; height: 100%; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var map = L.map('map', {
      center: [0, 0],
      zoom: 16,
      zoomControl: false,
      attributionControl: false
    });

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19
    }).addTo(map);

    // Route polyline
    var polyline = L.polyline([], {
      color: '#2563EB',
      weight: 5,
      opacity: 0.85,
      lineJoin: 'round'
    }).addTo(map);

    // Rider marker (pulsing dot)
    var markerHtml = '<div style="' +
      'width:18px;height:18px;border-radius:50%;' +
      'background:#2563EB;border:3px solid white;' +
      'box-shadow:0 0 0 4px rgba(37,99,235,0.3);' +
      'animation:pulse 1.5s infinite;"></div>';

    var style = document.createElement('style');
    style.innerHTML = '@keyframes pulse{0%,100%{box-shadow:0 0 0 4px rgba(37,99,235,0.3);}50%{box-shadow:0 0 0 8px rgba(37,99,235,0.1);}}';
    document.head.appendChild(style);

    var markerIcon = L.divIcon({ html: markerHtml, className: '', iconAnchor: [9,9] });
    var marker = L.marker([0,0], { icon: markerIcon }).addTo(map);

    // Try to get initial location
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(function(pos) {
        map.setView([pos.coords.latitude, pos.coords.longitude], 16);
        marker.setLatLng([pos.coords.latitude, pos.coords.longitude]);
      });
    }
  </script>
</body>
</html>
''';

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}