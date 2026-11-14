import 'package:flutter/material.dart';

enum UserRole {
  titolare('titolare', 'Titolare'),
  dipendente('dipendente', 'Dipendente'),
  rider1('rider_1', 'Rider 1'),
  rider2('rider_2', 'Rider 2');

  final String dbValue;
  final String label;
  const UserRole(this.dbValue, this.label);

  static UserRole fromDb(String value) {
    return UserRole.values.firstWhere(
          (e) => e.dbValue == value,
      orElse: () => UserRole.dipendente,
    );
  }
}

class AppUserSession {
  final String id;
  final UserRole role;
  final String displayName;

  const AppUserSession({
    required this.id,
    required this.role,
    required this.displayName,
  });

  bool get isOwner => role == UserRole.titolare;
  bool get isStaffOrOwner => role == UserRole.titolare || role == UserRole.dipendente;
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

  /// Regola fondamentale: solo Diretto (se consegna) e Just Eat usano i rider interni
  bool get usesInternalRiders =>
      this == OrderSource.diretto || this == OrderSource.justEat;

  bool get isExternalCourier =>
      this == OrderSource.glovo || this == OrderSource.deliveroo;

  Color get badgeColor {
    switch (this) {
      case OrderSource.diretto:
        return const Color(0xFFB84221);
      case OrderSource.justEat:
        return const Color(0xFFE65100);
      case OrderSource.glovo:
        return const Color(0xFFC88A00);
      case OrderSource.deliveroo:
        return const Color(0xFF00897B);
      case OrderSource.banco:
        return const Color(0xFF6D4C41);
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
  nuovoOrdine('nuovo_ordine', 'Nuovo ordine', Color(0xFFD84315)),
  daPreparare('da_preparare', 'Da preparare', Color(0xFFEF6C00)),
  inPreparazione('in_preparazione', 'In preparazione', Color(0xFFF9A825)),
  inForno('in_forno', 'In forno', Color(0xFFBF360C)),
  pronto('pronto', 'Pronto', Color(0xFF2E7D32)),
  inConsegna('in_consegna', 'In consegna', Color(0xFF1565C0)),
  completato('completato', 'Completato', Color(0xFF5D4037));

  final String dbValue;
  final String label;
  final Color color;
  const OrderStatus(this.dbValue, this.label, this.color);

  static OrderStatus fromDb(String value) {
    return OrderStatus.values.firstWhere(
          (e) => e.dbValue == value,
      orElse: () => OrderStatus.nuovoOrdine,
    );
  }

  /// Restituisce lo stato successivo rispettando la regola del ritiro al banco
  OrderStatus? nextStatus(DeliveryType deliveryType, OrderSource source) {
    switch (this) {
      case OrderStatus.nuovoOrdine:
        return OrderStatus.daPreparare;
      case OrderStatus.daPreparare:
        return OrderStatus.inPreparazione;
      case OrderStatus.inPreparazione:
        return OrderStatus.inForno;
      case OrderStatus.inForno:
        return OrderStatus.pronto;
      case OrderStatus.pronto:
        if (deliveryType == DeliveryType.ritiro || source == OrderSource.banco) {
          return OrderStatus.completato; // Salta "In consegna" per il banco
        }
        return OrderStatus.inConsegna;
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

  /// Verifica se il prodotto è disponibile nel giorno dell'ordine (es. Martedì=2, Mercoledì=3)
  bool isAvailableOnDate(DateTime date) {
    if (!available) return false;
    if (allowedWeekdays == null || allowedWeekdays!.isEmpty) return true;
    return allowedWeekdays!.contains(date.weekday);
  }
}

/// Calcolo automatico del prezzo delle Teglie secondo le regole della pizzeria
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
    return 20.00; // Teglia intera 1 o 2 gusti semplici
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
      addedIngredients: List<String>.from(json['added_ingredients'] ?? const []),
      removedIngredients: List<String>.from(json['removed_ingredients'] ?? const []),
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
  final String? assignedRider; // 'rider_1', 'rider_2', o null
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
      deliveryType: DeliveryType.fromDb(json['delivery_type'] as String? ?? 'ritiro'),
      source: OrderSource.fromDb(json['source'] as String? ?? 'diretto'),
      items: rawItems
          .map((e) => OrderLineItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      notes: json['notes'] as String? ?? '',
      assignedRider: json['assigned_rider'] as String?,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: PaymentMethod.fromDb(json['payment_method'] as String? ?? 'contanti'),
      isPaid: json['is_paid'] as bool? ?? false,
      status: OrderStatus.fromDb(json['status'] as String? ?? 'nuovo_ordine'),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String).toLocal()
          : null,
    );
  }

  /// Indica se l'ordine è in ritardo rispetto all'orario richiesto
  bool get isDelayed =>
      status != OrderStatus.completato && DateTime.now().isAfter(scheduledFor);

  int get delayMinutes =>
      isDelayed ? DateTime.now().difference(scheduledFor).inMinutes : 0;

  /// Verifica se l'ordine richiede un rider della pizzeria
  bool get needsInternalRider =>
      deliveryType == DeliveryType.consegna && source.usesInternalRiders;

  /// Verifica se l'ordine genera compenso al rider (completato + consegna + Diretto/JustEat)
  bool get generatesRiderCommission =>
      status == OrderStatus.completato &&
          deliveryType == DeliveryType.consegna &&
          source.usesInternalRiders &&
          assignedRider != null;
}

class RiderCompensationSummary {
  final String riderRole;
  final String riderName;
  final int shiftDaysCount;
  final double baseFeesTotal;
  final int completedDeliveriesCount;
  final double deliveriesBonusTotal;

  const RiderCompensationSummary({
    required this.riderRole,
    required this.riderName,
    required this.shiftDaysCount,
    required this.baseFeesTotal,
    required this.completedDeliveriesCount,
    required this.deliveriesBonusTotal,
  });

  double get grandTotal => baseFeesTotal + deliveriesBonusTotal;
}