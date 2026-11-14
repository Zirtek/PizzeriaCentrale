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
    return (wd == DateTime.saturday || wd == DateTime.sunday) ? 18.0 : 15.0;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();

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

          // Il rider vede ESCLUSIVAMENTE i propri ordini della giornata
          final myTodayOrders = snapshot.data!.where((o) {
            final sameDay = o.scheduledFor.year == today.year &&
                o.scheduledFor.month == today.month &&
                o.scheduledFor.day == today.day;
            return sameDay &&
                o.assignedRider == widget.session.role.dbValue &&
                o.source.usesInternalRiders;
          }).toList()
            ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

          final completedDeliveries = myTodayOrders
              .where((o) => o.status == OrderStatus.completato)
              .length;

          final baseQuota = _shiftRegisteredToday ? _todayBaseFee() : 0.0;
          final todayEarnings = baseQuota + (completedDeliveries * 2.0);

          return Column(
            children: [
              // Riepilogo turno e guadagno giornaliero personale
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.warmSurface,
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
                              'GUADAGNO DI OGGI',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textMutedBrown,
                              ),
                            ),
                            Text(
                              '€ ${todayEarnings.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.terracottaPrimary,
                              ),
                            ),
                            Text(
                              'Quota turno: € ${baseQuota.toStringAsFixed(0)} + $completedDeliveries consegne (€ ${completedDeliveries * 2})',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        if (!_loadingShift)
                          _shiftRegisteredToday
                              ? Chip(
                            avatar: const Icon(Icons.check_circle,
                                color: Colors.white, size: 18),
                            label: const Text('Turno attivo'),
                            backgroundColor: AppTheme.paidGreen,
                            labelStyle:
                            const TextStyle(color: Colors.white),
                          )
                              : ElevatedButton(
                            onPressed: _startShift,
                            child: const Text('INIZIA TURNO'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: myTodayOrders.isEmpty
                    ? const Center(
                  child: Text(
                    'Nessuna consegna assegnata a te al momento.',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.textMutedBrown,
                    ),
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: myTodayOrders.length,
                  itemBuilder: (context, index) {
                    final order = myTodayOrders[index];
                    return _RiderDeliveryCard(order: order);
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

class _RiderDeliveryCard extends StatelessWidget {
  final PizzeriaOrder order;

  const _RiderDeliveryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(order.scheduledFor);
    final isCompleted = order.status == OrderStatus.completato;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '#${order.orderNumber}  •  Ore $timeStr',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.brickBrownDark,
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              order.customerName,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on,
                    size: 18, color: AppTheme.terracottaPrimary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    order.deliveryAddress,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (order.customerPhone.isNotEmpty) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () =>
                    launchUrl(Uri.parse('tel:${order.customerPhone}')),
                child: Row(
                  children: [
                    const Icon(Icons.phone, size: 18, color: AppTheme.paidGreen),
                    const SizedBox(width: 6),
                    Text(
                      order.customerPhone,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppTheme.paidGreen,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (order.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Indicazioni: ${order.notes}',
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  color: AppTheme.brickBrownDark,
                ),
              ),
            ],
            const Divider(height: 18),
            // Indicazione chiara su incasso vs già pagato
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: order.isPaid
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                order.isPaid
                    ? 'GIÀ PAGATO (${order.paymentMethod.label}) • NON CHIEDERE SOLDI'
                    : 'DA INCASSARE: € ${order.totalAmount.toStringAsFixed(2)} (${order.paymentMethod.label})',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: order.isPaid
                      ? AppTheme.paidGreen
                      : AppTheme.delayAlertRed,
                ),
              ),
            ),
            if (!isCompleted) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (order.status != OrderStatus.inConsegna)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => SupabaseService.instance
                            .updateOrderStatus(
                            order.id, OrderStatus.inConsegna),
                        icon: const Icon(Icons.delivery_dining),
                        label: const Text('PRENDI IN CARICO'),
                      ),
                    ),
                  if (order.status != OrderStatus.inConsegna)
                    const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.paidGreen,
                      ),
                      onPressed: () async {
                        // Registra automaticamente il turno se il rider ha dimenticato di cliccare "Inizia turno"
                        if (order.assignedRider != null) {
                          await SupabaseService.instance.registerRiderShift(
                            order.assignedRider!,
                            order.scheduledFor,
                          );
                        }
                        await SupabaseService.instance
                            .updateOrderStatus(order.id, OrderStatus.completato);
                      },
                      icon: const Icon(Icons.check_circle),
                      label: const Text('CONSEGNATO'),
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