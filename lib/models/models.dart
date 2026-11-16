import 'package:flutter/material.dart';

class UserRole {
  static const String titolare = 'titolare';
  static const String dipendente = 'dipendente';
  static const String rider1 = 'rider_1';
  static const String rider2 = 'rider_2';

  static bool isRiderRole(String role) => role.startsWith('rider_');

  static int riderNumber(String role) {
    if (!isRiderRole(role)) return 999;
    return int.tryParse(role.replaceFirst('rider_', '')) ?? 999;
  }

  static String defaultLabel(String role) {
    switch (role) {
      case titolare:
        return 'Titolare';
      case dipendente:
        return 'Dipendente';
      default:
        if (isRiderRole(role)) {
          final numPart = role.replaceFirst('rider_', '');
          return 'Rider $numPart';
        }
        return role;
    }
  }
}

class UserProfile {
  final String id;
  final String role;
  final String displayName;
  final bool isActive;

  const UserProfile({
    required this.id,
    required this.role,
    required this.displayName,
    this.isActive = true,
  });

  bool get isOwner => role == UserRole.titolare;
  bool get isDipendente => role == UserRole.dipendente;
  bool get isRider => UserRole.isRiderRole(role);

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String? ?? UserRole.dipendente;
    final rawName = (json['display_name'] as String? ?? '').trim();
    return UserProfile(
      id: (json['id'] ?? role).toString(),
      role: role,
      displayName: rawName.isNotEmpty ? rawName : UserRole.defaultLabel(role),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  static List<UserProfile> fallbackDefaults() => const [
    UserProfile(
      id: 'titolare',
      role: UserRole.titolare,
      displayName: 'Titolare',
    ),
    UserProfile(
      id: 'dipendente',
      role: UserRole.dipendente,
      displayName: 'Dipendente',
    ),
    UserProfile(
      id: 'rider_1',
      role: UserRole.rider1,
      displayName: 'Rider 1',
    ),
    UserProfile(
      id: 'rider_2',
      role: UserRole.rider2,
      displayName: 'Rider 2',
    ),
  ];
}

class AppUserSession {
  final String id;
  final String role;
  final String displayName;

  const AppUserSession({
    required this.id,
    required this.role,
    required this.displayName,
  });

  bool get isOwner => role == UserRole.titolare;
  bool get isDipendente => role == UserRole.dipendente;
  bool get isStaffOrOwner => isOwner || isDipendente;
  bool get isRider => UserRole.isRiderRole(role);
}

class RiderRates {
  final double weekdayBaseFee;
  final double saturdayBaseFee;
  final double perDeliveryBonus;

  const RiderRates({
    this.weekdayBaseFee = 15.0,
    this.saturdayBaseFee = 20.0,
    this.perDeliveryBonus = 2.0,
  });

  double baseFeeForDate(DateTime date) {
    return date.weekday == DateTime.saturday
        ? saturdayBaseFee
        : weekdayBaseFee;
  }

  factory RiderRates.fromJson(Map<String, dynamic> json) {
    return RiderRates(
      weekdayBaseFee:
      (json['weekday_base_fee'] as num?)?.toDouble() ?? 15.0,
      saturdayBaseFee:
      (json['saturday_base_fee'] as num?)?.toDouble() ?? 20.0,
      perDeliveryBonus:
      (json['per_delivery_bonus'] as num?)?.toDouble() ?? 2.0,
    );
  }
}

class RiderShiftRecord {
  final String id;
  final String riderRole;
  final DateTime shiftDate;
  final double startingFloat;
  final DateTime? closedAt;
  final double cashCollected;
  final double cardCollected;
  final double onlinePaid;
  final int deliveriesCount;
  final double riderEarnings;
  final String closingNotes;

  const RiderShiftRecord({
    required this.id,
    required this.riderRole,
    required this.shiftDate,
    this.startingFloat = 0.0,
    this.closedAt,
    this.cashCollected = 0.0,
    this.cardCollected = 0.0,
    this.onlinePaid = 0.0,
    this.deliveriesCount = 0,
    this.riderEarnings = 0.0,
    this.closingNotes = '',
  });

  bool get isClosed => closedAt != null;

  factory RiderShiftRecord.fromJson(Map<String, dynamic> json) {
    return RiderShiftRecord(
      id: (json['id'] ?? '').toString(),
      riderRole: json['rider_role'] as String? ?? '',
      shiftDate: json['shift_date'] != null
          ? DateTime.parse(json['shift_date'] as String)
          : DateTime.now(),
      startingFloat: (json['starting_float'] as num?)?.toDouble() ?? 0.0,
      closedAt: json['closed_at'] != null
          ? DateTime.parse(json['closed_at'] as String).toLocal()
          : null,
      cashCollected: (json['cash_collected'] as num?)?.toDouble() ?? 0.0,
      cardCollected: (json['card_collected'] as num?)?.toDouble() ?? 0.0,
      onlinePaid: (json['online_paid'] as num?)?.toDouble() ?? 0.0,
      deliveriesCount: (json['deliveries_count'] as num?)?.toInt() ?? 0,
      riderEarnings: (json['rider_earnings'] as num?)?.toDouble() ?? 0.0,
      closingNotes: json['closing_notes'] as String? ?? '',
    );
  }
}

enum OrderSource {
  diretto('diretto', 'Diretto'),
  justEat('just_eat', 'Just Eat'),
  glovo('glovo', 'Glovo'),
  deliveroo('deliveroo', 'Deliveroo'),
  banco('banco', 'Banco');

