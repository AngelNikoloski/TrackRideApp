import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/gps_service.dart';

final gpsServiceProvider = Provider<GpsService>((ref) {
  final service = GpsService();
  ref.onDispose(service.dispose);
  return service;
});

final rideStateProvider = StreamProvider<RideState>((ref) {
  final service = ref.watch(gpsServiceProvider);

  // Create a controller so we can seed an immediate value
  final controller = StreamController<RideState>();

  // Emit current state right away so the screen never shows blank
  controller.add(service.currentState);

  // Forward all future ticks
  final sub = service.stream.listen(
    controller.add,
    onError: controller.addError,
    onDone: controller.close,
  );

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});