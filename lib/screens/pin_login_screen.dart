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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundBlack,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewportConstraints) {
            final isSmallPhone = viewportConstraints.maxWidth < 380;
            final horizontalPad = isSmallPhone ? 14.0 : 20.0;
            final logoSize = isSmallPhone ? 74.0 : 88.0;

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPad,
                  vertical: 12,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo Pizzeria Centrale compatto
                      Container(
                        width: logoSize,
                        height: logoSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFEDE2CE),
                          border: Border.all(
                            color: AppTheme.toCompleteYellow,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.45),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/icon/logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.local_pizza,
                              size: logoSize * 0.45,
                              color: const Color(0xFF3D2414),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '1. CHI STA ACCEDENDO?',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textMuted,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: _loadingProfiles ? null : _loadProfiles,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
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

                      // Griglia compatta con solo icona e nome profilo
                      GridView.builder(
                        itemCount: _profiles.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                          viewportConstraints.maxWidth < 310 ? 1 : 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          mainAxisExtent: isSmallPhone ? 46 : 50,
                        ),
                        itemBuilder: (context, index) {
                          final profile = _profiles[index];
                          final selected = _selectedRole == profile.role;
                          return InkWell(
                            onTap: () => setState(() {
                              _selectedRole = profile.role;
                              _pin = '';
                              _errorMessage = null;
                            }),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppTheme.toCompleteYellow
                                    : AppTheme.surfaceDark,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? AppTheme.toCompleteYellow
                                      : AppTheme.cardBorder,
                                  width: selected ? 2 : 1.2,
                                ),
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: isSmallPhone ? 10 : 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _iconForRole(profile.role),
                                    size: isSmallPhone ? 20 : 22,
                                    color: selected
                                        ? Colors.black
                                        : AppTheme.toCompleteYellow,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      profile.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: isSmallPhone ? 14 : 15,
                                        color: selected
                                            ? Colors.black
                                            : AppTheme.textWhite,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

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
                          final boxSize = isSmallPhone ? 44.0 : 48.0;
                          return Container(
                            margin: EdgeInsets.symmetric(
                                horizontal: isSmallPhone ? 6 : 8),
                            width: boxSize,
                            height: boxSize + 4,
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
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.darkRedTint,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.toStartRed),
                          ),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppTheme.toStartRed,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),

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
            );
          },
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

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final availableWidth = constraints.maxWidth;
        final keyWidth =
        ((availableWidth - (gap * 2)) / 3).clamp(64.0, 96.0);
        final keyHeight = keyWidth < 76 ? 54.0 : 60.0;

        return Column(
          children: keys.map((row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: gap),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(row.length, (colIndex) {
                  final key = row[colIndex];
                  final isAction = key == 'C' || key == '<';
                  return Padding(
                    padding: EdgeInsets.only(
                      right: colIndex == row.length - 1 ? 0 : gap,
                    ),
                    child: SizedBox(
                      width: keyWidth,
                      height: keyHeight,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
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
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}