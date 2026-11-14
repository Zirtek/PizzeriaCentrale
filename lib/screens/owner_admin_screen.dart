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
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.delivery_dining), text: 'Compensi Rider'),
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
      return (monday, now);
    } else if (_period == 'mese') {
      return (DateTime(now.year, now.month, 1), now);
    }
    return (now, now);
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _dateRange();

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
                                color: AppTheme.brickBrownDark,
                              ),
                            ),
                            Text(
                              '€ ${s.grandTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.terracottaPrimary,
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        Text(
                          'Turni lavorati: ${s.shiftDaysCount} giorni -> € ${s.baseFeesTotal.toStringAsFixed(2)}',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Consegne completate (Diretto + Just Eat): ${s.completedDeliveriesCount} -> € ${s.deliveriesBonusTotal.toStringAsFixed(2)}',
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

class _MenuManagerTab extends StatelessWidget {
  const _MenuManagerTab();

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
                  onChanged: (v) => setDlgState(() => confirmed = v),
                ),
                SwitchListTile(
                  title: const Text('Prodotto disponibile'),
                  value: available,
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
        final items = snapshot.data!;
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              title: Text(
                item.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  decoration:
                  item.available ? null : TextDecoration.lineThrough,
                ),
              ),
              subtitle: Text(
                'Categoria: ${item.category}${!item.priceConfirmed ? " • DA CONFERMARE" : ""}',
                style: TextStyle(
                  color: !item.priceConfirmed
                      ? AppTheme.delayAlertRed
                      : AppTheme.textMutedBrown,
                ),
              ),
              trailing: Text(
                item.price != null
                    ? '€ ${item.price!.toStringAsFixed(2)}'
                    : 'Da confermare',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppTheme.terracottaPrimary,
                ),
              ),
              onTap: () => _editMenuItemDialog(context, item),
            );
          },
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
            leading: const Icon(Icons.pin, color: AppTheme.terracottaPrimary),
            title: Text(
              role.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('PIN protetto con crittografia nel database'),
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