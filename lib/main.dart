import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'models/models.dart';
import 'services/session_storage_service.dart';
import 'services/supabase_service.dart';
import 'screens/pin_login_screen.dart';
import 'screens/agenda_screen.dart';
import 'screens/rider_screen.dart';

const String supabaseUrl = 'https://wsvxudlpzjiumgypvtoc.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indzdnh1ZGxwemppdW1neXB2dG9jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1OTI0NzksImV4cCI6MjExMDE2ODQ3OX0.lrix7n7l5XVz_WhW_SXHQDeKuwSSFJNcyzj1xoB8h9c';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT', null);

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  final restoredSession = await SessionStorageService.instance.loadSession();

  runApp(PizzeriaApp(initialSession: restoredSession));
}

class PizzeriaApp extends StatefulWidget {
  final AppUserSession? initialSession;

  const PizzeriaApp({super.key, this.initialSession});

  @override
  State<PizzeriaApp> createState() => _PizzeriaAppState();
}

class _PizzeriaAppState extends State<PizzeriaApp> {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
  GlobalKey<ScaffoldMessengerState>();
  AppUserSession? _currentSession;

  @override
  void initState() {
    super.initState();
    _currentSession = widget.initialSession;
    if (_currentSession != null) {
      _validateRestoredSession(_currentSession!);
    }
  }

  Future<void> _validateRestoredSession(AppUserSession session) async {
    try {
      final profile = await SupabaseService.instance
          .fetchActiveProfileByRole(session.role);
      if (!mounted) return;

      if (profile == null) {
        await _onLogout();
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content:
            Text('Profilo disattivato. Effettua nuovamente l\'accesso.'),
          ),
        );
        return;
      }

      if (profile.displayName != session.displayName) {
        final updated = AppUserSession(
          id: session.id,
          role: session.role,
          displayName: profile.displayName,
        );
        await SessionStorageService.instance.saveSession(updated);
        if (mounted) {
          setState(() {
            _currentSession = updated;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _onLoginSuccess(AppUserSession session) async {
    await SessionStorageService.instance.saveSession(session);
    if (!mounted) return;
    setState(() {
      _currentSession = session;
    });
  }

  Future<void> _onLogout() async {
    await SessionStorageService.instance.clearSession();
    if (!mounted) return;
    setState(() {
      _currentSession = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestionale Pizzeria',
      scaffoldMessengerKey: _messengerKey,
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

    if (session.isRider) {
      return RiderScreen(session: session, onLogout: _onLogout);
    }

    return AgendaScreen(session: session, onLogout: _onLogout);
  }
}