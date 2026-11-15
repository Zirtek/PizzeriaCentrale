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
            Tab(icon: Icon(Icons.lock), text: 'Gestione PIN'),
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

        // Compensi Rider 1 e Rider 2
        FutureBuilder<List<RiderCompensationSummary>>(
          future: Future.wait([
            SupabaseService.instance.calculateRiderCompensation(
              riderRole: 'rider_1',
              riderName: 'Rider 1',
              fromDate: from,
              toDate: to,
            ),
            SupabaseService.instance.calculateRiderCompensation(
              riderRole: 'rider_2',
              riderName: 'Rider 2',
              fromDate: from,
              toDate: to,
            ),
          ]),
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              s.riderName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textWhite,
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
                          'Consegne completate (Diretto + Just Eat): ${s.completedDeliveriesCount} -> € ${s.deliveriesBonusTotal.toStringAsFixed(2)}',
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

class _PinManagerTab extends StatelessWidget {
  const _PinManagerTab();

  Future<void> _changePinDialog(BuildContext context, UserRole role) async {
    final pinCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nuovo PIN per ${role.label}'),
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
              await SupabaseService.instance.updateUserPin(role, pin);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('PIN aggiornato per ${role.label}')),
                );
              }
            },
            child: const Text('Aggiorna PIN'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: UserRole.values.map((role) {
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading:
            const Icon(Icons.pin, color: AppTheme.toCompleteYellow),
            title: Text(
              role.label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.textWhite,
              ),
            ),
            subtitle: const Text(
              'PIN protetto con crittografia nel database',
              style: TextStyle(color: AppTheme.textMuted),
            ),
            trailing: OutlinedButton(
              onPressed: () => _changePinDialog(context, role),
              child: const Text('Cambia PIN'),
            ),
          ),
        );
      }).toList(),
    );
  }
}