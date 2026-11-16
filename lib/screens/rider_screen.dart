import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
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

  @override
  void initState() {
    super.initState();
    _checkTodayShift();
  }

  Future<void> _checkTodayShift() async {
    final hasShift = await SupabaseService.instance
        .hasRiderShiftToday(widget.session.role.dbValue);
    if (mounted) {
      setState(() {
        _shiftRegisteredToday = hasShift;
        _loadingShift = false;
      });
    }
  }

  Future<void> _startShift() async {
    await SupabaseService.instance
        .registerRiderShift(widget.session.role.dbValue, DateTime.now());
    await _checkTodayShift();
  }

  double _todayBaseFee() {
    final wd = DateTime.now().weekday;
    return wd == DateTime.saturday ? 20.0 : 15.0;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final myRoleDb = widget.session.role.dbValue;
    final hasActiveShift = !_loadingShift && _shiftRegisteredToday;

    return Scaffold(
      appBar: AppBar(
        title: Text('Area ${widget.session.displayName}'),
        actions: [
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
            final sameDay = o.scheduledFor.year == today.year &&
                o.scheduledFor.month == today.month &&
                o.scheduledFor.day == today.day;
            return sameDay && o.needsInternalRider;
          }).toList()
            ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

          // 1. Consegne prese in carico da QUESTO rider e ancora in corso
          final myActiveOrders = todayDeliveries
              .where((o) =>
          o.assignedRider == myRoleDb &&
              o.status != OrderStatus.completato)
              .toList();

          // 2. Tutte le consegne del giorno non ancora prese in carico (sia NUOVO ORDINE che PRONTO)
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

          final baseQuota = _shiftRegisteredToday ? _todayBaseFee() : 0.0;
          final todayEarnings = baseQuota + (myCompletedOrders.length * 2.0);

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
              // Riepilogo Compenso Personale + Cassa Consegne (Conti soldi in verde)
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
                        Column(
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
                              'Turno: € ${baseQuota.toStringAsFixed(0)} + ${myCompletedOrders.length} cons. (€ ${myCompletedOrders.length * 2})',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
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
                            onPressed: _startShift,
                            child: const Text('INIZIA TURNO'),
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
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: AppTheme.toCompleteYellow, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Premi "INIZIA TURNO" in alto per abilitare la presa in carico delle consegne.',
                          style: TextStyle(
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

              // SEZIONE 1: Consegne prese in carico da me in questo momento (Giallo: da completare)
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

              // SEZIONE 3: Consegne completate oggi (Verde)
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
          content: Text('Devi prima premere "INIZIA TURNO" in alto.'),
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
                'Consegna non ancora pronta o già presa dall\'altro rider.'),
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