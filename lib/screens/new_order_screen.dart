import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class NewOrderScreen extends StatefulWidget {
  final DateTime initialDate;

  const NewOrderScreen({super.key, required this.initialDate});

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
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

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().add(const Duration(minutes: 30));
    _scheduledDateTime = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
      now.hour,
      now.minute,
    );
  }

  @override
  void dispose() {
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

  void _setQuickMinutesFromNow(int minutes) {
    final target = DateTime.now().add(Duration(minutes: minutes));
    setState(() {
      _scheduledDateTime = DateTime(
        widget.initialDate.year,
        widget.initialDate.month,
        widget.initialDate.day,
        target.hour,
        target.minute,
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
        if (newSource != OrderSource.diretto) {
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
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
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
      backgroundColor: AppTheme.backgroundWhite,
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
                          color: AppTheme.brickBrownDark,
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
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.terracottaPrimary,
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
                                color: AppTheme.brickBrownDark,
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
                                  selectedColor: AppTheme.terracottaPrimary,
                                  labelStyle: TextStyle(
                                    color: isSel
                                        ? Colors.white
                                        : AppTheme.textDarkBrown,
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
                                color: AppTheme.brickBrownDark,
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
                                  selectedColor: AppTheme.ovenOrangeAccent,
                                  labelStyle: TextStyle(
                                    color: isSel
                                        ? Colors.white
                                        : AppTheme.textDarkBrown,
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
                          child: Text(
                            'AGGIUNGI TEGLIA (€ ${currentPrice.toStringAsFixed(2)})',
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
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Prezzo da confermare a listino. Inserisci l\'importo:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.brickBrownDark,
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
                        onPressed: qty > 1
                            ? () => setDlgState(() => qty--)
                            : null,
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

  void _openCartSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.backgroundWhite,
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
                    Text(
                      'Carrello ($_cartItemsCount articoli)',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.brickBrownDark,
                      ),
                    ),
                    Text(
                      '€ ${_cartTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.terracottaPrimary,
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
                          title: Text(
                            '${item.quantity}x ${item.name}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle:
                          details.isNotEmpty ? Text(details) : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '€ ${item.subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: AppTheme.delayAlertRed),
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

    const categories = [
      ('tutte', 'Tutti'),
      ('pizza_tonda', 'Pizze Tonde'),
      ('fritti', 'Fritti'),
      ('bevande', 'Bevande'),
      ('speciale_giorno', 'Speciali Mar/Mer'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Nuovo Ordine Veloce')),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: const BoxDecoration(
          color: AppTheme.warmSurface,
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
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_bag_outlined,
                          color: AppTheme.terracottaPrimary),
                      const SizedBox(width: 6),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_cartItemsCount pz • Vedi',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMutedBrown,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '€ ${_cartTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.brickBrownDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveOrder,
                    icon: _isSaving
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      _isSaving ? 'SALVATAGGIO...' : 'SALVA ORDINE',
                      style: const TextStyle(fontSize: 16),
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
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            children: [
              // 1. Provenienza e tipo consegna
              const Text(
                '1. PROVENIENZA E SERVIZIO',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppTheme.brickBrownDark,
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
                      color: sel ? Colors.white : AppTheme.textDarkBrown,
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
                      label: Text('Ritiro al banco'),
                    ),
                  ],
                  selected: {_deliveryType},
                  onSelectionChanged: (val) =>
                      setState(() => _deliveryType = val.first),
                ),
              ],

              const SizedBox(height: 18),

              // 2. Orario rapido + Dati cliente
              const Text(
                '2. ORARIO E CLIENTE',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppTheme.brickBrownDark,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.access_time,
                          size: 16, color: Colors.white),
                      label: Text(
                        '$formattedDate • $formattedTime',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: AppTheme.brickBrownDark,
                      onPressed: _pickScheduledDateTime,
                    ),
                    const SizedBox(width: 6),
                    for (final mins in [15, 30, 45, 60])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text('+$mins min'),
                          onPressed: () => _setQuickMinutesFromNow(mins),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _nameCtrl,
                      decoration:
                      const InputDecoration(labelText: 'Nome cliente *'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Telefono'),
                    ),
                  ),
                ],
              ),
              if (_deliveryType == DeliveryType.consegna) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _addressCtrl,
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
                  color: AppTheme.brickBrownDark,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.ovenOrangeAccent,
                  ),
                  onPressed:
                  menu.isEmpty ? null : () => _openTegliaBuilder(menu),
                  icon: const Icon(Icons.crop_square_rounded),
                  label: const Text('COMPONI TEGLIA / MEZZA TEGLIA'),
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
                        selectedColor: AppTheme.terracottaPrimary,
                        labelStyle: TextStyle(
                          color: sel ? Colors.white : AppTheme.textDarkBrown,
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
                    enabled: isAvailable,
                    onTap:
                    isAvailable ? () => _addMenuItemDialog(item) : null,
                    title: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      !isAvailable
                          ? 'Disponibile solo Martedì e Mercoledì'
                          : '$priceText • Tocca per varianti/note',
                      style: TextStyle(
                        fontSize: 12,
                        color: !isAvailable
                            ? AppTheme.delayAlertRed
                            : AppTheme.textMutedBrown,
                      ),
                    ),
                    trailing: !isAvailable
                        ? null
                        : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (qtyInCart > 0) ...[
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                color: AppTheme.brickBrownDark),
                            onPressed: () =>
                                _decrementSimpleItem(item.name),
                          ),
                          Text(
                            '$qtyInCart',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: AppTheme.terracottaPrimary,
                            ),
                          ),
                        ],
                        IconButton(
                          tooltip: 'Aggiungi subito 1',
                          icon: const Icon(Icons.add_circle,
                              size: 30,
                              color: AppTheme.terracottaPrimary),
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
                  color: AppTheme.brickBrownDark,
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
                ),
                value: _isPaid,
                activeColor: AppTheme.paidGreen,
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