  final String dbValue;
  final String label;
  const OrderSource(this.dbValue, this.label);

  static OrderSource fromDb(String value) {
    return OrderSource.values.firstWhere(
          (e) => e.dbValue == value,
      orElse: () => OrderSource.diretto,
    );
  }

  /// Solo Diretto (se consegna) e Just Eat usano i rider interni
  bool get usesInternalRiders =>
      this == OrderSource.diretto || this == OrderSource.justEat;

  bool get isExternalCourier =>
      this == OrderSource.glovo || this == OrderSource.deliveroo;

  Color get badgeColor {
    switch (this) {
      case OrderSource.diretto:
        return const Color(0xFFE53935);
      case OrderSource.justEat:
        return const Color(0xFFFF6D00);
      case OrderSource.glovo:
        return const Color(0xFFFFD60A);
      case OrderSource.deliveroo:
        return const Color(0xFF00BFA5);
      case OrderSource.banco:
        return const Color(0xFF455A64);
    }
  }

  Color get badgeTextColor {
    switch (this) {
      case OrderSource.glovo:
      case OrderSource.deliveroo:
        return Colors.black;
      default:
        return Colors.white;
    }
  }
}

enum DeliveryType {
  ritiro('ritiro', 'Ritiro al banco'),
  consegna('consegna', 'Consegna a domicilio');

  final String dbValue;
  final String label;
  const DeliveryType(this.dbValue, this.label);

  static DeliveryType fromDb(String value) {
    return DeliveryType.values.firstWhere(
          (e) => e.dbValue == value,
      orElse: () => DeliveryType.ritiro,
    );
  }
}

enum OrderStatus {
  // Da iniziare -> Rosso
  nuovoOrdine('nuovo_ordine', 'Nuovo ordine', Color(0xFFE53935), Colors.white),
  // Da completare -> Giallo
  pronto('pronto', 'Pronto', Color(0xFFFFD60A), Colors.black),
  inConsegna('in_consegna', 'In consegna', Color(0xFFFFD60A), Colors.black),
  // Completati -> Verde
  completato('completato', 'Completato', Color(0xFF00E676), Colors.black);

  final String dbValue;
  final String label;
  final Color color;
  final Color textColor;
  const OrderStatus(this.dbValue, this.label, this.color, this.textColor);

  static OrderStatus fromDb(String value) {
    return OrderStatus.values.firstWhere(
          (e) => e.dbValue == value,
      orElse: () => OrderStatus.nuovoOrdine,
    );
  }

  /// Da Nuovo ordine passa DIRETTAMENTE a Pronto.
  /// Quando è Pronto, le consegne con rider interni attendono la presa in carico del rider.
  OrderStatus? nextStatus(DeliveryType deliveryType, OrderSource source) {
    switch (this) {
      case OrderStatus.nuovoOrdine:
        return OrderStatus.pronto;
      case OrderStatus.pronto:
        if (deliveryType == DeliveryType.ritiro ||
            source == OrderSource.banco ||
            source.isExternalCourier) {
          return OrderStatus.completato;
        }
        return null;
      case OrderStatus.inConsegna:
        return OrderStatus.completato;
      case OrderStatus.completato:
        return null;
    }
  }
}

enum PaymentMethod {
  contanti('contanti', 'Contanti'),
  carta('carta', 'Carta'),
  online('online', 'Pagamento online');

  final String dbValue;
  final String label;
  const PaymentMethod(this.dbValue, this.label);

  static PaymentMethod fromDb(String value) {
    return PaymentMethod.values.firstWhere(
          (e) => e.dbValue == value,
      orElse: () => PaymentMethod.contanti,
    );
  }
}

class MenuItemModel {
  final String id;
  final String category;
  final String name;
  final double? price;
  final bool priceConfirmed;
  final bool available;
  final List<int>? allowedWeekdays;

  const MenuItemModel({
    required this.id,
    required this.category,
    required this.name,
    required this.price,
    required this.priceConfirmed,
    required this.available,
    this.allowedWeekdays,
  });

  factory MenuItemModel.fromJson(Map<String, dynamic> json) {
    return MenuItemModel(
      id: json['id'] as String,
      category: json['category'] as String,
      name: json['name'] as String,
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      priceConfirmed: json['price_confirmed'] as bool? ?? true,
      available: json['available'] as bool? ?? true,
      allowedWeekdays: json['allowed_weekdays'] != null
          ? List<int>.from(json['allowed_weekdays'] as List)
          : null,
    );
  }

