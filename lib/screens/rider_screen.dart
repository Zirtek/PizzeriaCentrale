import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/ready_order_alert_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class RiderScreen extends StatefulWidget {
  final AppUserSession session;
  final VoidCallback onLogout;

  const RiderScreen({
    super.key,
    required this.session,
    required this.onLogout,
  });

  @override
  State<RiderScreen> createState() => _RiderScreenState();
}

class _RiderScreenState extends State<RiderScreen> {
  bool _shiftRegisteredToday = false;
  bool _loadingShift = true;
  RiderRates _rates = const RiderRates();
  Timer? _clockTimer;

  // Traccia gli stati noti degli ordini per rilevare in tempo reale il passaggio a "Pronto"
  Map<String, OrderStatus>? _knownOrderStatuses;
  List<PizzeriaOrder> _newlyReadyAlerts = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  bool _isBeforeShiftStart(DateTime dt) {
    final start = DateTime(dt.year, dt.month, dt.day, 18, 30);
    return dt.isBefore(start);
  }

  bool _canStartShiftAt(DateTime dt) {
    final start = DateTime(dt.year, dt.month, dt.day, 18, 30);
    final end = DateTime(dt.year, dt.month, dt.day, 22, 0);
    return !dt.isBefore(start) && dt.isBefore(end);
  }

  Future<void> _loadInitialData() async {
    final results = await Future.wait([
      SupabaseService.instance.hasRiderShiftToday(widget.session.role),
      SupabaseService.instance.fetchRiderRates(),
    ]);
    if (mounted) {
      setState(() {
        _shiftRegisteredToday = results[0] as bool;
        _rates = results[1] as RiderRates;
        _loadingShift = false;
      });
    }
  }

