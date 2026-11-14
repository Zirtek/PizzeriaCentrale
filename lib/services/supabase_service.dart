import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  final SupabaseClient _client = Supabase.instance.client;

  /// Verifica sicura del PIN tramite RPC PostgreSQL (nessun PIN in chiaro)
  Future<AppUserSession?> loginWithPin(UserRole role, String pin) async {
    final response = await _client.rpc(
      'verify_pizzeria_pin',
      params: {'p_role': role.dbValue, 'p_pin': pin},
    );

    if (response is List && response.isNotEmpty) {
      final row = Map<String, dynamic>.from(response.first as Map);
      return AppUserSession(
        id: row['id'] as String,
        role: UserRole.fromDb(row['role'] as String),
        displayName: row['display_name'] as String,
      );
    }
    return null;
  }

  Future<void> updateUserPin(UserRole role, String newPin) async {
    await _client.rpc(
      'update_pizzeria_pin',
      params: {'p_role': role.dbValue, 'p_new_pin': newPin},
    );
  }

  /// Stream in tempo reale di tutti gli ordini
  Stream<List<PizzeriaOrder>> watchOrders() {
    return _client
        .from('pizzeria_orders')
        .stream(primaryKey: ['id'])
        .order('scheduled_for', ascending: true)
        .map((rows) => rows.map((r) => PizzeriaOrder.fromJson(r)).toList());
  }

  /// Stream in tempo reale del menu
  Stream<List<MenuItemModel>> watchMenu() {
    return _client
        .from('pizzeria_menu')
        .stream(primaryKey: ['id'])
        .order('sort_order', ascending: true)
        .map((rows) => rows.map((r) => MenuItemModel.fromJson(r)).toList());
  }

  Future<void> createOrder({
    required DateTime scheduledFor,
    required String customerName,
    required String customerPhone,
    required String deliveryAddress,
    required DeliveryType deliveryType,
    required OrderSource source,
    required List<OrderLineItem> items,
    required String notes,
    required String? assignedRider,
    required double totalAmount,
    required PaymentMethod paymentMethod,
    required bool isPaid,
  }) async {
    // Glovo, Deliveroo e Banco non possono mai avere un rider interno assegnato
    final String? safeRider =
    (deliveryType == DeliveryType.consegna && source.usesInternalRiders)
        ? assignedRider
        : null;

    await _client.from('pizzeria_orders').insert({
      'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      'customer_name': customerName.trim(),
      'customer_phone': customerPhone.trim(),
      'delivery_address':
      deliveryType == DeliveryType.consegna ? deliveryAddress.trim() : '',
      'delivery_type': deliveryType.dbValue,
      'source': source.dbValue,
      'items': items.map((e) => e.toJson()).toList(),
      'notes': notes.trim(),
      'assigned_rider': safeRider,
      'total_amount': totalAmount,
      'payment_method': paymentMethod.dbValue,
      'is_paid': isPaid,
      'status': OrderStatus.nuovoOrdine.dbValue,
    });
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus newStatus) async {
    final updateData = <String, dynamic>{
      'status': newStatus.dbValue,
    };
    if (newStatus == OrderStatus.completato) {
      updateData['completed_at'] = DateTime.now().toUtc().toIso8601String();
    }
    await _client.from('pizzeria_orders').update(updateData).eq('id', orderId);
  }

  Future<void> assignRider(String orderId, String? riderRole) async {
    await _client
        .from('pizzeria_orders')
        .update({'assigned_rider': riderRole})
        .eq('id', orderId);
  }

  Future<void> toggleOrderPaid(String orderId, bool isPaid) async {
    await _client
        .from('pizzeria_orders')
        .update({'is_paid': isPaid})
        .eq('id', orderId);
  }

  Future<void> deleteOrder(String orderId) async {
    await _client.from('pizzeria_orders').delete().eq('id', orderId);
  }

  /// Aggiornamento menu dal Titolare
  Future<void> updateMenuItem({
    required String id,
    required double? price,
    required bool priceConfirmed,
    required bool available,
  }) async {
    await _client.from('pizzeria_menu').update({
      'price': price,
      'price_confirmed': priceConfirmed,
      'available': available,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Registra il turno giornaliero del rider (idempotente grazie a UNIQUE(rider_role, shift_date))
  Future<void> registerRiderShift(String riderRole, DateTime date) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    await _client.from('pizzeria_rider_shifts').upsert(
      {
        'rider_role': riderRole,
        'shift_date': dateStr,
      },
      onConflict: 'rider_role,shift_date',
    );
  }

  Future<bool> hasRiderShiftToday(String riderRole) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final res = await _client
        .from('pizzeria_rider_shifts')
        .select('id')
        .eq('rider_role', riderRole)
        .eq('shift_date', dateStr);
    return (res as List).isNotEmpty;
  }

  /// Calcolo automatico compensi rider (Lun-Ven: 15€ + 2€/cons | Sab-Dom: 18€ + 2€/cons)
  Future<RiderCompensationSummary> calculateRiderCompensation({
    required String riderRole,
    required String riderName,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final startDay = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final endDay = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    final fromStr = DateFormat('yyyy-MM-dd').format(startDay);
    final toStr = DateFormat('yyyy-MM-dd').format(endDay);

    // 1. Recupera i giorni di turno lavorati nel periodo
    final shiftsRes = await _client
        .from('pizzeria_rider_shifts')
        .select('shift_date')
        .eq('rider_role', riderRole)
        .gte('shift_date', fromStr)
        .lte('shift_date', toStr);

    final shiftDates = (shiftsRes as List)
        .map((r) => DateTime.parse(r['shift_date'] as String))
        .toList();

    double baseFees = 0.0;
    for (final d in shiftDates) {
      final isWeekend =
          d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
      baseFees += isWeekend ? 18.0 : 15.0;
    }

    // 2. Recupera le consegne completate (solo Diretto e Just Eat, conteggiate una sola volta)
    final ordersRes = await _client
        .from('pizzeria_orders')
        .select()
        .eq('assigned_rider', riderRole)
        .eq('status', OrderStatus.completato.dbValue)
        .eq('delivery_type', DeliveryType.consegna.dbValue)
        .inFilter('source', [OrderSource.diretto.dbValue, OrderSource.justEat.dbValue])
        .gte('scheduled_for', startDay.toUtc().toIso8601String())
        .lte('scheduled_for', endDay.toUtc().toIso8601String());

    final deliveriesCount = (ordersRes as List).length;
    final bonusTotal = deliveriesCount * 2.0;

    return RiderCompensationSummary(
      riderRole: riderRole,
      riderName: riderName,
      shiftDaysCount: shiftDates.length,
      baseFeesTotal: baseFees,
      completedDeliveriesCount: deliveriesCount,
      deliveriesBonusTotal: bonusTotal,
    );
  }
}