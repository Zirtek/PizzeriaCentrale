import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class PinLoginScreen extends StatefulWidget {
  final ValueChanged<AppUserSession> onAuthenticated;

  const PinLoginScreen({super.key, required this.onAuthenticated});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  List<UserProfile> _profiles = UserProfile.fallbackDefaults();
  String _selectedRole = UserRole.titolare;
  String _pin = '';
  bool _isLoading = false;
  bool _loadingProfiles = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() => _loadingProfiles = true);
    try {
      final fetched = await SupabaseService.instance.fetchUserProfiles();
      if (!mounted) return;
      setState(() {
        _profiles = fetched;
        if (!_profiles.any((p) => p.role == _selectedRole) &&
            _profiles.isNotEmpty) {
          _selectedRole = _profiles.first.role;
        }
        _loadingProfiles = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProfiles = false);
    }
  }

  UserProfile get _currentProfile {
    return _profiles.firstWhere(
          (p) => p.role == _selectedRole,
      orElse: () => _profiles.first,
    );
  }

  void _onDigitTap(String digit) {
    if (_pin.length >= 4 || _isLoading) return;
    setState(() {
      _pin += digit;
      _errorMessage = null;
    });
    if (_pin.length == 4) {
      _submitPin();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty || _isLoading) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _errorMessage = null;
    });
  }

  Future<void> _submitPin() async {
    setState(() => _isLoading = true);
    try {
      final session =
      await SupabaseService.instance.loginWithPin(_selectedRole, _pin);
      if (!mounted) return;
      if (session != null) {
        widget.onAuthenticated(session);
      } else {
        setState(() {
          _pin = '';
          _errorMessage = 'PIN non corretto per ${_currentProfile.displayName}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pin = '';
        _errorMessage = 'Errore di connessione al database';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData _iconForRole(String role) {
    if (role == UserRole.titolare) return Icons.admin_panel_settings;
    if (role == UserRole.dipendente) return Icons.local_pizza;
    return Icons.delivery_dining;
  }

  String _subtitleForRole(String role) {
    if (role == UserRole.titolare) return 'Agenda, incassi e listino';
    if (role == UserRole.dipendente) return 'Comande e preparazione';
    return 'Consegne e cassa turno';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundBlack,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceDark,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.toCompleteYellow, width: 2),
                        ),
                        child: const Icon(
                          Icons.local_fire_department,
                          size: 34,
                          color: AppTheme.toStartRed,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PIZZERIA CENTRALE',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textWhite,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            'Accesso rapido postazione',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '1. CHI STA ACCEDENDO?',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMuted,
                          letterSpacing: 0.6,
                        ),
                      ),
                      InkWell(
                        onTap: _loadingProfiles ? null : _loadProfiles,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.refresh,
                                size: 15,
                                color: _loadingProfiles
                                    ? AppTheme.textMuted
                                    : AppTheme.toCompleteYellow,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Aggiorna',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _loadingProfiles
                                      ? AppTheme.textMuted
                                      : AppTheme.toCompleteYellow,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Griglia dinamica dei profili attivi (Titolare, Dipendente, Rider 1..N)
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.15,
                    children: _profiles.map((profile) {
                      final selected = _selectedRole == profile.role;
                      return InkWell(
                        onTap: () => setState(() {
                          _selectedRole = profile.role;
                          _pin = '';
                          _errorMessage = null;
                        }),
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.toCompleteYellow
                                : AppTheme.surfaceDark,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? AppTheme.toCompleteYellow
                                  : AppTheme.cardBorder,
                              width: selected ? 2 : 1.2,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Icon(
                                _iconForRole(profile.role),
                                size: 26,
                                color: selected
                                    ? Colors.black
                                    : AppTheme.toCompleteYellow,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      profile.displayName,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: selected
                                            ? Colors.black
                                            : AppTheme.textWhite,
                                      ),
                                    ),
                                    Text(
                                      _subtitleForRole(profile.role),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: selected
                                            ? Colors.black87
                                            : AppTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),

                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '2. DIGITA IL PIN (4 CIFRE)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 4 caselle PIN visive
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final filled = index < _pin.length;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 48,
                        height: 52,
                        decoration: BoxDecoration(
                          color: filled
                              ? AppTheme.moneyGreen
                              : AppTheme.surfaceDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: filled
                                ? AppTheme.moneyGreen
                                : AppTheme.cardBorder,
                            width: 1.8,
                          ),
                        ),
                        child: Center(
                          child: filled
                              ? const Icon(Icons.circle,
                              size: 14, color: Colors.black)
                              : null,
                        ),
                      );
                    }),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.darkRedTint,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.toStartRed),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppTheme.toStartRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    )
                  else
                    _buildNumericKeypad(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumericKeypad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '<'],
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((key) {
              final isAction = key == 'C' || key == '<';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 86,
                  height: 62,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isAction
                          ? AppTheme.surfaceDark
                          : AppTheme.surfaceElevated,
                      foregroundColor: isAction
                          ? AppTheme.toStartRed
                          : AppTheme.textWhite,
                      elevation: 0,
                      side: const BorderSide(color: AppTheme.cardBorder),
                    ),
                    onPressed: () {
                      if (key == 'C') {
                        setState(() {
                          _pin = '';
                          _errorMessage = null;
                        });
                      } else if (key == '<') {
                        _onBackspace();
                      } else {
                        _onDigitTap(key);
                      }
                    },
                    child: key == '<'
                        ? const Icon(Icons.backspace_outlined)
                        : Text(
                      key,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}