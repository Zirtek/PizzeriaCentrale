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
  UserRole _selectedRole = UserRole.titolare;
  String _pin = '';
  bool _isLoading = false;
  String? _errorMessage;

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
          _errorMessage = 'PIN non corretto per ${_selectedRole.label}';
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

  IconData _iconForRole(UserRole role) {
    switch (role) {
      case UserRole.titolare:
        return Icons.admin_panel_settings;
      case UserRole.dipendente:
        return Icons.local_pizza;
      case UserRole.rider1:
      case UserRole.rider2:
        return Icons.delivery_dining;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundWhite,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.warmSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.cardBorder, width: 2),
                    ),
                    child: const Icon(
                      Icons.local_fire_department,
                      size: 48,
                      color: AppTheme.terracottaPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'GESTIONE PIZZERIA',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.brickBrownDark,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Seleziona il profilo e digita il PIN a 4 cifre',
                    style: TextStyle(color: AppTheme.textMutedBrown),
                  ),
                  const SizedBox(height: 24),

                  // Griglia selezione profilo
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.5,
                    children: UserRole.values.map((role) {
                      final selected = _selectedRole == role;
                      return InkWell(
                        onTap: () => setState(() {
                          _selectedRole = role;
                          _pin = '';
                          _errorMessage = null;
                        }),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.terracottaPrimary
                                : AppTheme.warmSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? AppTheme.brickBrownDark
                                  : AppTheme.cardBorder,
                              width: 1.5,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _iconForRole(role),
                                color: selected
                                    ? Colors.white
                                    : AppTheme.terracottaPrimary,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  role.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: selected
                                        ? Colors.white
                                        : AppTheme.textDarkBrown,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  // Indicatori 4 pallini PIN
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final filled = index < _pin.length;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled
                              ? AppTheme.terracottaPrimary
                              : Colors.transparent,
                          border: Border.all(
                            color: AppTheme.terracottaPrimary,
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: AppTheme.delayAlertRed,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Tastierino numerico grande
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
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 82,
                  height: 64,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: key == 'C' || key == '<'
                          ? AppTheme.warmSurface
                          : AppTheme.terracottaPrimary,
                      foregroundColor: key == 'C' || key == '<'
                          ? AppTheme.brickBrownDark
                          : Colors.white,
                      side: const BorderSide(color: AppTheme.cardBorder),
                    ),
                    onPressed: () {
                      if (key == 'C') {
                        setState(() => _pin = '');
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