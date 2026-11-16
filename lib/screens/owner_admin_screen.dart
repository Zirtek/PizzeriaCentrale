import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class OwnerAdminScreen extends StatefulWidget {
  const OwnerAdminScreen({super.key});

  @override
  State<OwnerAdminScreen> createState() => _OwnerAdminScreenState();
}

class _OwnerAdminScreenState extends State<OwnerAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Area Riservata Titolare'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.moneyGreen,
          labelColor: AppTheme.moneyGreen,
          unselectedLabelColor: AppTheme.textMuted,
          tabs: const [
            Tab(icon: Icon(Icons.payments_outlined), text: 'Incassi e Rider'),
            Tab(icon: Icon(Icons.restaurant_menu), text: 'Menu e Prezzi'),
            Tab(icon: Icon(Icons.group), text: 'Team e PIN'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _RiderCompensationsTab(),
          _MenuManagerTab(),
          _PinManagerTab(),
        ],
      ),
    );
  }
}

class _RiderCompensationsTab extends StatefulWidget {
  const _RiderCompensationsTab();

  @override
  State<_RiderCompensationsTab> createState() => _RiderCompensationsTabState();
}

class _RiderCompensationsTabState extends State<_RiderCompensationsTab> {
  String _period = 'oggi'; // 'oggi', 'settimana', 'mese'

  final _weekdayFeeCtrl = TextEditingController(text: '15.00');
  final _saturdayFeeCtrl = TextEditingController(text: '20.00');
  final _bonusFeeCtrl = TextEditingController(text: '2.00');

  bool _loadingConfig = true;
  bool _savingRates = false;
  RiderRates _rates = const RiderRates();
  List<UserProfile> _riders = [];

  @override
  void initState() {
    super.initState();
    _loadSettingsAndRiders();
  }

  @override
  void dispose() {
    _weekdayFeeCtrl.dispose();
    _saturdayFeeCtrl.dispose();
    _bonusFeeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettingsAndRiders() async {
    setState(() => _loadingConfig = true);
    try {
      final results = await Future.wait([
        SupabaseService.instance.fetchRiderRates(),
        SupabaseService.instance.fetchUserProfiles(includeInactive: true),
      ]);
      if (!mounted) return;
      final fetchedRates = results[0] as RiderRates;
      final allProfiles = results[1] as List<UserProfile>;

      setState(() {
        _rates = fetchedRates;
        _weekdayFeeCtrl.text = fetchedRates.weekdayBaseFee.toStringAsFixed(2);
        _saturdayFeeCtrl.text = fetchedRates.saturdayBaseFee.toStringAsFixed(2);
        _bonusFeeCtrl.text = fetchedRates.perDeliveryBonus.toStringAsFixed(2);
        _riders = allProfiles.where((p) => p.isRider).toList();
        _loadingConfig = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingConfig = false);
    }
  }

  Future<void> _saveRates() async {
    final weekday =
    double.tryParse(_weekdayFeeCtrl.text.trim().replaceAll(',', '.'));
    final saturday =
    double.tryParse(_saturdayFeeCtrl.text.trim().replaceAll(',', '.'));
    final bonus =
    double.tryParse(_bonusFeeCtrl.text.trim().replaceAll(',', '.'));

    if (weekday == null ||
        weekday < 0 ||
        saturday == null ||
        saturday < 0 ||
        bonus == null ||
        bonus < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci importi numerici validi (es. 15.00)'),
        ),
      );
      return;
    }

    setState(() => _savingRates = true);
    try {
      final updated = RiderRates(
        weekdayBaseFee: weekday,
        saturdayBaseFee: saturday,
        perDeliveryBonus: bonus,
      );
      await SupabaseService.instance.updateRiderRates(updated);
      if (!mounted) return;
      setState(() {
        _rates = updated;
      });
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tariffe rider salvate con successo')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore salvataggio tariffe: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingRates = false);
    }
  }