  Future<void> _startShift() async {
    final now = DateTime.now();
    if (!_canStartShiftAt(now)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
            Text('Puoi iniziare il turno solo dalle 18:30 alle 22:00.'),
          ),
        );
      }
      return;
    }

    await SupabaseService.instance.registerRiderShift(widget.session.role, now);
    await _loadInitialData();
  }

  void _checkReadyTransitions(List<PizzeriaOrder> todayDeliveries) {
    final currentMap = <String, OrderStatus>{
      for (final o in todayDeliveries) o.id: o.status,
    };

    // Al primo caricamento memorizza lo stato iniziale senza suonare per ordini già pronti
    if (_knownOrderStatuses == null) {
      _knownOrderStatuses = currentMap;
      return;
    }

    final becameReady = <PizzeriaOrder>[];
    for (final order in todayDeliveries) {
      if (order.assignedRider == null && order.status == OrderStatus.pronto) {
        final previousStatus = _knownOrderStatuses![order.id];
        if (previousStatus != OrderStatus.pronto) {
          becameReady.add(order);
        }
      }
    }

    _knownOrderStatuses = currentMap;

    if (becameReady.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ReadyOrderAlertService.instance.triggerOrderReadyAlert();
        setState(() {
          final existingIds = _newlyReadyAlerts.map((e) => e.id).toSet();
          for (final o in becameReady) {
            if (!existingIds.contains(o.id)) {
              _newlyReadyAlerts.insert(0, o);
            }
          }
        });
      });
    }
  }

  Future<void> _quickClaimFromBanner(PizzeriaOrder order) async {
    if (_loadingShift || !_shiftRegisteredToday) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Devi prima premere "INIZIA TURNO" in alto.'),
        ),
      );
      return;
    }

    final claimed = await SupabaseService.instance.claimDelivery(
      order.id,
      widget.session.role,
    );
    if (!mounted) return;
    setState(() {
      _newlyReadyAlerts.removeWhere((o) => o.id == order.id);
    });
    if (!claimed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Consegna già presa in carico da un altro rider.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final myRoleDb = widget.session.role;
    final isBefore1830 = _isBeforeShiftStart(now);
    final canStartShiftNow = _canStartShiftAt(now);
    final hasActiveShift = !_loadingShift && _shiftRegisteredToday;
    final isMuted = ReadyOrderAlertService.instance.isMuted;

    return Scaffold(
      appBar: AppBar(
        title: Text('Area ${widget.session.displayName}'),
        actions: [
          IconButton(
            tooltip: isMuted
                ? 'Audio disattivato (tocca per attivare e provare)'
                : 'Prova suono avviso',
            icon: Icon(
              isMuted ? Icons.volume_off : Icons.volume_up,
              color: isMuted ? AppTheme.toStartRed : AppTheme.toCompleteYellow,
            ),
            onPressed: () async {
              if (isMuted) {
                setState(() => ReadyOrderAlertService.instance.setMuted(false));
              }
              await ReadyOrderAlertService.instance.triggerOrderReadyAlert();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  duration: Duration(seconds: 2),
                  content: Text('Avviso sonoro "Pronto" attivo (tieni alto il volume)'),
                ),
              );
            },
            onLongPress: () {
              setState(() {
                ReadyOrderAlertService.instance.setMuted(!isMuted);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 2),
                  content: Text(
                    !isMuted
                        ? 'Suono avvisi silenziato (resta attiva la vibrazione)'
                        : 'Suono avvisi riattivato',
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Aggiorna tariffe e turno',
            icon: const Icon(Icons.refresh),
            onPressed: _loadInitialData,
          ),
          IconButton(
            tooltip: 'Esci',
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: StreamBuilder<List<PizzeriaOrder>>(
        stream: SupabaseService.instance.watchOrders(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final todayDeliveries = snapshot.data!.where((o) {
            final sameDay = o.scheduledFor.year == now.year &&
                o.scheduledFor.month == now.month &&
                o.scheduledFor.day == now.day;
            return sameDay && o.needsInternalRider;
          }).toList()
            ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

          _checkReadyTransitions(todayDeliveries);

          // Mantieni nel banner solo gli ordini ancora effettivamente PRONTI e non assegnati
          final activeBannerAlerts = _newlyReadyAlerts.where((alertOrder) {
            return todayDeliveries.any(
                  (live) =>
              live.id == alertOrder.id &&
                  live.assignedRider == null &&
                  live.status == OrderStatus.pronto,
            );
          }).toList();

          // 1. Consegne prese in carico da QUESTO rider e ancora in corso
          final myActiveOrders = todayDeliveries
              .where((o) =>
          o.assignedRider == myRoleDb &&
              o.status != OrderStatus.completato)
              .toList();

          // 2. Tutte le consegne del giorno non ancora prese in carico
          final overviewOrders = todayDeliveries
              .where((o) =>
          o.assignedRider == null &&
              o.status != OrderStatus.completato)
              .toList();

          final readyCount = overviewOrders
              .where((o) => o.status == OrderStatus.pronto)
              .length;

          // 3. Consegne completate da QUESTO rider oggi
          final myCompletedOrders = todayDeliveries
              .where((o) =>
          o.assignedRider == myRoleDb &&
              o.status == OrderStatus.completato)
              .toList();

          final baseQuota =
          _shiftRegisteredToday ? _rates.baseFeeForDate(now) : 0.0;
          final deliveriesBonus =
              myCompletedOrders.length * _rates.perDeliveryBonus;
          final todayEarnings = baseQuota + deliveriesBonus;

          final collectedFromDeliveries = myCompletedOrders
              .where((o) =>
          o.isPaid && o.paymentMethod != PaymentMethod.online)
              .fold<double>(0.0, (sum, o) => sum + o.totalAmount);

          final stillToCollect = myActiveOrders
              .where((o) => !o.isPaid)
              .fold<double>(0.0, (sum, o) => sum + o.totalAmount);

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
            children: [
              // Banner di allerta immediata quando uno o più ordini diventano PRONTI
              if (activeBannerAlerts.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.toCompleteYellow,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.toCompleteYellow.withOpacity(0.35),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.notifications_active,
                              color: Colors.black, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              activeBannerAlerts.length == 1
                                  ? 'ORDINE PRONTO PER LA CONSEGNA!'
                                  : '${activeBannerAlerts.length} ORDINI PRONTI PER LA CONSEGNA!',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () =>
                                setState(() => _newlyReadyAlerts.clear()),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.close,
                                  color: Colors.black87, size: 20),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...activeBannerAlerts.map((o) {
                        final t = DateFormat('HH:mm').format(o.scheduledFor);
                        return Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.88),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '#${o.orderNumber} ($t) • ${o.customerName}',
                                      style: const TextStyle(
                                        color: AppTheme.toCompleteYellow,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (o.deliveryAddress.isNotEmpty)
                                      Text(
                                        o.deliveryAddress,
                                        style: const TextStyle(
                                          color: AppTheme.textWhite,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.moneyGreen,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                onPressed: () => _quickClaimFromBanner(o),
                                child: const Text(
                                  'PRENDI',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],

              // Riepilogo Compenso Personale + Cassa Consegne
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.cardBorder, width: 1.5),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'IL TUO GUADAGNO OGGI',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              Text(
                                '€ ${todayEarnings.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.moneyGreen,
                                ),
                              ),
                              Text(
                                'Turno: € ${baseQuota.toStringAsFixed(2)} + ${myCompletedOrders.length} cons. (€ ${deliveriesBonus.toStringAsFixed(2)})',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!_loadingShift)
                          _shiftRegisteredToday
                              ? const Chip(
                            avatar: Icon(Icons.check_circle,
                                color: Colors.black, size: 18),
                            label: Text('Turno attivo'),
                            backgroundColor: AppTheme.moneyGreen,
                            labelStyle: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                              : ElevatedButton(
                            onPressed:
                            canStartShiftNow ? _startShift : null,
                            child: Text(
                              canStartShiftNow
                                  ? 'INIZIA TURNO'
                                  : (isBefore1830
                                  ? 'DALLE 18:30'
                                  : 'TURNO CHIUSO'),
                            ),
                          ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'INCASSATI (DA VERSARE)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              Text(
                                '€ ${collectedFromDeliveries.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.moneyGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'IN CONSEGNA DA INCASSARE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              Text(
                                '€ ${stillToCollect.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.toCompleteYellow,
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

              // Avviso se il turno non è stato ancora avviato
              if (!_loadingShift && !_shiftRegisteredToday) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.darkYellowTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.toCompleteYellow),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isBefore1830 ? Icons.schedule : Icons.info_outline,
                        color: AppTheme.toCompleteYellow,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isBefore1830
                              ? 'Il turno può essere iniziato dalle 18:30 alle 22:00.'
                              : (canStartShiftNow
                              ? 'Premi "INIZIA TURNO" in alto per abilitare la presa in carico delle consegne.'
                              : 'Fascia turno terminata (18:30 - 22:00).'),
                          style: const TextStyle(
                            color: AppTheme.toCompleteYellow,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // SEZIONE 1: Consegne prese in carico da me in questo momento
              if (myActiveOrders.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.delivery_dining,
                        size: 20, color: AppTheme.toCompleteYellow),
                    const SizedBox(width: 6),
                    Text(
                      'LE TUE CONSEGNE IN CORSO (${myActiveOrders.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.toCompleteYellow,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...myActiveOrders.map(
                      (order) => _RiderDeliveryCard(
                    order: order,
                    currentRiderRole: myRoleDb,
                    isUnassignedOverview: false,
                    hasStartedShift: hasActiveShift,
                  ),
                ),
              ],

              // SEZIONE 2: Panoramica completa delle consegne da fare oggi
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.list_alt,
                      size: 20, color: AppTheme.textWhite),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'CONSEGNE DA FARE OGGI (${overviewOrders.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textWhite,
                      ),
                    ),
                  ),
                  if (readyCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.toCompleteYellow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$readyCount PRONTE',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (overviewOrders.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: const Center(
                    child: Text(
                      'Nessuna consegna in programma al momento.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                )
              else
                ...overviewOrders.map(
                      (order) => _RiderDeliveryCard(
                    order: order,
                    currentRiderRole: myRoleDb,
                    isUnassignedOverview: true,
                    hasStartedShift: hasActiveShift,
                  ),
                ),

              // SEZIONE 3: Consegne completate oggi
              if (myCompletedOrders.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'COMPLETATE DA TE OGGI (${myCompletedOrders.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.completedGreen,
                  ),
                ),
                const SizedBox(height: 8),
                ...myCompletedOrders.map(
                      (order) => _RiderDeliveryCard(
                    order: order,
                    currentRiderRole: myRoleDb,
                    isUnassignedOverview: false,
                    hasStartedShift: hasActiveShift,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RiderDeliveryCard extends StatefulWidget {
  final PizzeriaOrder order;
  final String currentRiderRole;
  final bool isUnassignedOverview;
  final bool hasStartedShift;

  const _RiderDeliveryCard({
    required this.order,
    required this.currentRiderRole,
    required this.isUnassignedOverview,
    required this.hasStartedShift,
  });

  @override
  State<_RiderDeliveryCard> createState() => _RiderDeliveryCardState();
}

class _RiderDeliveryCardState extends State<_RiderDeliveryCard> {
  bool _isBusy = false;

  Future<void> _takeInCharge() async {
    if (!widget.hasStartedShift) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Devi prima premere "INIZIA TURNO" (dalle 18:30 alle 22:00).'),
        ),
      );
      return;
    }

    setState(() => _isBusy = true);
    try {
      final claimed = await SupabaseService.instance.claimDelivery(
        widget.order.id,
        widget.currentRiderRole,
      );
      if (!mounted) return;
      if (!claimed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Consegna non ancora pronta o già presa da un altro rider.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _releaseDelivery() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rilasciare consegna #${widget.order.orderNumber}?'),
        content: const Text(
          'La consegna tornerà tra quelle pronte disponibili.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.toCompleteYellow,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rilascia'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isBusy = true);
    try {
      await SupabaseService.instance.releaseDelivery(widget.order.id);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _completeDelivery() async {
    final order = widget.order;
    PaymentMethod selectedMethod = order.paymentMethod;

    if (!order.isPaid) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDlgState) => AlertDialog(
            title: Text('Consegna #${order.orderNumber}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hai incassato € ${order.totalAmount.toStringAsFixed(2)}?',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.moneyGreen,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PaymentMethod>(
                  value: selectedMethod,
                  decoration: const InputDecoration(
                    labelText: 'Metodo incasso',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: PaymentMethod.contanti,
                      child: Text('Contanti'),
                    ),
                    DropdownMenuItem(
                      value: PaymentMethod.carta,
                      child: Text('Carta / POS'),
                    ),
                  ],
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
                label: const Text('SÌ, INCASSATO'),
              ),
            ],
          ),
        ),
      );

      if (confirmed != true) return;
    }

    setState(() => _isBusy = true);
    try {
      await SupabaseService.instance.updateOrderStatus(
        order.id,
        OrderStatus.completato,
        paymentMethod: selectedMethod,
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final timeStr = DateFormat('HH:mm').format(order.scheduledFor);
    final isCompleted = order.status == OrderStatus.completato;
    final isOrderReady =
        widget.isUnassignedOverview && order.status == OrderStatus.pronto;
    final canClaim = isOrderReady && widget.hasStartedShift;

    final borderColor = order.isDelayed
        ? AppTheme.toStartRed
        : order.status.color.withOpacity(0.85);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: borderColor,
          width: (order.isDelayed || isOrderReady) ? 2.2 : 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '#${order.orderNumber}  •  Ore $timeStr',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: order.isDelayed
                        ? AppTheme.toStartRed
                        : AppTheme.textWhite,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: order.status.color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    order.status.label.toUpperCase(),
                    style: TextStyle(
                      color: order.status.textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              order.customerName,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.textWhite,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on,
                    size: 18, color: AppTheme.toCompleteYellow),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    order.deliveryAddress,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),

            if (!widget.isUnassignedOverview) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (order.deliveryAddress.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final encoded =
                          Uri.encodeComponent(order.deliveryAddress);
                          launchUrl(
                            Uri.parse(
                                'https://www.google.com/maps/search/?api=1&query=$encoded'),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('NAVIGA'),
                      ),
                    ),
                  if (order.deliveryAddress.isNotEmpty &&
                      order.customerPhone.isNotEmpty)
                    const SizedBox(width: 8),
                  if (order.customerPhone.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final cleanPhone =
                          order.customerPhone.replaceAll(RegExp(r'\s+'), '');
                          launchUrl(Uri.parse('tel:$cleanPhone'));
                        },
                        icon: const Icon(Icons.phone,
                            size: 18, color: AppTheme.moneyGreen),
                        label: const Text('CHIAMA'),
                      ),
                    ),
                ],
              ),
            ],

            if (order.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.darkYellowTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.toCompleteYellow.withOpacity(0.5)),
                ),
                child: Text(
                  'Indicazioni: ${order.notes}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.toCompleteYellow,
                  ),
                ),
              ),
            ],
            const Divider(height: 18),

            // Box importo (Verde se pagato/incassato, Giallo se da incassare)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: order.isPaid
                    ? AppTheme.darkGreenTint
                    : AppTheme.darkYellowTint,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: order.isPaid
                      ? AppTheme.moneyGreen
                      : AppTheme.toCompleteYellow,
                ),
              ),
              child: Text(
                order.isPaid
                    ? (isCompleted
                    ? 'INCASSATO / PAGATO: € ${order.totalAmount.toStringAsFixed(2)} (${order.paymentMethod.label})'
                    : 'GIÀ PAGATO (${order.paymentMethod.label}) • NON CHIEDERE SOLDI')
                    : 'DA INCASSARE: € ${order.totalAmount.toStringAsFixed(2)} (${order.paymentMethod.label})',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: order.isPaid
                      ? AppTheme.moneyGreen
                      : AppTheme.toCompleteYellow,
                ),
              ),
            ),

            // Attivo solo se lo stato è PRONTO E il rider ha iniziato il turno
            if (widget.isUnassignedOverview) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canClaim
                        ? AppTheme.toCompleteYellow
                        : AppTheme.surfaceElevated,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: isOrderReady
                        ? AppTheme.darkYellowTint
                        : AppTheme.darkRedTint,
                    disabledForegroundColor: isOrderReady
                        ? AppTheme.toCompleteYellow
                        : AppTheme.toStartRed,
                  ),
                  onPressed: (!canClaim || _isBusy) ? null : _takeInCharge,
                  icon: _isBusy
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.black,
                    ),
                  )
                      : Icon(
                    canClaim
                        ? Icons.delivery_dining
                        : (isOrderReady
                        ? Icons.lock_outline
                        : Icons.schedule),
                    size: 22,
                  ),
                  label: Text(
                    canClaim
                        ? 'PRENDI IN CARICO'
                        : (isOrderReady
                        ? 'INIZIA TURNO PER PRENDERE IN CARICO'
                        : 'NUOVO ORDINE • ATTENDI "PRONTO"'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ] else if (!isCompleted) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _isBusy ? null : _releaseDelivery,
                    child: const Text('Rilascia'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.completedGreen,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: _isBusy ? null : _completeDelivery,
                        icon: const Icon(Icons.check_circle),
                        label: const Text('CONSEGNATO'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}