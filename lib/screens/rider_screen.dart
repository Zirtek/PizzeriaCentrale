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
  RiderShiftRecord? _todayShift;
  bool _loadingShift = true;
  RiderRates _rates = const RiderRates();
  Timer? _clockTimer;

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
      SupabaseService.instance.fetchTodayRiderShift(widget.session.role),
      SupabaseService.instance.fetchRiderRates(),
    ]);
    if (mounted) {
      setState(() {
        _todayShift = results[0] as RiderShiftRecord?;
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

    await SupabaseService.instance.registerRiderShift(
      widget.session.role,
      now,
      startingFloat: 0.0,
    );
    await _loadInitialData();
  }

  Future<void> _closeShiftDialog({
    required int activeDeliveriesCount,
    required int completedDeliveriesCount,
    required double cashFromOrders,
    required double cardFromOrders,
    required double onlineFromOrders,
    required double riderEarnings,
  }) async {
    if (activeDeliveriesCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.toStartRed,
          content: Text(
            'Hai ancora $activeDeliveriesCount consegne in corso: completale o rilasciale prima di chiudere il turno.',
          ),
        ),
      );
      return;
    }

    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chiudi Turno e Versa Cassa'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReconciliationRow(
                label: 'Consegne completate',
                value: '$completedDeliveriesCount',
              ),
              _ReconciliationRow(
                label: 'Tuo compenso turno',
                value: '€ ${riderEarnings.toStringAsFixed(2)}',
                valueColor: AppTheme.moneyGreen,
              ),
              const Divider(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.darkGreenTint,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.moneyGreen, width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'CONTANTI DA VERSARE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.moneyGreen,
                        ),
                      ),
                    ),
                    Text(
                      '€ ${cashFromOrders.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.moneyGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _ReconciliationRow(
                label: 'Incassato Carta / POS',
                value: '€ ${cardFromOrders.toStringAsFixed(2)}',
                valueColor: AppTheme.toCompleteYellow,
              ),
              if (onlineFromOrders > 0)
                _ReconciliationRow(
                  label: 'Già pagati online',
                  value: '€ ${onlineFromOrders.toStringAsFixed(2)}',
                ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note chiusura (opzionale)',
                  hintText: 'Es. scontrini POS consegnati al bancone',
                ),
              ),
            ],
          ),
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
            label: const Text('CONFERMA CHIUSURA'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await SupabaseService.instance.closeRiderShift(
      riderRole: widget.session.role,
      date: DateTime.now(),
      startingFloat: 0.0,
      cashCollected: cashFromOrders,
      cardCollected: cardFromOrders,
      onlinePaid: onlineFromOrders,
      deliveriesCount: completedDeliveriesCount,
      riderEarnings: riderEarnings,
      closingNotes: notesController.text,
    );
    await _loadInitialData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Turno chiuso e versamento cassa registrato!'),
      ),
    );
  }

  void _checkReadyTransitions(List<PizzeriaOrder> todayDeliveries) {
    final currentMap = <String, OrderStatus>{
      for (final o in todayDeliveries) o.id: o.status,
    };

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
    final shift = _todayShift;
    if (_loadingShift || shift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Devi prima premere "INIZIA TURNO" in alto.'),
        ),
      );
      return;
    }
    if (shift.isClosed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Il turno di oggi risulta già chiuso.'),
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

    final shift = _todayShift;
    final hasShiftRecord = !_loadingShift && shift != null;
    final isShiftClosed = !_loadingShift && (shift?.isClosed ?? false);
    final canOperateShift = hasShiftRecord && !isShiftClosed;
    final isMuted = ReadyOrderAlertService.instance.isMuted;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.session.displayName,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: isMuted
                ? 'Audio disattivato (tocca per attivare)'
                : 'Prova suono avviso (tieni premuto per silenziare)',
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
                  content: Text('Avviso sonoro "Pronto" attivo'),
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
                        ? 'Suono silenziato (resta la vibrazione)'
                        : 'Suono riattivato',
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Aggiorna',
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

          final activeBannerAlerts = _newlyReadyAlerts.where((alertOrder) {
            return todayDeliveries.any(
                  (live) =>
              live.id == alertOrder.id &&
                  live.assignedRider == null &&
                  live.status == OrderStatus.pronto,
            );
          }).toList();

          final myActiveOrders = todayDeliveries
              .where((o) =>
          o.assignedRider == myRoleDb &&
              o.status != OrderStatus.completato)
              .toList();

          final overviewOrders = todayDeliveries
              .where((o) =>
          o.assignedRider == null &&
              o.status != OrderStatus.completato)
              .toList();

          final readyCount = overviewOrders
              .where((o) => o.status == OrderStatus.pronto)
              .length;

          final myCompletedOrders = todayDeliveries
              .where((o) =>
          o.assignedRider == myRoleDb &&
              o.status == OrderStatus.completato)
              .toList();

          final baseQuota = hasShiftRecord ? _rates.baseFeeForDate(now) : 0.0;
          final deliveriesBonus =
              myCompletedOrders.length * _rates.perDeliveryBonus;
          final todayEarnings = baseQuota + deliveriesBonus;

          final cashFromOrders = myCompletedOrders
              .where((o) =>
          o.isPaid && o.paymentMethod == PaymentMethod.contanti)
              .fold<double>(0.0, (sum, o) => sum + o.totalAmount);

          final cardFromOrders = myCompletedOrders
              .where(
                  (o) => o.isPaid && o.paymentMethod == PaymentMethod.carta)
              .fold<double>(0.0, (sum, o) => sum + o.totalAmount);

          final onlineFromOrders = myCompletedOrders
              .where(
                  (o) => o.isPaid && o.paymentMethod == PaymentMethod.online)
              .fold<double>(0.0, (sum, o) => sum + o.totalAmount);

          final stillToCollect = myActiveOrders
              .where((o) => !o.isPaid)
              .fold<double>(0.0, (sum, o) => sum + o.totalAmount);

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
            children: [
              // Banner allerta ordine pronto (in-app)
              if (activeBannerAlerts.isNotEmpty && !isShiftClosed)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.toCompleteYellow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.notifications_active,
                              color: Colors.black, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              activeBannerAlerts.length == 1
                                  ? 'ORDINE PRONTO!'
                                  : '${activeBannerAlerts.length} ORDINI PRONTI!',
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
                            child: const Icon(Icons.close,
                                color: Colors.black87, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
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
                                      horizontal: 14, vertical: 8),
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

              // Card principale Turno, Guadagno e Cassa
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.cardBorder, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                                hasShiftRecord
                                    ? 'Base € ${baseQuota.toStringAsFixed(2)} + ${myCompletedOrders.length} cons. (€ ${deliveriesBonus.toStringAsFixed(2)})'
                                    : (isBefore1830
                                    ? 'Turni attivi dalle 18:30 alle 22:00'
                                    : 'Avvia il turno per prendere consegne'),
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
                          if (!hasShiftRecord)
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.moneyGreen,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                              ),
                              onPressed: canStartShiftNow ? _startShift : null,
                              child: Text(
                                canStartShiftNow
                                    ? 'INIZIA TURNO'
                                    : (isBefore1830
                                    ? 'DALLE 18:30'
                                    : 'FUORI ORARIO'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900),
                              ),
                            )
                          else if (isShiftClosed)
                            Chip(
                              avatar: const Icon(Icons.lock_clock,
                                  color: Colors.black, size: 17),
                              label: Text(
                                'Chiuso ${DateFormat('HH:mm').format(shift!.closedAt!)}',
                              ),
                              backgroundColor: AppTheme.toCompleteYellow,
                              labelStyle: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            )
                          else
                            const Chip(
                              avatar: Icon(Icons.check_circle,
                                  color: Colors.black, size: 17),
                              label: Text('Turno attivo'),
                              backgroundColor: AppTheme.moneyGreen,
                              labelStyle: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                      ],
                    ),
                    const Divider(height: 20),

                    // Cassa essenziale: Contanti da versare vs Carta/POS
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.darkGreenTint,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppTheme.moneyGreen.withOpacity(0.6)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CONTANTI DA VERSARE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '€ ${cashFromOrders.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.moneyGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.cardBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CARTA / POS',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '€ ${cardFromOrders.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.textWhite,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (stillToCollect > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Da incassare in consegna:',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.toCompleteYellow,
                            ),
                          ),
                          Text(
                            '€ ${stillToCollect.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.toCompleteYellow,
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (canOperateShift) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.toCompleteYellow,
                            side: const BorderSide(
                                color: AppTheme.toCompleteYellow, width: 1.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => _closeShiftDialog(
                            activeDeliveriesCount: myActiveOrders.length,
                            completedDeliveriesCount: myCompletedOrders.length,
                            cashFromOrders: cashFromOrders,
                            cardFromOrders: cardFromOrders,
                            onlineFromOrders: onlineFromOrders,
                            riderEarnings: todayEarnings,
                          ),
                          icon: const Icon(Icons.point_of_sale, size: 19),
                          label: const Text(
                            'CHIUDI TURNO / VERSA CASSA',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (isShiftClosed) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppTheme.darkGreenTint,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.moneyGreen),
                  ),
                  child: Text(
                    'Turno chiuso alle ${DateFormat('HH:mm').format(shift!.closedAt!)} • Contanti: € ${shift.cashCollected.toStringAsFixed(2)} • POS: € ${shift.cardCollected.toStringAsFixed(2)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.moneyGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],

              // Sezione 1: Le tue consegne in corso
              if (myActiveOrders.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(Icons.delivery_dining,
                        size: 20, color: AppTheme.toCompleteYellow),
                    const SizedBox(width: 6),
                    Text(
                      'IN CONSEGNA ORA (${myActiveOrders.length})',
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
                    canClaimDeliveries: canOperateShift,
                    isShiftClosed: isShiftClosed,
                  ),
                ),
              ],

              // Sezione 2: Consegne disponibili / in programma
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.list_alt,
                      size: 19, color: AppTheme.textWhite),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'CONSEGNE DI OGGI (${overviewOrders.length})',
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
                    canClaimDeliveries: canOperateShift,
                    isShiftClosed: isShiftClosed,
                  ),
                ),

              // Sezione 3: Completate oggi
              if (myCompletedOrders.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'COMPLETATE OGGI (${myCompletedOrders.length})',
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
                    canClaimDeliveries: canOperateShift,
                    isShiftClosed: isShiftClosed,
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

class _ReconciliationRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ReconciliationRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppTheme.textWhite,
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderDeliveryCard extends StatefulWidget {
  final PizzeriaOrder order;
  final String currentRiderRole;
  final bool isUnassignedOverview;
  final bool canClaimDeliveries;
  final bool isShiftClosed;

  const _RiderDeliveryCard({
    required this.order,
    required this.currentRiderRole,
    required this.isUnassignedOverview,
    required this.canClaimDeliveries,
    required this.isShiftClosed,
  });

  @override
  State<_RiderDeliveryCard> createState() => _RiderDeliveryCardState();
}

class _RiderDeliveryCardState extends State<_RiderDeliveryCard> {
  bool _isBusy = false;

  bool _isDrinkItem(OrderLineItem item) {
    final cat = item.category.toLowerCase();
    final name = item.name.toLowerCase();
    return cat.contains('bibit') ||
        cat.contains('bevand') ||
        cat.contains('birr') ||
        name.contains('coca') ||
        name.contains('fanta') ||
        name.contains('sprite') ||
        name.contains('acqua') ||
        name.contains('birra') ||
        name.contains('tè') ||
        name.contains('the ');
  }

  Future<void> _takeInCharge() async {
    if (!widget.canClaimDeliveries) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isShiftClosed
                ? 'Il turno di oggi è già stato chiuso.'
                : 'Devi prima premere "INIZIA TURNO" (dalle 18:30 alle 22:00).',
          ),
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
    final canClaim = isOrderReady && widget.canClaimDeliveries;
    final totalPieces =
    order.items.fold<int>(0, (sum, item) => sum + item.quantity);

    final borderColor = order.isDelayed
        ? AppTheme.toStartRed
        : order.status.color.withOpacity(0.8);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: borderColor,
          width: (order.isDelayed || isOrderReady) ? 2.0 : 1.2,
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
                  '#${order.orderNumber}  •  $timeStr',
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
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                    size: 17, color: AppTheme.toCompleteYellow),
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
            if (!widget.isUnassignedOverview && !isCompleted) ...[
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
            if (order.items.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ORDINE ($totalPieces ${totalPieces == 1 ? 'pezzo' : 'pezzi'})',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...order.items.map((item) {
                      final isDrink = _isDrinkItem(item);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item.quantity}x ',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.toCompleteYellow,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: isDrink
                                          ? const Color(0xFF4FC3F7)
                                          : AppTheme.textWhite,
                                    ),
                                  ),
                                ),
                                if (isDrink)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4FC3F7)
                                          .withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: const Color(0xFF4FC3F7)),
                                    ),
                                    child: const Text(
                                      'FRIGO',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF4FC3F7),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (item.addedIngredients.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 22),
                                child: Text(
                                  '+ ${item.addedIngredients.join(', ')}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.moneyGreen,
                                  ),
                                ),
                              ),
                            if (item.removedIngredients.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 22),
                                child: Text(
                                  '- Senza ${item.removedIngredients.join(', ')}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.toStartRed,
                                  ),
                                ),
                              ),
                            if (item.notes.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 22),
                                child: Text(
                                  'Nota: ${item.notes}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: AppTheme.toCompleteYellow,
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
            if (order.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.darkYellowTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Note: ${order.notes}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.toCompleteYellow,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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
                    ? 'INCASSATO: € ${order.totalAmount.toStringAsFixed(2)} (${order.paymentMethod.label})'
                    : 'GIÀ PAGATO (${order.paymentMethod.label}) • NON INCASSARE')
                    : 'DA INCASSARE: € ${order.totalAmount.toStringAsFixed(2)} (${order.paymentMethod.label})',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: order.isPaid
                      ? AppTheme.moneyGreen
                      : AppTheme.toCompleteYellow,
                ),
              ),
            ),
            if (widget.isUnassignedOverview) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
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
                    size: 21,
                  ),
                  label: Text(
                    canClaim
                        ? 'PRENDI IN CARICO'
                        : (isOrderReady
                        ? (widget.isShiftClosed
                        ? 'TURNO CHIUSO'
                        : 'INIZIA TURNO PER PRENDERE')
                        : 'IN PREPARAZIONE'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ] else if (!isCompleted) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _isBusy ? null : _releaseDelivery,
                    child: const Text('Rilascia'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.completedGreen,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: _isBusy ? null : _completeDelivery,
                        icon: const Icon(Icons.check_circle),
                        label: const Text(
                          'CONSEGNATO',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
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