import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/ride/home_screen.dart';
import 'features/ride/ride_screen.dart';
import 'features/history/history_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/goals/goals_screen.dart';
import 'shared/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  runApp(
    const ProviderScope(
      child: TrackRideApp(),
    ),
  );
}

class TrackRideApp extends StatefulWidget {
  const TrackRideApp({super.key});

  @override
  State<TrackRideApp> createState() => _TrackRideAppState();
}

class _TrackRideAppState extends State<TrackRideApp> {
  // The navigator key lets us push routes from outside the widget tree
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();

    // Listen to auth state changes and redirect accordingly
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;

      if (event == AuthChangeEvent.signedIn) {
        navigator.pushNamedAndRemoveUntil('/home', (route) => false);
      } else if (event == AuthChangeEvent.signedOut) {
        navigator.pushNamedAndRemoveUntil('/login', (route) => false);
      }
    });
  }

  // Determine the initial route based on whether a session already exists
  String get _initialRoute {
    final session = Supabase.instance.client.auth.currentSession;
    return session != null ? '/home' : '/login';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrackRide',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: _navigatorKey,
      initialRoute: _initialRoute,
      routes: {
        '/login':    (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/home':     (_) => const HomeScreen(),
        '/ride':     (_) => const RideScreen(),
        '/history':  (_) => const HistoryScreen(),
        '/profile':  (_) => const ProfileScreen(),
        '/goals':    (_) => const GoalsScreen(),
      },
    );
  }
}