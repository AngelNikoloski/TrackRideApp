import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';

class RidePoint {
  final double latitude;
  final double longitude;
  final double? altitudeM;
  final double speedKmh;
  final DateTime recordedAt;

  const RidePoint({
    required this.latitude,
    required this.longitude,
    this.altitudeM,
    required this.speedKmh,
    required this.recordedAt,
  });
}

class RideState {
  final RideStatus status;
  final double distanceKm;
  final Duration elapsed;
  final double currentSpeedKmh;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final int elevationGainM;
  final List<RidePoint> points;

  const RideState({
    required this.status,
    required this.distanceKm,
    required this.elapsed,
    required this.currentSpeedKmh,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.elevationGainM,
    required this.points,
  });

  static RideState get initial => const RideState(
        status: RideStatus.idle,
        distanceKm: 0,
        elapsed: Duration.zero,
        currentSpeedKmh: 0,
        avgSpeedKmh: 0,
        maxSpeedKmh: 0,
        elevationGainM: 0,
        points: [],
      );

  RideState copyWith({
    RideStatus? status,
    double? distanceKm,
    Duration? elapsed,
    double? currentSpeedKmh,
    double? avgSpeedKmh,
    double? maxSpeedKmh,
    int? elevationGainM,
    List<RidePoint>? points,
  }) =>
      RideState(
        status: status ?? this.status,
        distanceKm: distanceKm ?? this.distanceKm,
        elapsed: elapsed ?? this.elapsed,
        currentSpeedKmh: currentSpeedKmh ?? this.currentSpeedKmh,
        avgSpeedKmh: avgSpeedKmh ?? this.avgSpeedKmh,
        maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
        elevationGainM: elevationGainM ?? this.elevationGainM,
        points: points ?? this.points,
      );
}

enum RideStatus { idle, active, paused, stopped }

class GpsService {
  final _controller = StreamController<RideState>.broadcast();
  Stream<RideState> get stream => _controller.stream;

  RideState _state = RideState.initial;
  RideState get currentState => _state;

  StreamSubscription<Position>? _positionSub;
  Timer? _ticker;
  DateTime? _startTime;
  Duration _accumulatedDuration = Duration.zero;
  double? _lastAltitude;

  Future<bool> requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<void> start() async {
    final granted = await requestPermissions();
    if (!granted) return;

    _accumulatedDuration = Duration.zero;
    _startTime = DateTime.now();
    _lastAltitude = null;
    _state = RideState.initial.copyWith(status: RideStatus.active);
    _emit(_state);

    _startPositionStream();
    _startTicker();
  }

  void pause() {
    if (_state.status != RideStatus.active) return;
    _accumulatedDuration += DateTime.now().difference(_startTime!);
    _positionSub?.cancel();
    _ticker?.cancel();
    _state = _state.copyWith(status: RideStatus.paused, currentSpeedKmh: 0);
    _emit(_state);
  }

  void resume() {
    if (_state.status != RideStatus.paused) return;
    _startTime = DateTime.now();
    _state = _state.copyWith(status: RideStatus.active);
    _emit(_state);
    _startPositionStream();
    _startTicker();
  }

  void stop() {
    if (_state.status == RideStatus.active) {
      _accumulatedDuration += DateTime.now().difference(_startTime!);
    }
    _positionSub?.cancel();
    _ticker?.cancel();
    _state = _state.copyWith(
      status: RideStatus.stopped,
      elapsed: _accumulatedDuration,
      currentSpeedKmh: 0,
    );
    _emit(_state);
  }

  void reset() {
    _accumulatedDuration = Duration.zero;
    _startTime = null;
    _lastAltitude = null;
    _state = RideState.initial;
    _emit(_state);
  }

  void _startPositionStream() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(_onPosition);
  }

  void _onPosition(Position pos) {
    final speedKmh = (pos.speed * 3.6).clamp(0.0, 200.0);
    final newPoint = RidePoint(
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitudeM: pos.altitude,
      speedKmh: speedKmh,
      recordedAt: DateTime.now(),
    );

    final updatedPoints = List<RidePoint>.from(_state.points)..add(newPoint);

    double newDistanceKm = _state.distanceKm;
    if (updatedPoints.length >= 2) {
      final prev = updatedPoints[updatedPoints.length - 2];
      newDistanceKm += _haversineKm(
        prev.latitude, prev.longitude,
        pos.latitude, pos.longitude,
      );
    }

    int elevGain = _state.elevationGainM;
    if (_lastAltitude != null && pos.altitude - _lastAltitude! > 2.0) {
      elevGain += (pos.altitude - _lastAltitude!).round();
    }
    _lastAltitude = pos.altitude;

    final maxSpeed = speedKmh > _state.maxSpeedKmh ? speedKmh : _state.maxSpeedKmh;

    final elapsedHours =
        (_accumulatedDuration + DateTime.now().difference(_startTime!)).inSeconds /
            3600.0;
    final avgSpeed = elapsedHours > 0 ? newDistanceKm / elapsedHours : speedKmh;

    _state = _state.copyWith(
      distanceKm: newDistanceKm,
      currentSpeedKmh: speedKmh,
      avgSpeedKmh: avgSpeed,
      maxSpeedKmh: maxSpeed,
      elevationGainM: elevGain,
      points: updatedPoints,
    );
    _emit(_state);
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state.status != RideStatus.active) return;
      final elapsed =
          _accumulatedDuration + DateTime.now().difference(_startTime!);
      _state = _state.copyWith(elapsed: elapsed);
      _emit(_state);
    });
  }

  void _emit(RideState s) {
    if (!_controller.isClosed) _controller.add(s);
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _deg2rad(double d) => d * pi / 180;

  void dispose() {
    _positionSub?.cancel();
    _ticker?.cancel();
    _controller.close();
  }
}