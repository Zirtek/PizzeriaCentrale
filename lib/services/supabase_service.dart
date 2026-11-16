import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  final SupabaseClient _client = Supabase.instance.client;
  bool _didSplitCombinedDrinks = false;

  Future<AppUserSession?> loginWithPin(String role, String pin) async {
    final response = await _client.rpc(
      'verify_pizzeria_pin',
      params: {'p_role': role, 'p_pin': pin},
    );

    if (response is List && response.isNotEmpty) {
      final row = Map<String, dynamic>.from(response.first as Map);
      return AppUserSession(
        id: row['id'].toString(),
        role: row['role'] as String,
        displayName: row['display_name'] as String,
      );
    }
    return null;
  }

  Future<void> updateUserPin(String role, String newPin) async {
    await _client.rpc(
      'update_pizzeria_pin',
      params: {'p_role': role, 'p_new_pin': newPin},
    );
  }

  /// Carica tutti i profili configurati (Titolare, Dipendente, Rider 1..N)
  Future<List<UserProfile>> fetchUserProfiles({
    bool includeInactive = false,
  }) async {
    try {
      final response = await _client.rpc('get_pizzeria_users');
      if (response is List && response.isNotEmpty) {
        final profiles = response
            .map((e) =>
            UserProfile.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((p) => includeInactive || p.isActive)
            .toList();
        if (profiles.isNotEmpty) return profiles;
      }
    } catch (_) {
      try {
        final rows = await _client
            .from('pizzeria_users')
            .select('id, role, display_name');
        final profiles = (rows as List)
            .map((e) =>
            UserProfile.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
          ..sort((a, b) =>
              _roleSortOrder(a.role).compareTo(_roleSortOrder(b.role)));
        if (profiles.isNotEmpty) return profiles;
      } catch (_) {}
    }
    return UserProfile.fallbackDefaults();
  }

  int _roleSortOrder(String role) {
    if (role == UserRole.titolare) return 1;
    if (role == UserRole.dipendente) return 2;
    if (UserRole.isRiderRole(role)) return 10 + UserRole.riderNumber(role);
    return 999;
  }

  /// Crea un nuovo rider (es. rider_3) o aggiorna nome/PIN di un rider esistente
  Future<void> upsertRiderProfile({
    required String role,
    required String displayName,
    String? pin,
  }) async {
    await _client.rpc(
      'upsert_pizzeria_rider',
      params: {
        'p_role': role,
        'p_display_name': displayName.trim(),
        'p_pin': pin?.trim(),
      },
    );
  }

  /// Attiva o disattiva un profilo rider/dipendente
  Future<void> setUserActive(String role, bool isActive) async {
    await _client.rpc(
      'set_pizzeria_user_active',
      params: {
        'p_role': role,
        'p_is_active': isActive,
      },
    );
  }

  /// Elimina un profilo rider dal database
  Future<void> deleteRiderProfile(String role) async {
    await _client.rpc(
      'delete_pizzeria_rider',
      params: {'p_role': role},
    );
  }

  /// Legge le tariffe configurate per i rider (feriale, sabato, bonus consegna)
  Future<RiderRates> fetchRiderRates() async {
    try {
      final row = await _client
          .from('pizzeria_settings')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (row != null) {
        return RiderRates.fromJson(Map<String, dynamic>.from(row));
      }
    } catch (_) {}
    return const RiderRates();
  }

  /// Salva le tariffe rider su Supabase
  Future<void> updateRiderRates(RiderRates rates) async {
    await _client.from('pizzeria_settings').upsert({
      'id': 1,
      'weekday_base_fee': rates.weekdayBaseFee,
      'saturday_base_fee': rates.saturdayBaseFee,
      'per_delivery_bonus': rates.perDeliveryBonus,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Stream<List<PizzeriaOrder>> watchOrders() {
    return _client
        .from('pizzeria_orders')
        .stream(primaryKey: ['id'])
        .order('scheduled_for', ascending: true)
        .map((rows) => rows.map((r) => PizzeriaOrder.fromJson(r)).toList());
  }

  /// Estrae la rubrica dei clienti abituali dallo storico ordini,
  /// raggruppando per numero di telefono normalizzato.
  Future<List<SavedCustomer>> fetchSavedCustomers() async {
    final rows = await _client
        .from('pizzeria_orders')
        .select('customer_name, customer_phone, delivery_address, created_at')
        .order('created_at', ascending: false);

    final Map<String, _CustomerAccumulator> byKey = {};

    for (final raw in (rows as List)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final name = (row['customer_name'] as String? ?? '').trim();
      final phone = (row['customer_phone'] as String? ?? '').trim();
      final address = (row['delivery_address'] as String? ?? '').trim();
      final createdAtStr = row['created_at'] as String?;
      final createdAt = createdAtStr != null
          ? DateTime.parse(createdAtStr).toLocal()
          : DateTime.now();

      final normalizedPhone = normalizePhone(phone);
      if (normalizedPhone.isEmpty) continue;

      final existing = byKey[normalizedPhone];
      if (existing == null) {
        byKey[normalizedPhone] = _CustomerAccumulator(
          name: name,
          phone: phone,
          address: address,
          ordersCount: 1,
          lastOrderAt: createdAt,
        );
      } else {
        existing.ordersCount += 1;
        if (existing.name.isEmpty && name.isNotEmpty) {
          existing.name = name;
        }
        if (existing.address.isEmpty && address.isNotEmpty) {
          existing.address = address;
        }
      }
    }

    final customers = byKey.values
        .where((c) => c.name.isNotEmpty)
        .map(
          (c) => SavedCustomer(
        name: c.name,
        phone: c.phone,
        address: c.address,
        ordersCount: c.ordersCount,
        lastOrderAt: c.lastOrderAt,
      ),
    )
        .toList();

    customers.sort((a, b) {
      final byCount = b.ordersCount.compareTo(a.ordersCount);
      if (byCount != 0) return byCount;
      return b.lastOrderAt.compareTo(a.lastOrderAt);
    });

    return customers;
  }

  static String normalizePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0039') && digits.length > 6) {
      digits = digits.substring(4);
    } else if (digits.startsWith('39') && digits.length >= 11) {
      digits = digits.substring(2);
    }
    return digits;
  }

  Stream<List<MenuItemModel>> watchMenu() {
    _ensureCombinedDrinksSplit();
    return _client
        .from('pizzeria_menu')
        .stream(primaryKey: ['id'])
        .order('sort_order', ascending: true)
        .map((rows) => rows.map((r) => MenuItemModel.fromJson(r)).toList());
  }

  /// Divide automaticamente "cocacola/fanta/te" in 3 prodotti singoli con lo stesso prezzo
  Future<void> _ensureCombinedDrinksSplit() async {
    if (_didSplitCombinedDrinks) return;
    _didSplitCombinedDrinks = true;

    try {
      final rows = await _client.from('pizzeria_menu').select();
      final list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      for (final row in list) {
        final name = (row['name'] as String? ?? '').trim();
        final lower = name.toLowerCase();

        final isCombinedCocaFantaTe = lower.contains('coca') &&
            lower.contains('fanta') &&
            lower.contains('/') &&
            !lower.contains('lattina') &&
            !lower.contains('1,5') &&
            !lower.contains('1.5');

        if (isCombinedCocaFantaTe) {
          for (final singleName in ['Coca Cola', 'Fanta', 'Tè']) {
            final alreadyExists = list.any(
                  (r) =>
              (r['name'] as String? ?? '').trim().toLowerCase() ==
                  singleName.toLowerCase(),
            );
            if (!alreadyExists) {
              await _client.from('pizzeria_menu').insert({
                'category': row['category'],
                'name': singleName,
                'price': row['price'],
                'price_confirmed': row['price_confirmed'] ?? true,
                'available': row['available'] ?? true,
                'allowed_weekdays': row['allowed_weekdays'],
                'sort_order': row['sort_order'] ?? 999,
              });
            }
          }
          await _client.from('pizzeria_menu').delete().eq('id', row['id']);
        }
      }
    } catch (_) {
      _didSplitCombinedDrinks = false;
    }
  }

  /// Crea l'ordine nello stato "nuovo_ordine" senza rider assegnato
  Future<void> createOrder({
    required DateTime scheduledFor,
    required String customerName,
    required String customerPhone,
    required String deliveryAddress,
    required DeliveryType deliveryType,
    required OrderSource source,
    required List<OrderLineItem> items,
    required String notes,
    required double totalAmount,
    required PaymentMethod paymentMethod,
    required bool isPaid,
  }) async {
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
      'assigned_rider': null,
      'total_amount': totalAmount,
      'payment_method': paymentMethod.dbValue,
      'is_paid': isPaid,
      'status': OrderStatus.nuovoOrdine.dbValue,
    });
  }

  /// Aggiorna un ordine esistente (orario, dati cliente, prodotti, note, pagamento)
  Future<void> updateOrder({
    required String orderId,
    required DateTime scheduledFor,
    required String customerName,
    required String customerPhone,
    required String deliveryAddress,
    required DeliveryType deliveryType,
    required OrderSource source,
    required List<OrderLineItem> items,
    required String notes,
    required double totalAmount,
    required PaymentMethod paymentMethod,
    required bool isPaid,
  }) async {
    final needsInternalRider =
        deliveryType == DeliveryType.consegna && source.usesInternalRiders;

    final updateData = <String, dynamic>{
      'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      'customer_name': customerName.trim(),
      'customer_phone': customerPhone.trim(),
      'delivery_address':
      deliveryType == DeliveryType.consegna ? deliveryAddress.trim() : '',
      'delivery_type': deliveryType.dbValue,
      'source': source.dbValue,
      'items': items.map((e) => e.toJson()).toList(),
      'notes': notes.trim(),
      'total_amount': totalAmount,
      'payment_method': paymentMethod.dbValue,
      'is_paid': isPaid,
    };

    if (!needsInternalRider) {
      updateData['assigned_rider'] = null;
    }

    await _client
        .from('pizzeria_orders')
        .update(updateData)
        .eq('id', orderId);
  }

  /// Il rider può prendere in carico SOLO se l'ordine è già stato segnato PRONTO
  Future<bool> claimDelivery(String orderId, String riderRole) async {
    final updated = await _client
        .from('pizzeria_orders')
        .update({
      'assigned_rider': riderRole,
      'status': OrderStatus.inConsegna.dbValue,
    })
        .eq('id', orderId)
        .eq('status', OrderStatus.pronto.dbValue)
        .isFilter('assigned_rider', null)
        .select('id');

    return (updated as List).isNotEmpty;
  }

  /// Rimette la consegna tra quelle pronte disponibili (in caso di errore)
  Future<void> releaseDelivery(String orderId) async {
    await _client
        .from('pizzeria_orders')
        .update({
      'assigned_rider': null,
      'status': OrderStatus.pronto.dbValue,
    })
        .eq('id', orderId);
  }

  /// Aggiorna stato ordine: quando diventa COMPLETATO segna automaticamente is_paid = true
  Future<void> updateOrderStatus(
      String orderId,
      OrderStatus newStatus, {
        PaymentMethod? paymentMethod,
      }) async {
    final updateData = <String, dynamic>{
      'status': newStatus.dbValue,
    };
    if (newStatus == OrderStatus.completato) {
      updateData['completed_at'] = DateTime.now().toUtc().toIso8601String();
      updateData['is_paid'] = true;
      if (paymentMethod != null) {
        updateData['payment_method'] = paymentMethod.dbValue;
      }
    }
    await _client.from('pizzeria_orders').update(updateData).eq('id', orderId);
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

  /// Aggiunge un nuovo prodotto al listino
  Future<void> addMenuItem({
    required String category,
    required String name,
    required double? price,
    required bool priceConfirmed,
    required bool available,
  }) async {
    await _client.from('pizzeria_menu').insert({
      'category': category,
      'name': name.trim(),
      'price': price,
      'price_confirmed': priceConfirmed,
      'available': available,
      'sort_order': 999,
    });
  }

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

  Future<RiderCompensationSummary> calculateRiderCompensation({
    required String riderRole,
    required String riderName,
    bool isActive = true,
    required DateTime fromDate,
    required DateTime toDate,
    RiderRates? rates,
  }) async {
    final activeRates = rates ?? await fetchRiderRates();
    final startDay = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final endDay = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    final fromStr = DateFormat('yyyy-MM-dd').format(startDay);
    final toStr = DateFormat('yyyy-MM-dd').format(endDay);

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
      baseFees += activeRates.baseFeeForDate(d);
    }

    final ordersRes = await _client
        .from('pizzeria_orders')
        .select()
        .eq('assigned_rider', riderRole)
        .eq('status', OrderStatus.completato.dbValue)
        .eq('delivery_type', DeliveryType.consegna.dbValue)
        .inFilter(
        'source', [OrderSource.diretto.dbValue, OrderSource.justEat.dbValue])
        .gte('scheduled_for', startDay.toUtc().toIso8601String())
        .lte('scheduled_for', endDay.toUtc().toIso8601String());

    final deliveriesCount = (ordersRes as List).length;
    final bonusTotal = deliveriesCount * activeRates.perDeliveryBonus;

    return RiderCompensationSummary(
      riderRole: riderRole,
      riderName: riderName,
      isActive: isActive,
      shiftDaysCount: shiftDates.length,
      baseFeesTotal: baseFees,
      completedDeliveriesCount: deliveriesCount,
      deliveriesBonusTotal: bonusTotal,
    );
  }
}

class _CustomerAccumulator {
  String name;
  final String phone;
  String address;
  int ordersCount;
  final DateTime lastOrderAt;

  _CustomerAccumulator({
    required this.name,
    required this.phone,
    required this.address,
    required this.ordersCount,
    required this.lastOrderAt,
  });
}