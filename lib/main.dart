import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'models/models.dart';
import 'screens/pin_login_screen.dart';
import 'screens/agenda_screen.dart';
import 'screens/rider_screen.dart';

// INSERISCI QUI LE TUE CHIAVI SUPABASE (Project Settings -> API)
const String supabaseUrl = 'https://wsvxudlpzjiumgypvtoc.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indzdnh1ZGxwemppdW1neXB2dG9jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1OTI0NzksImV4cCI6MjExMDE2ODQ3OX0.lrix7n7l5XVz_WhW_SXHQDeKuwSSFJNcyzj1xoB8h9c';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT', null);

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const PizzeriaApp());
}

class PizzeriaApp extends StatefulWidget {
  const PizzeriaApp({super.key});

  @override
  State<PizzeriaApp> createState() => _PizzeriaAppState();
}

class _PizzeriaAppState extends State<PizzeriaApp> {
  AppUserSession? _currentSession;

  void _onLoginSuccess(AppUserSession session) {
    setState(() {
      _currentSession = session;
    });
  }

  void _onLogout() {
    setState(() {
      _currentSession = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestionale Pizzeria',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: const Locale('it', 'IT'),
      supportedLocales: const [Locale('it', 'IT')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    final session = _currentSession;
    if (session == null) {
      return PinLoginScreen(onAuthenticated: _onLoginSuccess);
    }

    if (session.role == UserRole.rider1 || session.role == UserRole.rider2) {
      return RiderScreen(session: session, onLogout: _onLogout);
    }

    return AgendaScreen(session: session, onLogout: _onLogout);
  }
}