  (DateTime, DateTime) _dateRange() {
    final now = DateTime.now();
    if (_period == 'settimana') {
      final monday = now.subtract(Duration(days: now.weekday - 1));
      return (DateTime(monday.year, monday.month, monday.day), now);
    } else if (_period == 'mese') {
      return (DateTime(now.year, now.month, 1), now);
    }
    return (DateTime(now.year, now.month, now.day), now);
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _dateRange();
    final endOfDay = DateTime(to.year, to.month, to.day, 23, 59, 59);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'oggi', label: Text('Oggi')),
            ButtonSegment(value: 'settimana', label: Text('Settimana')),
            ButtonSegment(value: 'mese', label: Text('Mese')),
          ],
          selected: {_period},
          onSelectionChanged: (s) => setState(() => _period = s.first),
        ),
        const SizedBox(height: 16),

        // Riepilogo Incassi del periodo selezionato
        StreamBuilder<List<PizzeriaOrder>>(
          stream: SupabaseService.instance.watchOrders(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final periodOrders = snapshot.data!.where((o) {
              return !o.scheduledFor.isBefore(from) &&
                  !o.scheduledFor.isAfter(endOfDay);
            }).toList();

            final paidTotal = periodOrders
                .where((o) => o.isPaid)
                .fold<double>(0.0, (sum, o) => sum + o.totalAmount);
            final pendingTotal = periodOrders
                .where((o) => !o.isPaid)
                .fold<double>(0.0, (sum, o) => sum + o.totalAmount);
            final completedCount = periodOrders
                .where((o) => o.status == OrderStatus.completato)
                .length;

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RIEPILOGO INCASSI PERIODO',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textWhite,
                      ),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Incassato confermato:'),
                        Text(
                          '€ ${paidTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.moneyGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('In sospeso (non completati):'),
                        Text(
                          '€ ${pendingTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.toCompleteYellow,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Ordini completati:'),
                        Text(
                          '$completedCount su ${periodOrders.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.completedGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        // Configurazione Tariffe Rider
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune,
                        size: 18, color: AppTheme.toCompleteYellow),
                    SizedBox(width: 8),
                    Text(
                      'TARIFFE COMPENSI RIDER',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.toCompleteYellow,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _weekdayFeeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Feriale (€)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _saturdayFeeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Sabato (€)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _bonusFeeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'A consegna (€)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _savingRates ? null : _saveRates,
                    icon: _savingRates
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _savingRates ? 'SALVATAGGIO...' : 'SALVA TARIFFE',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Compensi dinamici per TUTTI i rider configurati
        if (_loadingConfig)
          const Center(child: CircularProgressIndicator())
        else if (_riders.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Nessun rider configurato. Aggiungine uno dalla scheda "Team e PIN".',
                style: TextStyle(color: AppTheme.textMuted),
              ),
            ),
          )
        else
          FutureBuilder<List<RiderCompensationSummary>>(
            future: Future.wait(
              _riders.map(
                    (r) => SupabaseService.instance.calculateRiderCompensation(
                  riderRole: r.role,
                  riderName: r.displayName,
                  isActive: r.isActive,
                  fromDate: from,
                  toDate: to,
                  rates: _rates,
                ),
              ),
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final summaries = snapshot.data!;
              return Column(
                children: summaries.map((s) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        s.riderName,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textWhite,
                                        ),
                                      ),
                                    ),
                                    if (!s.isActive) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.darkRedTint,
                                          borderRadius:
                                          BorderRadius.circular(6),
                                          border: Border.all(
                                              color: AppTheme.toStartRed),
                                        ),
                                        child: const Text(
                                          'DISATTIVATO',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.toStartRed,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Text(
                                '€ ${s.grandTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.moneyGreen,
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          Text(
                            'Turni lavorati: ${s.shiftDaysCount} giorni -> € ${s.baseFeesTotal.toStringAsFixed(2)}',
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Consegne completate (Diretto + Just Eat): ${s.completedDeliveriesCount} × € ${_rates.perDeliveryBonus.toStringAsFixed(2)} -> € ${s.deliveriesBonusTotal.toStringAsFixed(2)}',
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }
}

class _MenuManagerTab extends StatefulWidget {
  const _MenuManagerTab();

  @override
  State<_MenuManagerTab> createState() => _MenuManagerTabState();
}

class _MenuManagerTabState extends State<_MenuManagerTab> {
  String _search = '';
  String _filter = 'tutti';

  static const _menuCategories = [
    ('pizza_tonda', 'Pizze Tonde'),
    ('fritti', 'Fritti'),
    ('bevande', 'Bevande'),
    ('speciale_giorno', 'Speciali Mar/Mer'),
    ('teglia_gusto_semplice', 'Teglia - Gusto Semplice'),
    ('teglia_gusto_speciale', 'Teglia - Gusto Speciale'),
  ];

  Future<void> _addNewMenuItemDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String selectedCategory = 'bevande';
    bool confirmed = true;
    bool available = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            title: const Text('Nuovo Prodotto a Listino'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: _menuCategories
                        .map((c) => DropdownMenuItem(
                      value: c.$1,
                      child: Text(c.$2),
                    ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDlgState(() => selectedCategory = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome prodotto * (es. Coca Cola lattina)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: priceCtrl,
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Prezzo (€) (es. 2.50)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Prezzo confermato definitivo'),
                    value: confirmed,
                    activeColor: AppTheme.moneyGreen,
                    onChanged: (v) => setDlgState(() => confirmed = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Prodotto disponibile'),
                    value: available,
                    activeColor: AppTheme.moneyGreen,
                    onChanged: (v) => setDlgState(() => available = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annulla'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Inserisci il nome del prodotto'),
                      ),
                    );
                    return;
                  }
                  final parsedPrice = double.tryParse(
                    priceCtrl.text.replaceAll(',', '.'),
                  );
                  await SupabaseService.instance.addMenuItem(
                    category: selectedCategory,
                    name: nameCtrl.text,
                    price: parsedPrice,
                    priceConfirmed: confirmed,
                    available: available,
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Aggiunto: ${nameCtrl.text.trim()}'),
                      ),
                    );
                  }
                },
                child: const Text('Aggiungi'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editMenuItemDialog(
      BuildContext context, MenuItemModel item) async {
    final priceCtrl = TextEditingController(
      text: item.price != null ? item.price!.toStringAsFixed(2) : '',
    );
    bool confirmed = item.priceConfirmed;
    bool available = item.available;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            title: Text('Modifica: ${item.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: priceCtrl,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Prezzo (€)'),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  title: const Text('Prezzo confermato definitivo'),
                  value: confirmed,
                  activeColor: AppTheme.moneyGreen,
                  onChanged: (v) => setDlgState(() => confirmed = v),
                ),
                SwitchListTile(
                  title: const Text('Prodotto disponibile'),
                  value: available,
                  activeColor: AppTheme.moneyGreen,
                  onChanged: (v) => setDlgState(() => available = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annulla'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final parsed = double.tryParse(
                    priceCtrl.text.replaceAll(',', '.'),
                  );
                  await SupabaseService.instance.updateMenuItem(
                    id: item.id,
                    price: parsed,
                    priceConfirmed: confirmed,
                    available: available,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Salva'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MenuItemModel>>(
      stream: SupabaseService.instance.watchMenu(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!.where((item) {
          if (_filter == 'da_confermare' && item.priceConfirmed) return false;
          if (_filter == 'non_disponibili' && item.available) return false;
          if (_search.isNotEmpty &&
              !item.name.toLowerCase().contains(_search.toLowerCase())) {
            return false;
          }
          return true;
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _addNewMenuItemDialog(context),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('NUOVO PRODOTTO'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: const InputDecoration(
                  hintText: 'Cerca prodotto nel listino...',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  for (final opt in [
                    ('tutti', 'Tutti'),
                    ('da_confermare', 'Prezzi da confermare'),
                    ('non_disponibili', 'Non disponibili'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(opt.$2),
                        selected: _filter == opt.$1,
                        selectedColor: AppTheme.toCompleteYellow,
                        labelStyle: TextStyle(
                          color: _filter == opt.$1
                              ? Colors.black
                              : AppTheme.textWhite,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (_) => setState(() => _filter = opt.$1),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    title: Text(
                      item.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textWhite,
                        decoration:
                        item.available ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    subtitle: Text(
                      'Categoria: ${item.category}${!item.priceConfirmed ? " • DA CONFERMARE" : ""}',
                      style: TextStyle(
                        color: !item.priceConfirmed
                            ? AppTheme.toCompleteYellow
                            : AppTheme.textMuted,
                      ),
                    ),
                    trailing: Text(
                      item.price != null
                          ? '€ ${item.price!.toStringAsFixed(2)}'
                          : 'Da confermare',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: item.price != null
                            ? AppTheme.moneyGreen
                            : AppTheme.toCompleteYellow,
                      ),
                    ),
                    onTap: () => _editMenuItemDialog(context, item),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PinManagerTab extends StatefulWidget {
  const _PinManagerTab();

  @override
  State<_PinManagerTab> createState() => _PinManagerTabState();
}

class _PinManagerTabState extends State<_PinManagerTab> {
  List<UserProfile> _profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() => _loading = true);
    try {
      final list = await SupabaseService.instance
          .fetchUserProfiles(includeInactive: true);
      if (mounted) {
        setState(() {
          _profiles = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _nextAvailableRiderRole() {
    final usedNumbers = _profiles
        .where((p) => p.isRider)
        .map((p) => UserRole.riderNumber(p.role))
        .toSet();
    int candidate = 1;
    while (usedNumbers.contains(candidate)) {
      candidate++;
    }
    return 'rider_$candidate';
  }

  Future<void> _addNewRiderDialog() async {
    final nextRole = _nextAvailableRiderRole();
    final nextLabel = UserRole.defaultLabel(nextRole);
    final nameCtrl = TextEditingController(text: nextLabel);
    final pinCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Aggiungi Nuovo Rider ($nextLabel)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome visualizzato (es. Rider 3 o Marco)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pinCtrl,
              maxLength: 4,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'PIN iniziale (4 cifre)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final pin = pinCtrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Inserisci il nome del rider')),
                );
                return;
              }
              if (pin.length != 4 || int.tryParse(pin) == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Il PIN deve essere di 4 cifre numeriche')),
                );
                return;
              }

              try {
                await SupabaseService.instance.upsertRiderProfile(
                  role: nextRole,
                  displayName: name,
                  pin: pin,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadProfiles();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Rider "$name" aggiunto')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Errore creazione rider: $e')),
                  );
                }
              }
            },
            child: const Text('Crea Rider'),
          ),
        ],
      ),
    );
  }

  Future<void> _editRiderNameDialog(UserProfile profile) async {
    final nameCtrl = TextEditingController(text: profile.displayName);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rinomina ${profile.displayName}'),
        content: TextField(
          controller: nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nuovo nome visualizzato',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              try {
                await SupabaseService.instance.upsertRiderProfile(
                  role: profile.role,
                  displayName: name,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadProfiles();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Errore modifica nome: $e')),
                  );
                }
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePinDialog(UserProfile profile) async {
    final pinCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nuovo PIN per ${profile.displayName}'),
        content: TextField(
          controller: pinCtrl,
          maxLength: 4,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Nuovo PIN (4 cifre)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () async {
              final pin = pinCtrl.text.trim();
              if (pin.length != 4 || int.tryParse(pin) == null) return;
              await SupabaseService.instance.updateUserPin(profile.role, pin);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('PIN aggiornato per ${profile.displayName}'),
                  ),
                );
              }
            },
            child: const Text('Aggiorna PIN'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteRider(UserProfile profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminare ${profile.displayName}?'),
        content: const Text(
          'Il profilo verrà rimosso dall\'accesso. Se preferisci conservare lo storico turni, usa invece lo switch per disattivarlo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.toStartRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await SupabaseService.instance.deleteRiderProfile(profile.role);
      await _loadProfiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore eliminazione: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _addNewRiderDialog,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('AGGIUNGI NUOVO RIDER'),
          ),
        ),
        const SizedBox(height: 14),
        ..._profiles.map((profile) {
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        profile.isOwner
                            ? Icons.admin_panel_settings
                            : (profile.isDipendente
                            ? Icons.local_pizza
                            : Icons.delivery_dining),
                        color: profile.isActive
                            ? AppTheme.toCompleteYellow
                            : AppTheme.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: profile.isActive
                                    ? AppTheme.textWhite
                                    : AppTheme.textMuted,
                                decoration: profile.isActive
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                            Text(
                              'Codice: ${profile.role} • ${profile.isActive ? "Attivo" : "Disattivato"}',
                              style: TextStyle(
                                fontSize: 12,
                                color: profile.isActive
                                    ? AppTheme.textMuted
                                    : AppTheme.toStartRed,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (profile.isRider)
                        Switch(
                          value: profile.isActive,
                          activeColor: AppTheme.moneyGreen,
                          onChanged: (val) async {
                            await SupabaseService.instance
                                .setUserActive(profile.role, val);
                            await _loadProfiles();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _changePinDialog(profile),
                        icon: const Icon(Icons.pin, size: 17),
                        label: const Text('Cambia PIN'),
                      ),
                      if (profile.isRider) ...[
                        OutlinedButton.icon(
                          onPressed: () => _editRiderNameDialog(profile),
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          label: const Text('Nome'),
                        ),
                        IconButton(
                          tooltip: 'Elimina rider',
                          icon: const Icon(Icons.delete_outline,
                              color: AppTheme.toStartRed),
                          onPressed: () => _confirmDeleteRider(profile),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}