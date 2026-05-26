import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/theme/app_theme.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _goal;
  List<Map<String, dynamic>> _monthRides = [];
  bool _isLoading = true;
  bool _isSaving = false;

  // Calendar
  final DateTime _now = DateTime.now();
  late DateTime _monthStart;
  late DateTime _monthEnd;

  // Streak
  int _currentStreak = 0;
  int _bestStreak = 0;

  @override
  void initState() {
    super.initState();
    _monthStart = DateTime(_now.year, _now.month, 1);
    _monthEnd = DateTime(_now.year, _now.month + 1, 0);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser!.id;

      // Load or create weekly goal
      final goalsRes = await _supabase
          .from('goals')
          .select()
          .eq('user_id', userId)
          .eq('period', 'weekly')
          .order('created_at', ascending: false)
          .limit(1);

      Map<String, dynamic>? goal;
      if (goalsRes.isEmpty) {
        // Create default 100km weekly goal
        final created = await _supabase.from('goals').insert({
          'user_id': userId,
          'period': 'weekly',
          'target_distance_km': 100.0,
          'current_distance_km': 0.0,
        }).select().single();
        goal = created;
      } else {
        goal = goalsRes.first;
      }

      // Load this month's completed rides
      final ridesRes = await _supabase
          .from('rides')
          .select('started_at, distance_km')
          .eq('user_id', userId)
          .eq('status', 'completed')
          .gte('started_at', _monthStart.toIso8601String())
          .lte('started_at', _monthEnd
              .add(const Duration(hours: 23, minutes: 59))
              .toIso8601String())
          .order('started_at', ascending: true);

      final rides = List<Map<String, dynamic>>.from(ridesRes);

      // Update goal current distance (this week)
      final weekStart = _now.subtract(Duration(days: _now.weekday - 1));
      final weekStartDate =
          DateTime(weekStart.year, weekStart.month, weekStart.day);
      double weeklyKm = 0;
      for (final r in rides) {
        final dt = DateTime.tryParse(r['started_at'] as String? ?? '');
        if (dt != null && dt.isAfter(weekStartDate)) {
          weeklyKm += (r['distance_km'] as num? ?? 0).toDouble();
        }
      }

      // Sync current_distance_km
      await _supabase.from('goals').update({
        'current_distance_km': weeklyKm,
        'completed': weeklyKm >= (goal['target_distance_km'] as num).toDouble(),
      }).eq('id', goal['id'] as String);

      goal['current_distance_km'] = weeklyKm;
      goal['completed'] =
          weeklyKm >= (goal['target_distance_km'] as num).toDouble();

      // Compute streaks
      final rideDays = _rideDaysSet(rides);
      _currentStreak = _computeCurrentStreak(rideDays);
      _bestStreak = _computeBestStreak(rideDays);

      if (mounted) {
        setState(() {
          _goal = goal;
          _monthRides = rides;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editTarget() async {
    final controller = TextEditingController(
      text: (_goal?['target_distance_km'] as num? ?? 100).toStringAsFixed(0),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Weekly Target',
            style: TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Distance (km)',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            suffixText: 'km',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val > 0) Navigator.pop(ctx, val);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;
    setState(() => _isSaving = true);
    try {
      await _supabase.from('goals').update({
        'target_distance_km': result,
        'completed': (_goal?['current_distance_km'] as num? ?? 0) >= result,
      }).eq('id', _goal!['id'] as String);
      setState(() {
        _goal!['target_distance_km'] = result;
        _isSaving = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Set<String> _rideDaysSet(List<Map<String, dynamic>> rides) {
    final days = <String>{};
    for (final r in rides) {
      final dt = DateTime.tryParse(r['started_at'] as String? ?? '')?.toLocal();
      if (dt != null) {
        days.add('${dt.year}-${dt.month}-${dt.day}');
      }
    }
    return days;
  }

  int _computeCurrentStreak(Set<String> rideDays) {
    int streak = 0;
    var day = DateTime(_now.year, _now.month, _now.day);
    while (true) {
      final key = '${day.year}-${day.month}-${day.day}';
      if (rideDays.contains(key)) {
        streak++;
        day = day.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  int _computeBestStreak(Set<String> rideDays) {
    if (rideDays.isEmpty) return 0;
    // Check entire year
    int best = 0;
    int current = 0;
    final yearStart = DateTime(_now.year, 1, 1);
    var day = yearStart;
    while (!day.isAfter(_now)) {
      final key = '${day.year}-${day.month}-${day.day}';
      if (rideDays.contains(key)) {
        current++;
        if (current > best) best = current;
      } else {
        current = 0;
      }
      day = day.add(const Duration(days: 1));
    }
    return best;
  }

  bool _didRide(int day) {
    final target = DateTime(_now.year, _now.month, day);
    for (final r in _monthRides) {
      final dt = DateTime.tryParse(r['started_at'] as String? ?? '')?.toLocal();
      if (dt != null &&
          dt.year == target.year &&
          dt.month == target.month &&
          dt.day == target.day) {
        return true;
      }
    }
    return false;
  }

  bool _isFuture(int day) {
    final target = DateTime(_now.year, _now.month, day);
    return target.isAfter(DateTime(_now.year, _now.month, _now.day));
  }

  bool _isToday(int day) => day == _now.day;

  String _monthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return names[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Goals',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: AppTheme.textSecondary),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    
                    _WeeklyGoalCard(
                      goal: _goal,
                      onEdit: _editTarget,
                      isSaving: _isSaving,
                    ),

                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: _StreakCard(
                            icon: '🔥',
                            label: 'Current Streak',
                            value: '$_currentStreak days',
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StreakCard(
                            icon: '🏆',
                            label: 'Best Streak',
                            value: '$_bestStreak days',
                            color: const Color(0xFF7C3AED),
                          ),
                        ),
                      ],
                    ),

                    // Streak message
                    if (_currentStreak > 0) ...[
                      const SizedBox(height: 12),
                      _StreakMessage(streak: _currentStreak),
                    ],

                    const SizedBox(height: 20),

                    //Calendar
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_monthName(_now.month)} ${_now.year}',
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              // Legend
                              Row(
                                children: [
                                  _LegendDot(
                                      color: const Color(0xFF16A34A),
                                      label: 'Rode'),
                                  const SizedBox(width: 10),
                                  _LegendDot(
                                      color: const Color(0xFFDC2626),
                                      label: 'Missed'),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Weekday headers
                          Row(
                            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                                .map((d) => Expanded(
                                      child: Center(
                                        child: Text(
                                          d,
                                          style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 8),

                          // Calendar grid
                          _buildCalendarGrid(),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    _MonthSummary(rides: _monthRides, now: _now),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCalendarGrid() {
    final daysInMonth = _monthEnd.day;
    // weekday: 1=Mon, 7=Sun
    final firstWeekday = _monthStart.weekday; // 1-7
    final leadingBlanks = firstWeekday - 1;
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: List.generate(rows, (row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: List.generate(7, (col) {
              final cellIndex = row * 7 + col;
              final day = cellIndex - leadingBlanks + 1;

              if (day < 1 || day > daysInMonth) {
                return const Expanded(child: SizedBox());
              }

              final isToday = _isToday(day);
              final isFuture = _isFuture(day);
              final rode = !isFuture && _didRide(day);
              final missed = !isFuture && !isToday && !rode;

              return Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isToday
                          ? AppTheme.primary.withValues(alpha: 0.12)
                          : rode
                              ? const Color(0xFF16A34A).withValues(alpha: 0.12)
                              : missed
                                  ? const Color(0xFFDC2626).withValues(alpha: 0.08)
                                  : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isToday
                          ? Border.all(
                              color: AppTheme.primary, width: 1.5)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            color: isToday
                                ? AppTheme.primary
                                : isFuture
                                    ? AppTheme.textSecondary
                                        .withValues(alpha: 0.4)
                                    : AppTheme.textPrimary,
                            fontSize: 11,
                            fontWeight: isToday
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        if (!isFuture) ...[
                          const SizedBox(height: 1),
                          Icon(
                            rode
                                ? Icons.check_rounded
                                : isToday
                                    ? Icons.circle_outlined
                                    : Icons.close_rounded,
                            size: 10,
                            color: rode
                                ? const Color(0xFF16A34A)
                                : isToday
                                    ? AppTheme.primary
                                    : const Color(0xFFDC2626),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

class _WeeklyGoalCard extends StatelessWidget {
  final Map<String, dynamic>? goal;
  final VoidCallback onEdit;
  final bool isSaving;

  const _WeeklyGoalCard({
    required this.goal,
    required this.onEdit,
    required this.isSaving,
  });

  @override
  Widget build(BuildContext context) {
    final target =
        (goal?['target_distance_km'] as num? ?? 100).toDouble();
    final current =
        (goal?['current_distance_km'] as num? ?? 0).toDouble();
    final progress = (current / target).clamp(0.0, 1.0);
    final percent = (progress * 100).toStringAsFixed(0);
    final completed = goal?['completed'] == true;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: completed
            ? const Color(0xFF16A34A)
            : AppTheme.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (completed
                    ? const Color(0xFF16A34A)
                    : AppTheme.primary)
                .withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    completed ? '🎉 Goal Completed!' : 'Weekly Goal',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${current.toStringAsFixed(2)} / ${target.toStringAsFixed(0)} km',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: onEdit,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Row(
                          children: [
                            Icon(Icons.edit_rounded,
                                color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('Target',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),

          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$percent% complete',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${(target - current).clamp(0, target).toStringAsFixed(1)} km to go',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color color;

  const _StreakCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StreakMessage extends StatelessWidget {
  final int streak;

  const _StreakMessage({required this.streak});

  String get _message {
    if (streak >= 30) return '🏅 Incredible! 30+ days straight. You\'re unstoppable!';
    if (streak >= 14) return '💪 Two weeks straight! You\'re on fire!';
    if (streak >= 7) return '🔥 One full week streak! Keep it going!';
    if (streak >= 3) return '⚡ $streak days in a row — great momentum!';
    return '👍 $streak day streak — keep it up!';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Text(
        _message,
        style: const TextStyle(
          color: Color(0xFF92400E),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  final List<Map<String, dynamic>> rides;
  final DateTime now;

  const _MonthSummary({required this.rides, required this.now});

  @override
  Widget build(BuildContext context) {
    final totalKm = rides.fold<double>(
        0, (sum, r) => sum + (r['distance_km'] as num? ?? 0).toDouble());
    final rideDays = rides
        .map((r) {
          final dt =
              DateTime.tryParse(r['started_at'] as String? ?? '')?.toLocal();
          return dt != null ? '${dt.year}-${dt.month}-${dt.day}' : null;
        })
        .whereType<String>()
        .toSet()
        .length;
    final daysElapsed = now.day;
    final missedDays = (daysElapsed - rideDays).clamp(0, daysElapsed);

    return Container(
      padding: const EdgeInsets.all(18),
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
        children: [
          const Text(
            'This Month',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: 'Rides',
                  value: '${rides.length}',
                  icon: Icons.directions_bike_rounded,
                  color: AppTheme.primary,
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: 'Distance',
                  value: '${totalKm.toStringAsFixed(1)} km',
                  icon: Icons.route_rounded,
                  color: const Color(0xFF0891B2),
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: 'Active Days',
                  value: '$rideDays',
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF16A34A),
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: 'Rest Days',
                  value: '$missedDays',
                  icon: Icons.bed_rounded,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 11)),
      ],
    );
  }
}