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

class TrackRideApp extends StatelessWidget {
  const TrackRideApp({super.key});

  @override 
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrackRide',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: '/login',
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