  bool isAvailableOnDate(DateTime date) {
    if (!available) return false;
    if (allowedWeekdays == null || allowedWeekdays!.isEmpty) return true;
    return allowedWeekdays!.contains(date.weekday);
  }
}

class TegliaPricing {
  static double calculatePrice({
    required bool isMezzaTeglia,
    required List<MenuItemModel> selectedFlavors,
  }) {
    if (isMezzaTeglia) {
      return 14.00;
    }
    if (selectedFlavors.length >= 4) {
      return 28.00;
    }
    final hasSpecial = selectedFlavors.any(
          (f) => f.category == 'teglia_gusto_speciale',
    );
    if (hasSpecial) {
      return 25.00;
    }
    if (selectedFlavors.length == 3) {
      return 22.00;
    }
    return 20.00;
  }
}

class OrderLineItem {
  final String name;
  final String category;
  final int quantity;
  final double unitPrice;
  final List<String> addedIngredients;
  final List<String> removedIngredients;
  final String notes;

  const OrderLineItem({
    required this.name,
    required this.category,
    required this.quantity,
    required this.unitPrice,
    this.addedIngredients = const [],
    this.removedIngredients = const [],
    this.notes = '',
  });

  double get subtotal => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'quantity': quantity,
    'unit_price': unitPrice,
    'added_ingredients': addedIngredients,
    'removed_ingredients': removedIngredients,
    'notes': notes,
  };

  factory OrderLineItem.fromJson(Map<String, dynamic> json) {
    return OrderLineItem(
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      addedIngredients:
      List<String>.from(json['added_ingredients'] ?? const []),
      removedIngredients:
      List<String>.from(json['removed_ingredients'] ?? const []),
      notes: json['notes'] as String? ?? '',
    );
  }
}

class PizzeriaOrder {
  final String id;
  final int orderNumber;
  final DateTime createdAt;
  final DateTime scheduledFor;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final DeliveryType deliveryType;
  final OrderSource source;
  final List<OrderLineItem> items;
  final String notes;
  final String? assignedRider;
  final double totalAmount;
  final PaymentMethod paymentMethod;
  final bool isPaid;
  final OrderStatus status;
  final DateTime? completedAt;

  const PizzeriaOrder({
    required this.id,
    required this.orderNumber,
    required this.createdAt,
    required this.scheduledFor,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    required this.deliveryType,
    required this.source,
    required this.items,
    required this.notes,
    required this.assignedRider,
    required this.totalAmount,
    required this.paymentMethod,
    required this.isPaid,
    required this.status,
    this.completedAt,
  });

  factory PizzeriaOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return PizzeriaOrder(
      id: json['id'] as String,
      orderNumber: (json['order_number'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      scheduledFor: DateTime.parse(json['scheduled_for'] as String).toLocal(),
      customerName: json['customer_name'] as String? ?? '',
      customerPhone: json['customer_phone'] as String? ?? '',
      deliveryAddress: json['delivery_address'] as String? ?? '',
      deliveryType:
      DeliveryType.fromDb(json['delivery_type'] as String? ?? 'ritiro'),
      source: OrderSource.fromDb(json['source'] as String? ?? 'diretto'),
      items: rawItems
          .map((e) =>
          OrderLineItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      notes: json['notes'] as String? ?? '',
      assignedRider: json['assigned_rider'] as String?,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod:
      PaymentMethod.fromDb(json['payment_method'] as String? ?? 'contanti'),
      isPaid: json['is_paid'] as bool? ?? false,
      status: OrderStatus.fromDb(json['status'] as String? ?? 'nuovo_ordine'),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String).toLocal()
          : null,
    );
  }

  bool get isDelayed =>
      status != OrderStatus.completato && DateTime.now().isAfter(scheduledFor);

  int get delayMinutes =>
      isDelayed ? DateTime.now().difference(scheduledFor).inMinutes : 0;

  bool get needsInternalRider =>
      deliveryType == DeliveryType.consegna && source.usesInternalRiders;

  bool get generatesRiderCommission =>
      status == OrderStatus.completato &&
          deliveryType == DeliveryType.consegna &&
          source.usesInternalRiders &&
          assignedRider != null;
}

class SavedCustomer {
  final String name;
  final String phone;
  final String address;
  final int ordersCount;
  final DateTime lastOrderAt;

  const SavedCustomer({
    required this.name,
    required this.phone,
    required this.address,
    required this.ordersCount,
    required this.lastOrderAt,
  });
}

class RiderCompensationSummary {
  final String riderRole;
  final String riderName;
  final bool isActive;
  final int shiftDaysCount;
  final double baseFeesTotal;
  final int completedDeliveriesCount;
  final double deliveriesBonusTotal;

  const RiderCompensationSummary({
    required this.riderRole,
    required this.riderName,
    this.isActive = true,
    required this.shiftDaysCount,
    required this.baseFeesTotal,
    required this.completedDeliveriesCount,
    required this.deliveriesBonusTotal,
  });

  double get grandTotal => baseFeesTotal + deliveriesBonusTotal;
}