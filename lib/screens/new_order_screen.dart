import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class NewOrderScreen extends StatefulWidget {
  final DateTime initialDate;
  final PizzeriaOrder? existingOrder;

  const NewOrderScreen({
    super.key,
    required this.initialDate,
    this.existingOrder,
  });

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  static const List<(int, int)> _timeSlots = [
    (19, 0),
    (19, 15),
    (19, 30),
    (19, 45),
    (20, 0),
    (20, 15),
    (20, 30),
    (20, 45),
    (21, 0),
    (21, 15),
    (21, 30),
  ];

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  late DateTime _scheduledDateTime;
  OrderSource _source = OrderSource.diretto;
  DeliveryType _deliveryType = DeliveryType.consegna;
  PaymentMethod _paymentMethod = PaymentMethod.contanti;
  bool _isPaid = false;

  String _selectedCategory = 'tutte';
  String _searchQuery = '';

  final List<OrderLineItem> _cart = [];
  bool _isSaving = false;

  // Rubrica clienti abituali
  List<SavedCustomer> _savedCustomers = [];
  List<SavedCustomer> _matchingCustomers = [];
  bool _suppressSuggestions = false;

  bool get _isEditing => widget.existingOrder != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingOrder;

    if (existing != null) {
      _nameCtrl.text = existing.customerName;
      _phoneCtrl.text = existing.customerPhone;
      _addressCtrl.text = existing.deliveryAddress;
      _notesCtrl.text = existing.notes;
      _scheduledDateTime = existing.scheduledFor;
      _source = existing.source;
      _deliveryType = existing.deliveryType;
      _paymentMethod = existing.paymentMethod;
      _isPaid = existing.isPaid;
      _cart.addAll(existing.items);
      _suppressSuggestions = true;
    } else {
      final now = DateTime.now();
      final isToday = now.year == widget.initialDate.year &&
          now.month == widget.initialDate.month &&
          now.day == widget.initialDate.day;

      int initialHour = 19;
      int initialMinute = 0;

      if (isToday) {
        final nowMinutes = now.hour * 60 + now.minute;
        const startMinutes = 19 * 60;
        const endMinutes = 21 * 60 + 30;
        if (nowMinutes >= startMinutes && nowMinutes < endMinutes) {
          final nextQuarter = ((nowMinutes ~/ 15) + 1) * 15;
          initialHour = nextQuarter ~/ 60;
          initialMinute = nextQuarter % 60;
        }
      }

      _scheduledDateTime = DateTime(
        widget.initialDate.year,
        widget.initialDate.month,
        widget.initialDate.day,
        initialHour,
        initialMinute,
      );
    }

    _phoneCtrl.addListener(_onCustomerFieldChanged);
    _nameCtrl.addListener(_onCustomerFieldChanged);
    _loadSavedCustomers();
  }

  Future<void> _loadSavedCustomers() async {
    try {
      final list = await SupabaseService.instance.fetchSavedCustomers();
      if (mounted) {
        setState(() {
          _savedCustomers = list;
        });
        _updateCustomerMatches();
      }
    } catch (_) {}
  }

  void _onCustomerFieldChanged() {
    if (_suppressSuggestions) {
      _suppressSuggestions = false;
      return;
    }
    _updateCustomerMatches();
  }

  void _updateCustomerMatches() {
    if (_savedCustomers.isEmpty) return;

    final phoneQuery = SupabaseService.normalizePhone(_phoneCtrl.text);
    final nameQuery = _nameCtrl.text.trim().toLowerCase();

    if (phoneQuery.length < 2 && nameQuery.length < 2) {
      if (_matchingCustomers.isNotEmpty) {
        setState(() => _matchingCustomers = []);
      }
      return;
    }

    final matches = _savedCustomers.where((c) {
      final cPhone = SupabaseService.normalizePhone(c.phone);
      final cName = c.name.toLowerCase();

      final phoneMatch = phoneQuery.length >= 2 && cPhone.contains(phoneQuery);
      final nameMatch = nameQuery.length >= 2 && cName.contains(nameQuery);
      return phoneMatch || nameMatch;
    }).take(4).toList();

    setState(() {
      _matchingCustomers = matches;
    });
  }

  void _applyCustomer(SavedCustomer customer) {
    _suppressSuggestions = true;
    setState(() {
      _nameCtrl.text = customer.name;
      _phoneCtrl.text = customer.phone;
      if (customer.address.isNotEmpty) {
        _addressCtrl.text = customer.address;
      }
      _matchingCustomers = [];
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _openCustomerDirectorySheet() async {
    final searchCtrl = TextEditingController();
    String filter = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final filtered = _savedCustomers.where((c) {
            if (filter.isEmpty) return true;
            final q = filter.toLowerCase();
            final qDigits = SupabaseService.normalizePhone(filter);
            return c.name.toLowerCase().contains(q) ||
                c.address.toLowerCase().contains(q) ||
                (qDigits.isNotEmpty &&
                    SupabaseService.normalizePhone(c.phone).contains(qDigits));
          }).toList();

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.78,
            maxChildSize: 0.92,
            builder: (_, scrollCtrl) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Rubrica Clienti (${_savedCustomers.length})',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textWhite,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: searchCtrl,
                      onChanged: (v) => setModalState(() => filter = v.trim()),
                      decoration: InputDecoration(
                        hintText: 'Cerca per telefono, nome o via...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: filter.isNotEmpty
                            ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            searchCtrl.clear();
                            setModalState(() => filter = '');
                          },
                        )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                        child: Text(
                          'Nessun cliente trovato in rubrica.',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      )
                          : ListView.separated(
                        controller: scrollCtrl,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            onTap: () {
                              Navigator.pop(ctx);
                              _applyCustomer(c);
                            },
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.surfaceElevated,
                              child: Text(
                                c.name.isNotEmpty
                                    ? c.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.toCompleteYellow,
                                ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    c.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textWhite,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.darkGreenTint,
                                    borderRadius:
                                    BorderRadius.circular(10),
                                    border: Border.all(
                                        color: AppTheme.moneyGreen),
                                  ),
                                  child: Text(
                                    '${c.ordersCount} ${c.ordersCount == 1 ? "ordine" : "ordini"}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.moneyGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '${c.phone}${c.address.isNotEmpty ? " • ${c.address}" : ""}',
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _phoneCtrl.removeListener(_onCustomerFieldChanged);
    _nameCtrl.removeListener(_onCustomerFieldChanged);
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  double get _cartTotal =>
      _cart.fold<double>(0.0, (sum, item) => sum + item.subtotal);

  int get _cartItemsCount =>
      _cart.fold<int>(0, (sum, item) => sum + item.quantity);

  void _selectSlot(int hour, int minute) {
    setState(() {
      _scheduledDateTime = DateTime(
        _scheduledDateTime.year,
        _scheduledDateTime.month,
        _scheduledDateTime.day,
        hour,
        minute,
      );
    });
  }

  void _onSourceChanged(OrderSource newSource) {
    setState(() {
      _source = newSource;
      if (newSource == OrderSource.banco) {
        _deliveryType = DeliveryType.ritiro;
      } else if (newSource == OrderSource.justEat ||
          newSource == OrderSource.glovo ||
          newSource == OrderSource.deliveroo) {
        _deliveryType = DeliveryType.consegna;
        if (!_isEditing && newSource != OrderSource.diretto) {
          _paymentMethod = PaymentMethod.online;
          _isPaid = true;
        }
      }
    });
  }

  Future<void> _pickScheduledDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledDateTime,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('it', 'IT'),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledDateTime),
    );
    if (time == null) return;

    setState(() {
      _scheduledDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _quickAddItem(MenuItemModel item) {
    if (!item.priceConfirmed || item.price == null) {
      _addMenuItemDialog(item);
      return;
    }
    setState(() {
      final existingIndex = _cart.indexWhere(
            (c) =>
        c.name == item.name &&
            c.addedIngredients.isEmpty &&
            c.removedIngredients.isEmpty &&
            c.notes.isEmpty,
      );
      if (existingIndex != -1) {
        final existing = _cart[existingIndex];
        _cart[existingIndex] = OrderLineItem(
          name: existing.name,
          category: existing.category,
          quantity: existing.quantity + 1,
          unitPrice: existing.unitPrice,
        );
      } else {
        _cart.add(
          OrderLineItem(
            name: item.name,
            category: item.category,
            quantity: 1,
            unitPrice: item.price!,
          ),
        );
      }
    });
  }

  void _decrementSimpleItem(String itemName) {
    final idx = _cart.lastIndexWhere((c) => c.name == itemName);
    if (idx == -1) return;
    setState(() {
      final current = _cart[idx];
      if (current.quantity > 1) {
        _cart[idx] = OrderLineItem(
          name: current.name,
          category: current.category,
          quantity: current.quantity - 1,
          unitPrice: current.unitPrice,
          addedIngredients: current.addedIngredients,
          removedIngredients: current.removedIngredients,
          notes: current.notes,
        );
      } else {
        _cart.removeAt(idx);
      }
    });
  }

  int _countInCart(String itemName) {
    return _cart
        .where((c) => c.name == itemName)
        .fold<int>(0, (sum, c) => sum + c.quantity);
  }

  Future<void> _openTegliaBuilder(List<MenuItemModel> menu) async {
    final simpleFlavors = menu
        .where((m) => m.category == 'teglia_gusto_semplice' && m.available)
        .toList();
    final specialFlavors = menu
        .where((m) => m.category == 'teglia_gusto_speciale' && m.available)
        .toList();

    bool isMezza = false;
    final selected = <MenuItemModel>[];
    final noteCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final currentPrice = TegliaPricing.calculatePrice(
              isMezzaTeglia: isMezza,
              selectedFlavors: selected,
            );

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.85,
              maxChildSize: 0.95,
              builder: (_, scrollCtrl) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'Componi Teglia',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textWhite,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Teglia Intera'),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Mezza Teglia (14 €)'),
                          ),
                        ],
                        selected: {isMezza},
                        onSelectionChanged: (val) {
                          setModalState(() {
                            isMezza = val.first;
                            if (isMezza && selected.length > 2) {
                              selected.removeRange(2, selected.length);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Prezzo: € ${currentPrice.toStringAsFixed(2)} (${selected.length}/${isMezza ? 2 : 4} gusti)',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.moneyGreen,
                        ),
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView(
                          controller: scrollCtrl,
                          children: [
                            const Text(
                              'GUSTI SEMPLICI',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.toCompleteYellow,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: simpleFlavors.map((flavor) {
                                final isSel = selected.contains(flavor);
                                return FilterChip(
                                  label: Text(flavor.name),
                                  selected: isSel,
                                  selectedColor: AppTheme.toCompleteYellow,
                                  checkmarkColor: Colors.black,
                                  labelStyle: TextStyle(
                                    color: isSel
                                        ? Colors.black
                                        : AppTheme.textWhite,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  onSelected: (v) {
                                    setModalState(() {
                                      if (v) {
                                        final max = isMezza ? 2 : 4;
                                        if (selected.length < max) {
                                          selected.add(flavor);
                                        }
                                      } else {
                                        selected.remove(flavor);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'GUSTI SPECIALI',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.toCompleteYellow,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: specialFlavors.map((flavor) {
                                final isSel = selected.contains(flavor);
                                return FilterChip(
                                  label: Text(flavor.name),
                                  selected: isSel,
                                  selectedColor: AppTheme.toCompleteYellow,
                                  checkmarkColor: Colors.black,
                                  labelStyle: TextStyle(
                                    color: isSel
                                        ? Colors.black
                                        : AppTheme.textWhite,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  onSelected: (v) {
                                    setModalState(() {
                                      if (v) {
                                        final max = isMezza ? 2 : 4;
                                        if (selected.length < max) {
                                          selected.add(flavor);
                                        }
                                      } else {
                                        selected.remove(flavor);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: noteCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Note / modifiche teglia',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () {
                            final label = isMezza
                                ? 'Mezza Teglia (${selected.map((e) => e.name).join(", ")})'
                                : 'Teglia Intera (${selected.map((e) => e.name).join(", ")})';
                            setState(() {
                              _cart.add(
                                OrderLineItem(
                                  name: label,
                                  category: 'teglia',
                                  quantity: 1,
                                  unitPrice: currentPrice,
                                  notes: noteCtrl.text.trim(),
                                ),
                              );
                            });
                            Navigator.pop(ctx);
                          },
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'AGGIUNGI TEGLIA (€ ${currentPrice.toStringAsFixed(2)})',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _addMenuItemDialog(MenuItemModel item) async {
    final priceCtrl = TextEditingController(
      text: item.price != null ? item.price!.toStringAsFixed(2) : '',
    );
    final addCtrl = TextEditingController();
    final remCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    int qty = 1;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            title: Text('Personalizza: ${item.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!item.priceConfirmed || item.price == null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.darkYellowTint,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.toCompleteYellow),
                      ),
                      child: const Text(
                        'Prezzo da confermare a listino. Inserisci l\'importo:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.toCompleteYellow,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: priceCtrl,
                      keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Prezzo unitario (€)',
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 28),
                        onPressed:
                        qty > 1 ? () => setDlgState(() => qty--) : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '$qty',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 28),
                        onPressed: () => setDlgState(() => qty++),
                      ),
                    ],
                  ),
                  TextField(
                    controller: addCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Aggiungi (+ ingredienti, separati da virgola)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: remCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Togli (- ingredienti, separati da virgola)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Note per la cucina',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annulla'),
              ),
              ElevatedButton(
                onPressed: () {
                  final parsedPrice = double.tryParse(
                    priceCtrl.text.replaceAll(',', '.'),
                  );
                  if (parsedPrice == null || parsedPrice <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                        Text('Inserisci un prezzo valido maggiore di 0'),
                      ),
                    );
                    return;
                  }
                  setState(() {
                    _cart.add(
                      OrderLineItem(
                        name: item.name,
                        category: item.category,
                        quantity: qty,
                        unitPrice: parsedPrice,
                        addedIngredients: addCtrl.text
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList(),
                        removedIngredients: remCtrl.text
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList(),
                        notes: noteCtrl.text.trim(),
                      ),
                    );
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Aggiungi'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editCartItemDialog(
      int index, StateSetter setSheetState) async {
    final existing = _cart[index];
    final priceCtrl =
    TextEditingController(text: existing.unitPrice.toStringAsFixed(2));
    final addCtrl =
    TextEditingController(text: existing.addedIngredients.join(', '));
    final remCtrl =
    TextEditingController(text: existing.removedIngredients.join(', '));
    final noteCtrl = TextEditingController(text: existing.notes);
    int qty = existing.quantity;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            title: Text('Modifica: ${existing.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 28),
                        onPressed:
                        qty > 1 ? () => setDlgState(() => qty--) : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '$qty',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 28),
                        onPressed: () => setDlgState(() => qty++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: priceCtrl,
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Prezzo unitario (€)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: addCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Aggiungi (+ ingredienti, separati da virgola)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: remCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Togli (- ingredienti, separati da virgola)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Note per la cucina',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annulla'),
              ),
              ElevatedButton(
                onPressed: () {
                  final parsedPrice = double.tryParse(
                    priceCtrl.text.replaceAll(',', '.'),
                  );
                  if (parsedPrice == null || parsedPrice <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                        Text('Inserisci un prezzo valido maggiore di 0'),
                      ),
                    );
                    return;
                  }
                  setState(() {
                    _cart[index] = OrderLineItem(
                      name: existing.name,
                      category: existing.category,
                      quantity: qty,
                      unitPrice: parsedPrice,
                      addedIngredients: addCtrl.text
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList(),
                      removedIngredients: remCtrl.text
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList(),
                      notes: noteCtrl.text.trim(),
                    );
                  });
                  setSheetState(() {});
                  Navigator.pop(ctx);
                },
                child: const Text('Salva'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openCartSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Carrello ($_cartItemsCount articoli)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textWhite,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '€ ${_cartTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.moneyGreen,
                      ),
                    ),
                  ],
                ),
                const Divider(),
                if (_cart.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Il carrello è vuoto.')),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _cart.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, idx) {
                        final item = _cart[idx];
                        final details = [
                          ...item.addedIngredients.map((e) => '+$e'),
                          ...item.removedIngredients.map((e) => '-$e'),
                          if (item.notes.isNotEmpty) item.notes,
                        ].join(', ');
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          onTap: () => _editCartItemDialog(idx, setSheetState),
                          title: Text(
                            '${item.quantity}x ${item.name}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            details.isNotEmpty
                                ? '$details • Tocca per modificare'
                                : 'Tocca per modificare varianti/quantità',
                            style: TextStyle(
                              fontSize: 12,
                              color: details.isNotEmpty
                                  ? AppTheme.toCompleteYellow
                                  : AppTheme.textMuted,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '€ ${item.subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.moneyGreen,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Modifica articolo',
                                constraints: const BoxConstraints(
                                    minWidth: 36, minHeight: 36),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.edit_outlined,
                                    color: AppTheme.toCompleteYellow),
                                onPressed: () =>
                                    _editCartItemDialog(idx, setSheetState),
                              ),
                              IconButton(
                                tooltip: 'Rimuovi articolo',
                                constraints: const BoxConstraints(
                                    minWidth: 36, minHeight: 36),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.delete_outline,
                                    color: AppTheme.toStartRed),
                                onPressed: () {
                                  setState(() => _cart.removeAt(idx));
                                  setSheetState(() {});
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveOrder() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci il nome del cliente')),
      );
      return;
    }
    if (_deliveryType == DeliveryType.consegna &&
        _addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
            Text('Inserisci l\'indirizzo per la consegna a domicilio')),
      );
      return;
    }
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Aggiungi almeno un prodotto all\'ordine')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await SupabaseService.instance.updateOrder(
          orderId: widget.existingOrder!.id,
          scheduledFor: _scheduledDateTime,
          customerName: _nameCtrl.text,
          customerPhone: _phoneCtrl.text,
          deliveryAddress: _addressCtrl.text,
          deliveryType: _deliveryType,
          source: _source,
          items: _cart,
          notes: _notesCtrl.text,
          totalAmount: _cartTotal,
          paymentMethod: _paymentMethod,
          isPaid: _isPaid,
        );
      } else {
        await SupabaseService.instance.createOrder(
          scheduledFor: _scheduledDateTime,
          customerName: _nameCtrl.text,
          customerPhone: _phoneCtrl.text,
          deliveryAddress: _addressCtrl.text,
          deliveryType: _deliveryType,
          source: _source,
          items: _cart,
          notes: _notesCtrl.text,
          totalAmount: _cartTotal,
          paymentMethod: _paymentMethod,
          isPaid: _isPaid,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore salvataggio ordine: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedTime = DateFormat('HH:mm').format(_scheduledDateTime);
    final formattedDate = DateFormat('dd/MM').format(_scheduledDateTime);
    final isCompact = MediaQuery.of(context).size.width < 410;

    const categories = [
      ('tutte', 'Tutti'),
      ('pizza_tonda', 'Pizze Tonde'),
      ('fritti', 'Fritti'),
      ('bevande', 'Bevande'),
      ('speciale_giorno', 'Speciali Mar/Mer'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? 'Modifica Ordine #${widget.existingOrder!.orderNumber}'
              : 'Nuovo Ordine Veloce',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          isCompact ? 10 : 14,
          10,
          isCompact ? 10 : 14,
          12,
        ),
        decoration: const BoxDecoration(
          color: AppTheme.surfaceDark,
          border: Border(top: BorderSide(color: AppTheme.cardBorder, width: 1.5)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              InkWell(
                onTap: _openCartSheet,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 9 : 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundBlack,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.moneyGreen),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        color: AppTheme.moneyGreen,
                        size: isCompact ? 20 : 24,
                      ),
                      const SizedBox(width: 6),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_cartItemsCount pz • Vedi',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '€ ${_cartTotal.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: isCompact ? 16 : 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.moneyGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: _isSaving ? null : _saveOrder,
                    icon: _isSaving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.black,
                      ),
                    )
                        : const Icon(Icons.check_circle_outline, size: 20),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _isSaving
                            ? 'SALVATAGGIO...'
                            : (_isEditing ? 'SALVA MODIFICHE' : 'SALVA ORDINE'),
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: StreamBuilder<List<MenuItemModel>>(
        stream: SupabaseService.instance.watchMenu(),
        builder: (context, snapshot) {
          final menu = snapshot.data ?? [];

          final productList = menu.where((m) {
            if (m.category == 'teglia_gusto_semplice' ||
                m.category == 'teglia_gusto_speciale') {
              return false;
            }
            if (_selectedCategory != 'tutte' &&
                m.category != _selectedCategory) {
              return false;
            }
            if (_searchQuery.isNotEmpty &&
                !m.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
              return false;
            }
            return true;
          }).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
            children: [
              // 1. Provenienza e tipo consegna
              const Text(
                '1. PROVENIENZA E SERVIZIO',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppTheme.toCompleteYellow,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: OrderSource.values.map((s) {
                  final sel = _source == s;
                  return ChoiceChip(
                    label: Text(s.label),
                    selected: sel,
                    selectedColor: s.badgeColor,
                    labelStyle: TextStyle(
                      color: sel ? s.badgeTextColor : AppTheme.textWhite,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (_) => _onSourceChanged(s),
                  );
                }).toList(),
              ),
              if (_source == OrderSource.diretto) ...[
                const SizedBox(height: 10),
                SegmentedButton<DeliveryType>(
                  segments: const [
                    ButtonSegment(
                      value: DeliveryType.consegna,
                      icon: Icon(Icons.delivery_dining),
                      label: Text('Consegna'),
                    ),
                    ButtonSegment(
                      value: DeliveryType.ritiro,
                      icon: Icon(Icons.storefront),
                      label: Text('Ritiro'),
                    ),
                  ],
                  selected: {_deliveryType},
                  onSelectionChanged: (val) =>
                      setState(() => _deliveryType = val.first),
                ),
              ],

              const SizedBox(height: 18),

              // 2. Orario + Dati cliente + Rubrica (con Wrap responsive)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  const Text(
                    '2. ORARIO E CLIENTE',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: AppTheme.toCompleteYellow,
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (_savedCustomers.isNotEmpty)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.contact_phone_outlined,
                              size: 14, color: AppTheme.moneyGreen),
                          label: Text(
                            'Rubrica (${_savedCustomers.length})',
                            style: const TextStyle(
                              color: AppTheme.moneyGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          backgroundColor: AppTheme.surfaceElevated,
                          onPressed: _openCustomerDirectorySheet,
                        ),
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.calendar_today,
                            size: 14, color: AppTheme.toCompleteYellow),
                        label: Text(
                          '$formattedDate • $formattedTime',
                          style: const TextStyle(
                            color: AppTheme.textWhite,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        backgroundColor: AppTheme.surfaceElevated,
                        onPressed: _pickScheduledDateTime,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _timeSlots.map((slot) {
                  final (hour, minute) = slot;
                  final label =
                      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
                  final isSelected = _scheduledDateTime.hour == hour &&
                      _scheduledDateTime.minute == minute;

                  return ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    selectedColor: AppTheme.toCompleteYellow,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : AppTheme.textWhite,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                    onSelected: (_) => _selectSlot(hour, minute),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // Telefono e Nome impilati su telefono stretto, affiancati su tablet
              if (isCompact) ...[
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefono',
                    prefixIcon: Icon(Icons.phone_outlined, size: 19),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                  const InputDecoration(labelText: 'Nome cliente *'),
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Telefono',
                          prefixIcon: Icon(Icons.phone_outlined, size: 19),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration:
                        const InputDecoration(labelText: 'Nome cliente *'),
                      ),
                    ),
                  ],
                ),

              // Suggerimenti istantanei dalla rubrica clienti abituali
              if (_matchingCustomers.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.toCompleteYellow,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Row(
                          children: [
                            Icon(Icons.bolt,
                                size: 15, color: AppTheme.toCompleteYellow),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'CLIENTI ABITUALI TROVATI (TOCCA PER COMPILARE)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.toCompleteYellow,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ..._matchingCustomers.map((c) {
                        return InkWell(
                          onTap: () => _applyCustomer(c),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${c.name} • ${c.phone}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: AppTheme.textWhite,
                                        ),
                                      ),
                                      if (c.address.isNotEmpty)
                                        Text(
                                          c.address,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.moneyGreen,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'USA (${c.ordersCount})',
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),

              if (_deliveryType == DeliveryType.consegna) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _addressCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Indirizzo di consegna *',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // 3. Prodotti con ricerca, filtri categoria e aggiunta 1-tap
              const Text(
                '3. PRODOTTI (TOCCA + PER AGGIUNGERE SUBITO)',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppTheme.toCompleteYellow,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.toCompleteYellow,
                    foregroundColor: Colors.black,
                  ),
                  onPressed:
                  menu.isEmpty ? null : () => _openTegliaBuilder(menu),
                  icon: const Icon(Icons.crop_square_rounded),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('COMPONI TEGLIA / MEZZA TEGLIA'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Cerca pizza, fritto o bevanda...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: categories.map((cat) {
                    final sel = _selectedCategory == cat.$1;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat.$2),
                        selected: sel,
                        selectedColor: AppTheme.toCompleteYellow,
                        labelStyle: TextStyle(
                          color: sel ? Colors.black : AppTheme.textWhite,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (_) =>
                            setState(() => _selectedCategory = cat.$1),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),

              ...productList.map((item) {
                final isAvailable = item.isAvailableOnDate(_scheduledDateTime);
                final qtyInCart = _countInCart(item.name);
                final priceText = item.price == null
                    ? 'Da confermare'
                    : (!item.priceConfirmed
                    ? '€ ${item.price!.toStringAsFixed(2)} (?)'
                    : '€ ${item.price!.toStringAsFixed(2)}');

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    enabled: isAvailable,
                    onTap:
                    isAvailable ? () => _addMenuItemDialog(item) : null,
                    title: Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textWhite,
                      ),
                    ),
                    subtitle: Text(
                      !isAvailable
                          ? 'Disponibile solo Martedì e Mercoledì'
                          : '$priceText • Tocca per varianti',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: !isAvailable
                            ? AppTheme.toStartRed
                            : AppTheme.moneyGreen,
                      ),
                    ),
                    trailing: !isAvailable
                        ? null
                        : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (qtyInCart > 0) ...[
                          IconButton(
                            constraints: const BoxConstraints(
                                minWidth: 36, minHeight: 36),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.remove_circle_outline,
                                color: AppTheme.toStartRed),
                            onPressed: () =>
                                _decrementSimpleItem(item.name),
                          ),
                          Text(
                            '$qtyInCart',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: AppTheme.toCompleteYellow,
                            ),
                          ),
                        ],
                        IconButton(
                          tooltip: 'Aggiungi subito 1',
                          constraints: const BoxConstraints(
                              minWidth: 38, minHeight: 38),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.add_circle,
                              size: 28, color: AppTheme.moneyGreen),
                          onPressed: () => _quickAddItem(item),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 16),

              // 4. Pagamento e Note
              const Text(
                '4. PAGAMENTO E NOTE',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppTheme.toCompleteYellow,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<PaymentMethod>(
                value: _paymentMethod,
                decoration:
                const InputDecoration(labelText: 'Metodo di pagamento'),
                items: PaymentMethod.values
                    .map(
                      (m) => DropdownMenuItem(value: m, child: Text(m.label)),
                )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _paymentMethod = v);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Già pagato dal cliente',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  _isPaid
                      ? 'Il rider NON deve incassare'
                      : 'Da incassare (verrà conteggiato al completamento)',
                  style: TextStyle(
                    color: _isPaid
                        ? AppTheme.moneyGreen
                        : AppTheme.toCompleteYellow,
                  ),
                ),
                value: _isPaid,
                activeColor: AppTheme.moneyGreen,
                onChanged: (v) => setState(() => _isPaid = v),
              ),
              TextField(
                controller: _notesCtrl,
                decoration:
                const InputDecoration(labelText: 'Note aggiuntive ordine'),
              ),
            ],
          );
        },
      ),
    );
  }
}