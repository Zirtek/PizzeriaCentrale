import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'new_order_screen.dart';
import 'owner_admin_screen.dart';

enum AgendaFilter {
  tutti('Tutti'),
  inRitardo('In ritardo'),
  nonPagati('Non pagati'),
  senzaRider('Senza rider');

  final String label;
  const AgendaFilter(this.label);
}

class AgendaScreen extends StatefulWidget {
  final AppUserSession session;
  final VoidCallback onLogout;

  const AgendaScreen({
    super.key,
    required this.session,
    required this.onLogout,
  });

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  DateTime _selectedDate = DateTime.now();
  AgendaFilter _activeFilter = AgendaFilter.tutti;
  bool _hideCompleted = false;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    // Aggiorna l'interfaccia ogni 30 secondi per evidenziare tempestivamente gli ordini in ritardo
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
      locale: const Locale('it', 'IT'),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormatted =
    DateFormat('EEEE d MMMM yyyy', 'it_IT').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Agenda Ordini',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
            Text(
              'Accesso: ${widget.session.displayName}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          if (widget.session.isOwner)
            IconButton(
              tooltip: 'Menu, Prezzi e Compensi Rider',
              icon: const Icon(Icons.bar_chart_rounded, size: 28),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OwnerAdminScreen(),
                  ),
                );
              },
            ),
          IconButton(
            tooltip: 'Cambia profilo / Esci',
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.terracottaPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_circle_outline, size: 28),
        label: const Text(
          'NUOVO ORDINE',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NewOrderScreen(initialDate: _selectedDate),
            ),
          );
        },
      ),
      body: Column(
        children: [
          // Barra navigazione data
          Container(
            color: AppTheme.warmSurface,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 30),
                  color: AppTheme.brickBrownDark,
                  onPressed: () => setState(() {
                    _selectedDate =
                        _selectedDate.subtract(const Duration(days: 1));
                  }),
                ),
                InkWell(
                  onTap: _pickDate,
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 18, color: AppTheme.terracottaPrimary),
                      const SizedBox(width: 8),
                      Text(
                        dateFormatted.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppTheme.brickBrownDark,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 30),
                  color: AppTheme.brickBrownDark,
                  onPressed: () => setState(() {
                    _selectedDate = _selectedDate.add(const Duration(days: 1));
                  }),
                ),
              ],
            ),
          ),

          // Barra Filtri rapidi
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ...AgendaFilter.values.map((filter) {
                  final selected = _activeFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filter.label),
                      selected: selected,
                      selectedColor: AppTheme.terracottaPrimary,
                      labelStyle: TextStyle(
                        color:
                        selected ? Colors.white : AppTheme.textDarkBrown,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) =>
                          setState(() => _activeFilter = filter),
                    ),
                  );
                }),
                FilterChip(
                  label: const Text('Nascondi completati'),
                  selected: _hideCompleted,
                  selectedColor: AppTheme.brickBrownDark,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _hideCompleted
                        ? Colors.white
                        : AppTheme.textDarkBrown,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (val) => setState(() => _hideCompleted = val),
                ),
              ],
            ),
          ),

          // Lista ordini in tempo reale
          Expanded(
            child: StreamBuilder<List<PizzeriaOrder>>(
              stream: SupabaseService.instance.watchOrders(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Errore caricamento ordini: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allOrders = snapshot.data!;
                var dayOrders = allOrders
                    .where((o) => _isSameDay(o.scheduledFor, _selectedDate))
                    .toList();

                // Riepilogo incassi rapido per il solo Titolare
                final dayRevenue = dayOrders.fold<double>(
                    0.0, (sum, o) => sum + o.totalAmount);

                // Applica filtri
                if (_hideCompleted) {
                  dayOrders = dayOrders
                      .where((o) => o.status != OrderStatus.completato)
                      .toList();
                }
                if (_activeFilter == AgendaFilter.inRitardo) {
                  dayOrders = dayOrders.where((o) => o.isDelayed).toList();
                } else if (_activeFilter == AgendaFilter.nonPagati) {
                  dayOrders = dayOrders.where((o) => !o.isPaid).toList();
                } else if (_activeFilter == AgendaFilter.senzaRider) {
                  dayOrders = dayOrders
                      .where((o) =>
                  o.needsInternalRider && o.assignedRider == null)
                      .toList();
                }

                dayOrders
                    .sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

                return Column(
                  children: [
                    if (widget.session.isOwner)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        color: const Color(0xFFF3E5DF),
                        child: Text(
                          'Ordini giorno: ${dayOrders.length}  •  Totale previsto: € ${dayRevenue.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.brickBrownDark,
                          ),
                        ),
                      ),
                    Expanded(
                      child: dayOrders.isEmpty
                          ? const Center(
                        child: Text(
                          'Nessun ordine presente per i filtri selezionati.',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppTheme.textMutedBrown,
                          ),
                        ),
                      )
                          : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                        itemCount: dayOrders.length,
                        itemBuilder: (context, index) {
                          return _OrderAgendaCard(
                            order: dayOrders[index],
                            isOwner: widget.session.isOwner,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderAgendaCard extends StatelessWidget {
  final PizzeriaOrder order;
  final bool isOwner;

  const _OrderAgendaCard({required this.order, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    final timeRequested = DateFormat('HH:mm').format(order.scheduledFor);
    final timeReceived = DateFormat('HH:mm').format(order.createdAt);
    final nextStatus =
    order.status.nextStatus(order.deliveryType, order.source);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: order.isDelayed
              ? AppTheme.delayAlertRed
              : AppTheme.cardBorder,
          width: order.isDelayed ? 2.5 : 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Riga 1: Numero ordine, Orario richiesto, Provenienza, Ritardo
            Row(
              children: [
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.brickBrownDark,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#${order.orderNumber}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  timeRequested,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: order.isDelayed
                        ? AppTheme.delayAlertRed
                        : AppTheme.textDarkBrown,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(ric. $timeReceived)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMutedBrown,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: order.source.badgeColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    order.source.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            if (order.isDelayed) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.delayAlertRed,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'ORDINE IN RITARDO DI ${order.delayMinutes} MINUTI',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // Riga 2: Cliente, Telefono, Ritiro o Consegna + Indirizzo
            Row(
              children: [
                Icon(
                  order.deliveryType == DeliveryType.consegna
                      ? Icons.delivery_dining
                      : Icons.storefront,
                  color: AppTheme.terracottaPrimary,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${order.customerName} ${order.customerPhone.isNotEmpty ? "• ${order.customerPhone}" : ""}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            if (order.deliveryType == DeliveryType.consegna &&
                order.deliveryAddress.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 26),
                child: Text(
                  order.deliveryAddress,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMutedBrown,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            const Divider(height: 18),

            // Prodotti ordinati
            ...order.items.map((item) {
              final mods = <String>[
                ...item.addedIngredients.map((e) => '+ $e'),
                ...item.removedIngredients.map((e) => '- $e'),
                if (item.notes.isNotEmpty) item.notes,
              ];
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${item.quantity}x ${item.name}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '€ ${item.subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (mods.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(
                          mods.join(' | '),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.terracottaPrimary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),

            if (order.notes.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Note: ${order.notes}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.brickBrownDark,
                  ),
                ),
              ),

            const Divider(height: 18),

            // Sezione Rider (solo se Diretto o Just Eat a domicilio)
            if (order.needsInternalRider)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Text(
                      'Rider: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        value: order.assignedRider,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: null,
                            child: Text('Da assegnare'),
                          ),
                          DropdownMenuItem(
                            value: 'rider_1',
                            child: Text('Rider 1'),
                          ),
                          DropdownMenuItem(
                            value: 'rider_2',
                            child: Text('Rider 2'),
                          ),
                        ],
                        onChanged: (val) {
                          SupabaseService.instance.assignRider(order.id, val);
                        },
                      ),
                    ),
                  ],
                ),
              )
            else if (order.source.isExternalCourier)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Consegna gestita da corriere ${order.source.label}',
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textMutedBrown,
                  ),
                ),
              ),

            // Riga finale: Totale + Stato Pagamento + Avanzamento Stato Preparazione
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '€ ${order.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.brickBrownDark,
                      ),
                    ),
                    InkWell(
                      onTap: () => SupabaseService.instance
                          .toggleOrderPaid(order.id, !order.isPaid),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: order.isPaid
                              ? AppTheme.paidGreen
                              : AppTheme.ovenOrangeAccent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${order.paymentMethod.label} • ${order.isPaid ? "PAGATO" : "DA INCASSARE"}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (isOwner)
                  IconButton(
                    tooltip: 'Elimina ordine',
                    icon: const Icon(Icons.delete_outline,
                        color: AppTheme.delayAlertRed),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Eliminare ordine #${order.orderNumber}?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Annulla'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Elimina'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await SupabaseService.instance.deleteOrder(order.id);
                      }
                    },
                  ),
                const SizedBox(width: 6),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: order.status.color,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  onPressed: nextStatus == null
                      ? null
                      : () => SupabaseService.instance
                      .updateOrderStatus(order.id, nextStatus),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        order.status.label.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (nextStatus != null)
                        Text(
                          'Tocca -> ${nextStatus.label}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}