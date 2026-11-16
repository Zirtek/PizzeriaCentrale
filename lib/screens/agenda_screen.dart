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
  nonPagati('Da incassare'),
  consegne('Consegne');

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
  Map<String, String> _riderDisplayNames = {};

  @override
  void initState() {
    super.initState();
    _loadRiderNames();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadRiderNames() async {
    try {
      final profiles = await SupabaseService.instance
          .fetchUserProfiles(includeInactive: true);
      if (!mounted) return;
      setState(() {
        _riderDisplayNames = {
          for (final p in profiles) p.role: p.displayName,
        };
      });
    } catch (_) {}
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
    final now = DateTime.now();
    final isToday = _isSameDay(_selectedDate, now);
    final dateFormatted =
    DateFormat('EEEE d MMMM', 'it_IT').format(_selectedDate);

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
              'Profilo: ${widget.session.displayName}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
        actions: [
          if (widget.session.isOwner)
            IconButton(
              tooltip: 'Incassi, Rider e Listino',
              icon: const Icon(Icons.bar_chart_rounded,
                  size: 28, color: AppTheme.moneyGreen),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OwnerAdminScreen(),
                  ),
                );
                _loadRiderNames();
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
        backgroundColor: AppTheme.moneyGreen,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_circle_outline, size: 26),
        label: const Text(
          'NUOVO ORDINE',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
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
      body: StreamBuilder<List<PizzeriaOrder>>(
        stream: SupabaseService.instance.watchOrders(),
        builder: (context, snapshot) {
          final allOrders = snapshot.data ?? [];
          final allDayOrders = allOrders
              .where((o) => _isSameDay(o.scheduledFor, _selectedDate))
              .toList();

          final delayedCount = allDayOrders.where((o) => o.isDelayed).length;
          final unpaidCount = allDayOrders.where((o) => !o.isPaid).length;
          final deliveriesCount = allDayOrders
              .where((o) => o.deliveryType == DeliveryType.consegna)
              .length;

          final collectedRevenue = allDayOrders
              .where((o) => o.isPaid)
              .fold<double>(0.0, (sum, o) => sum + o.totalAmount);
          final pendingRevenue = allDayOrders
              .where((o) => !o.isPaid)
              .fold<double>(0.0, (sum, o) => sum + o.totalAmount);
          final totalDayRevenue = collectedRevenue + pendingRevenue;

          var visibleOrders = List<PizzeriaOrder>.from(allDayOrders);
          if (_hideCompleted) {
            visibleOrders = visibleOrders
                .where((o) => o.status != OrderStatus.completato)
                .toList();
          }
          if (_activeFilter == AgendaFilter.inRitardo) {
            visibleOrders = visibleOrders.where((o) => o.isDelayed).toList();
          } else if (_activeFilter == AgendaFilter.nonPagati) {
            visibleOrders = visibleOrders.where((o) => !o.isPaid).toList();
          } else if (_activeFilter == AgendaFilter.consegne) {
            visibleOrders = visibleOrders
                .where((o) => o.deliveryType == DeliveryType.consegna)
                .toList();
          }

          visibleOrders.sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

          return Column(
            children: [
              // Barra navigazione data con tasto rapido OGGI
              Container(
                color: AppTheme.surfaceDark,
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 28),
                      color: AppTheme.textWhite,
                      onPressed: () => setState(() {
                        _selectedDate =
                            _selectedDate.subtract(const Duration(days: 1));
                      }),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 17, color: AppTheme.toCompleteYellow),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  dateFormatted.toUpperCase(),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: AppTheme.textWhite,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!isToday)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: ActionChip(
                          label: const Text(
                            'OGGI',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: Colors.black,
                            ),
                          ),
                          backgroundColor: AppTheme.toCompleteYellow,
                          onPressed: () =>
                              setState(() => _selectedDate = DateTime.now()),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 28),
                      color: AppTheme.textWhite,
                      onPressed: () => setState(() {
                        _selectedDate =
                            _selectedDate.add(const Duration(days: 1));
                      }),
                    ),
                  ],
                ),
              ),

              // Riepilogo Incassi Titolare
              if (widget.session.isOwner)
                Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    border: Border(
                      top: BorderSide(color: AppTheme.cardBorder),
                      bottom: BorderSide(color: AppTheme.cardBorder),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _RevenueMetricTile(
                          label: 'INCASSATO',
                          value: '€ ${collectedRevenue.toStringAsFixed(2)}',
                          valueColor: AppTheme.moneyGreen,
                        ),
                      ),
                      Container(
                          width: 1, height: 28, color: AppTheme.cardBorder),
                      Expanded(
                        child: _RevenueMetricTile(
                          label: 'IN SOSPESO',
                          value: '€ ${pendingRevenue.toStringAsFixed(2)}',
                          valueColor: pendingRevenue > 0
                              ? AppTheme.toCompleteYellow
                              : AppTheme.textMuted,
                        ),
                      ),
                      Container(
                          width: 1, height: 28, color: AppTheme.cardBorder),
                      Expanded(
                        child: _RevenueMetricTile(
                          label: 'TOTALE (${allDayOrders.length})',
                          value: '€ ${totalDayRevenue.toStringAsFixed(2)}',
                          valueColor: AppTheme.moneyGreen,
                        ),
                      ),
                    ],
                  ),
                ),

              // Barra Filtri rapidi
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    ...AgendaFilter.values.map((filter) {
                      final selected = _activeFilter == filter;
                      final count = switch (filter) {
                        AgendaFilter.tutti => allDayOrders.length,
                        AgendaFilter.inRitardo => delayedCount,
                        AgendaFilter.nonPagati => unpaidCount,
                        AgendaFilter.consegne => deliveriesCount,
                      };
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${filter.label} ($count)'),
                          selected: selected,
                          selectedColor: AppTheme.toCompleteYellow,
                          labelStyle: TextStyle(
                            color: selected ? Colors.black : AppTheme.textWhite,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          onSelected: (_) =>
                              setState(() => _activeFilter = filter),
                        ),
                      );
                    }),
                    FilterChip(
                      label: const Text('Nascondi completati'),
                      selected: _hideCompleted,
                      selectedColor: AppTheme.completedGreen,
                      checkmarkColor: Colors.black,
                      labelStyle: TextStyle(
                        color:
                        _hideCompleted ? Colors.black : AppTheme.textWhite,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      onSelected: (val) => setState(() => _hideCompleted = val),
                    ),
                  ],
                ),
              ),

              // Lista ordini in tempo reale
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                            'Errore caricamento ordini: ${snapshot.error}'),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (visibleOrders.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.receipt_long_outlined,
                                size: 48, color: AppTheme.textMuted),
                            const SizedBox(height: 8),
                            const Text(
                              'Nessun ordine presente per i filtri selezionati.',
                              style: TextStyle(
                                fontSize: 15,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            if (_activeFilter != AgendaFilter.tutti ||
                                _hideCompleted) ...[
                              const SizedBox(height: 10),
                              OutlinedButton(
                                onPressed: () => setState(() {
                                  _activeFilter = AgendaFilter.tutti;
                                  _hideCompleted = false;
                                }),
                                child: const Text('Mostra tutti gli ordini'),
                              ),
                            ],
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 92),
                      itemCount: visibleOrders.length,
                      itemBuilder: (context, index) {
                        final order = visibleOrders[index];
                        final canModify = widget.session.isOwner ||
                            (widget.session.isDipendente &&
                                order.status != OrderStatus.completato);
                        final assignedName = order.assignedRider == null
                            ? null
                            : (_riderDisplayNames[order.assignedRider!] ??
                            UserRole.defaultLabel(order.assignedRider!));

                        return _OrderAgendaCard(
                          order: order,
                          assignedRiderName: assignedName,
                          canEditOrder: canModify,
                          canDeleteOrder: canModify,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RevenueMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _RevenueMetricTile({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppTheme.textMuted,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _OrderAgendaCard extends StatelessWidget {
  final PizzeriaOrder order;
  final String? assignedRiderName;
  final bool canEditOrder;
  final bool canDeleteOrder;

  const _OrderAgendaCard({
    required this.order,
    required this.assignedRiderName,
    required this.canEditOrder,
    required this.canDeleteOrder,
  });

  List<OrderStatus> _workflowSteps() {
    if (order.deliveryType == DeliveryType.ritiro ||
        order.source == OrderSource.banco ||
        order.source.isExternalCourier) {
      return const [
        OrderStatus.nuovoOrdine,
        OrderStatus.pronto,
        OrderStatus.completato,
      ];
    }
    return const [
      OrderStatus.nuovoOrdine,
      OrderStatus.pronto,
      OrderStatus.inConsegna,
      OrderStatus.completato,
    ];
  }

  Future<void> _handleCompleteOrder(BuildContext context) async {
    if (order.isPaid) {
      await SupabaseService.instance
          .updateOrderStatus(order.id, OrderStatus.completato);
      return;
    }

    PaymentMethod selectedMethod = order.paymentMethod;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Completa e Incassa #${order.orderNumber}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Importo incassato: € ${order.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.moneyGreen,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Metodo di pagamento:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<PaymentMethod>(
                value: selectedMethod,
                items: PaymentMethod.values
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDlgState(() => selectedMethod = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.moneyGreen,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check_circle),
              label: const Text('Conferma Incasso'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await SupabaseService.instance.updateOrderStatus(
        order.id,
        OrderStatus.completato,
        paymentMethod: selectedMethod,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeRequested = DateFormat('HH:mm').format(order.scheduledFor);
    final timeReceived = DateFormat('HH:mm').format(order.createdAt);
    final nextStatus =
    order.status.nextStatus(order.deliveryType, order.source);
    final steps = _workflowSteps();
    final currentStepIdx = steps.indexOf(order.status);
    final isWaitingForRider = order.needsInternalRider &&
        order.status == OrderStatus.pronto &&
        order.assignedRider == null;

    final borderColor = order.isDelayed
        ? AppTheme.toStartRed
        : order.status.color.withOpacity(0.75);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: borderColor,
          width: order.isDelayed ? 2.5 : 1.6,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Riga 1: Numero ordine, Orario, Provenienza, Menu rapido stato
            Row(
              children: [
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Text(
                    '#${order.orderNumber}',
                    style: const TextStyle(
                      color: AppTheme.textWhite,
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
                        ? AppTheme.toStartRed
                        : AppTheme.textWhite,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(ric. $timeReceived)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
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
                    style: TextStyle(
                      color: order.source.badgeTextColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                PopupMenuButton<OrderStatus>(
                  tooltip: 'Scegli stato direttamente',
                  icon:
                  const Icon(Icons.more_vert, color: AppTheme.textWhite),
                  onSelected: (chosen) async {
                    if (chosen == OrderStatus.completato) {
                      await _handleCompleteOrder(context);
                    } else {
                      await SupabaseService.instance
                          .updateOrderStatus(order.id, chosen);
                    }
                  },
                  itemBuilder: (_) => steps
                      .map(
                        (s) => PopupMenuItem(
                      value: s,
                      child: Row(
                        children: [
                          Icon(
                            s == order.status
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: s.color,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            s.label,
                            style: TextStyle(
                              fontWeight: s == order.status
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      .toList(),
                ),
              ],
            ),

            // Barra visiva avanzamento (Rosso -> Giallo -> Verde)
            const SizedBox(height: 8),
            Row(
              children: List.generate(steps.length, (i) {
                final active = i <= currentStepIdx;
                return Expanded(
                  child: Container(
                    height: 5,
                    margin:
                    EdgeInsets.only(right: i == steps.length - 1 ? 0 : 4),
                    decoration: BoxDecoration(
                      color: active ? order.status.color : AppTheme.cardBorder,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
            ),

            if (order.isDelayed) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.toStartRed,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'IN RITARDO DI ${order.delayMinutes} MINUTI',
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

            // Riga 2: Tipo servizio, Cliente, Telefono, Indirizzo
            Row(
              children: [
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        order.deliveryType == DeliveryType.consegna
                            ? Icons.delivery_dining
                            : Icons.storefront,
                        color: AppTheme.toCompleteYellow,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        order.deliveryType == DeliveryType.consegna
                            ? 'CONSEGNA'
                            : 'RITIRO',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textWhite,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${order.customerName}${order.customerPhone.isNotEmpty ? " • ${order.customerPhone}" : ""}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppTheme.textWhite,
                    ),
                  ),
                ),
              ],
            ),
            if (order.deliveryType == DeliveryType.consegna &&
                order.deliveryAddress.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5, left: 2),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 16, color: AppTheme.toCompleteYellow),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.deliveryAddress,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const Divider(height: 16),

            // Prodotti ordinati
            ...order.items.map((item) {
              final mods = <String>[
                ...item.addedIngredients.map((e) => '+ $e'),
                ...item.removedIngredients.map((e) => '- $e'),
                if (item.notes.isNotEmpty) item.notes,
              ];
              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: AppTheme.cardBorder),
                          ),
                          child: Text(
                            '${item.quantity}x',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: AppTheme.toCompleteYellow,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textWhite,
                            ),
                          ),
                        ),
                        Text(
                          '€ ${item.subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.moneyGreen,
                          ),
                        ),
                      ],
                    ),
                    if (mods.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 34, top: 2),
                        child: Text(
                          mods.join(' | '),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.toCompleteYellow,
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
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.darkYellowTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.toCompleteYellow.withOpacity(0.5)),
                ),
                child: Text(
                  'Note: ${order.notes}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.toCompleteYellow,
                  ),
                ),
              ),

            const Divider(height: 16),

            // Stato presa in carico Rider
            if (order.needsInternalRider)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        order.assignedRider != null
                            ? Icons.sports_motorsports
                            : (order.status == OrderStatus.pronto
                            ? Icons.notifications_active_outlined
                            : Icons.visibility_outlined),
                        size: 18,
                        color: order.assignedRider != null
                            ? AppTheme.toCompleteYellow
                            : (order.status == OrderStatus.pronto
                            ? AppTheme.toCompleteYellow
                            : AppTheme.textMuted),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          order.assignedRider != null
                              ? 'Presa in carico da: ${assignedRiderName ?? order.assignedRider}'
                              : (order.status == OrderStatus.pronto
                              ? 'Pronto • Il rider può ora prenderlo in carico'
                              : 'Visibile ai rider • Segna "Pronto" per sbloccarlo'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: order.assignedRider != null
                                ? AppTheme.toCompleteYellow
                                : (order.status == OrderStatus.pronto
                                ? AppTheme.toCompleteYellow
                                : AppTheme.textMuted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (order.source.isExternalCourier)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Consegna gestita da corriere ${order.source.label}',
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),

            // Riga finale: Totale + Stato Pagamento + Modifica + Elimina + Stato
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '€ ${order.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.moneyGreen,
                      ),
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: () => SupabaseService.instance
                          .toggleOrderPaid(order.id, !order.isPaid),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: order.isPaid
                              ? AppTheme.moneyGreen
                              : AppTheme.toCompleteYellow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              order.isPaid
                                  ? Icons.check_circle
                                  : Icons.payments_outlined,
                              size: 13,
                              color: Colors.black,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${order.paymentMethod.label} • ${order.isPaid ? "PAGATO" : "DA INCASSARE"}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (canEditOrder)
                  IconButton(
                    tooltip: 'Modifica ordine',
                    icon: const Icon(Icons.edit_outlined,
                        color: AppTheme.toCompleteYellow),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NewOrderScreen(
                            initialDate: order.scheduledFor,
                            existingOrder: order,
                          ),
                        ),
                      );
                    },
                  ),
                if (canDeleteOrder)
                  IconButton(
                    tooltip: 'Annulla ed elimina ordine',
                    icon: const Icon(Icons.delete_outline,
                        color: AppTheme.toStartRed),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(
                              'Annullare ed eliminare ordine #${order.orderNumber}?'),
                          content: const Text(
                            'L\'ordine verrà rimosso definitivamente dall\'agenda.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Indietro'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.toStartRed,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Elimina ordine'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await SupabaseService.instance.deleteOrder(order.id);
                      }
                    },
                  ),
                const SizedBox(width: 4),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: order.status.color,
                    foregroundColor: order.status.textColor,
                    disabledBackgroundColor: order.status.color,
                    disabledForegroundColor: order.status.textColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  onPressed: nextStatus == null
                      ? null
                      : () async {
                    if (nextStatus == OrderStatus.completato) {
                      await _handleCompleteOrder(context);
                    } else {
                      await SupabaseService.instance
                          .updateOrderStatus(order.id, nextStatus);
                    }
                  },
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
                          nextStatus == OrderStatus.pronto
                              ? 'Segna Pronto ->'
                              : 'Completa ->',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: order.status.textColor.withOpacity(0.8),
                          ),
                        )
                      else if (isWaitingForRider)
                        Text(
                          'In attesa rider',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: order.status.textColor.withOpacity(0.8),
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