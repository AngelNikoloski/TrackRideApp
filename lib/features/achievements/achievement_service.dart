import 'package:supabase_flutter/supabase_flutter.dart';

class AchievementDefinition {
  final String type;
  final String title;
  final String description;
  final String emoji;

  const AchievementDefinition({
    required this.type,
    required this.title,
    required this.description,
    required this.emoji,
  });
}

class AchievementService {
  final _supabase = Supabase.instance.client;

  // Master list of every achievement the app knows about
  static const List<AchievementDefinition> all = [
    AchievementDefinition(
      type: 'first_ride',
      title: 'First Ride',
      description: 'Completed your very first ride',
      emoji: '🚴',
    ),
    AchievementDefinition(
      type: 'speed_demon',
      title: 'Speed Demon',
      description: 'Reached a speed of 40 km/h or more',
      emoji: '⚡',
    ),
    AchievementDefinition(
      type: 'century_rider',
      title: 'Century Rider',
      description: 'Cycled 100 km in total',
      emoji: '💯',
    ),
    AchievementDefinition(
      type: 'iron_legs',
      title: 'Iron Legs',
      description: 'Cycled 500 km in total',
      emoji: '🦾',
    ),
    AchievementDefinition(
      type: 'elite_cyclist',
      title: 'Elite Cyclist',
      description: 'Cycled 1000 km in total',
      emoji: '🏆',
    ),
    AchievementDefinition(
      type: 'marathoner',
      title: 'Marathoner',
      description: 'Rode 42 km or more in a single ride',
      emoji: '🏅',
    ),
    AchievementDefinition(
      type: 'early_bird',
      title: 'Early Bird',
      description: 'Started a ride before 7:00 AM',
      emoji: '🌅',
    ),
  ];

  // Call this after every completed ride
  // Returns list of newly unlocked achievement titles (to show in snackbar)
  Future<List<String>> checkAndGrant({
    required String userId,
    required double rideDistanceKm,    // this single ride's distance
    required double maxSpeedKmh,       // this single ride's max speed
    required double totalDistanceKm,   // profile total AFTER update
    required int totalRides,           // profile total AFTER update
    required DateTime startedAt,       // when the ride started
  }) async {
    // 1. Fetch already-earned types so we never duplicate
    final existing = await _supabase
        .from('achievements')
        .select('type')
        .eq('user_id', userId);

    final earned = <String>{
      for (final row in existing) row['type'] as String
    };

    final toGrant = <AchievementDefinition>[];

    // 2. Evaluate each rule
    if (!earned.contains('first_ride') && totalRides >= 1) {
      toGrant.add(_def('first_ride'));
    }

    if (!earned.contains('speed_demon') && maxSpeedKmh >= 40) {
      toGrant.add(_def('speed_demon'));
    }

    if (!earned.contains('century_rider') && totalDistanceKm >= 100) {
      toGrant.add(_def('century_rider'));
    }

    if (!earned.contains('iron_legs') && totalDistanceKm >= 500) {
      toGrant.add(_def('iron_legs'));
    }

    if (!earned.contains('elite_cyclist') && totalDistanceKm >= 1000) {
      toGrant.add(_def('elite_cyclist'));
    }

    if (!earned.contains('marathoner') && rideDistanceKm >= 42) {
      toGrant.add(_def('marathoner'));
    }

    if (!earned.contains('early_bird') && startedAt.hour < 7) {
      toGrant.add(_def('early_bird'));
    }

    if (toGrant.isEmpty) return [];

    // 3. Insert new achievements (ignore conflicts just in case)
    final rows = toGrant.map((d) => {
      'user_id': userId,
      'type': d.type,
      'title': d.title,
      'description': d.description,
      'value': _valueFor(d.type, rideDistanceKm, maxSpeedKmh, totalDistanceKm),
    }).toList();

    await _supabase
        .from('achievements')
        .upsert(rows, onConflict: 'user_id,type');

    return toGrant.map((d) => '${d.emoji} ${d.title}').toList();
  }

  // Fetch all achievements for a user (earned + locked)
  Future<List<Map<String, dynamic>>> fetchForUser(String userId) async {
    final earned = await _supabase
        .from('achievements')
        .select()
        .eq('user_id', userId)
        .order('earned_at', ascending: true);

    final earnedTypes = <String>{
      for (final row in earned) row['type'] as String
    };

    // Merge: earned rows first, then locked placeholders
    final result = <Map<String, dynamic>>[];

    for (final def in all) {
      if (earnedTypes.contains(def.type)) {
        final row = (earned as List).firstWhere((r) => r['type'] == def.type);
        result.add({
          ...Map<String, dynamic>.from(row),
          'emoji': def.emoji,
          'locked': false,
        });
      } else {
        result.add({
          'type': def.type,
          'title': def.title,
          'description': def.description,
          'emoji': def.emoji,
          'locked': true,
        });
      }
    }

    return result;
  }

  AchievementDefinition _def(String type) =>
      all.firstWhere((d) => d.type == type);

  double? _valueFor(String type, double rideDist, double maxSpeed, double totalDist) {
    switch (type) {
      case 'speed_demon': return maxSpeed;
      case 'marathoner':  return rideDist;
      case 'century_rider':
      case 'iron_legs':
      case 'elite_cyclist': return totalDist;
      default: return null;
    }
  }
}