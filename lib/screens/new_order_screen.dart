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

  late DateTime _scheduledDateTime;
  OrderSource _source = OrderSource.diretto;
  DeliveryType _deliveryType = DeliveryType.consegna;
  PaymentMethod _paymentMethod = PaymentMethod.contanti;
  bool _isPaid = false;
  String? _assignedRider;

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
    super.dispose();
  }

  double get _cartTotal =>
      _cart.fold<double>(0.0, (sum, item) => sum + item.subtotal);

  void _onSourceChanged(OrderSource newSource) {
    setState(() {
      _source = newSource;
      if (newSource == OrderSource.banco) {
        _deliveryType = DeliveryType.ritiro;
        _assignedRider = null;
      } else if (newSource == OrderSource.justEat ||
          newSource == OrderSource.glovo ||
          newSource == OrderSource.deliveroo) {
        _deliveryType = DeliveryType.consegna;
        if (newSource.isExternalCourier) {
          _assignedRider = null;
        }
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

  Future<void> _openTegliaBuilder(List<MenuItemModel> menu) async {
    final simpleFlavors =
    menu.where((m) => m.category == 'teglia_gusto_semplice' && m.available).toList();
    final specialFlavors =
    menu.where((m) => m.category == 'teglia_gusto_speciale' && m.available).toList();

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
                        'Prezzo calcolato: € ${currentPrice.toStringAsFixed(2)} (${selected.length}/${isMezza ? 2 : 4} gusti)',
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
    double? chosenPrice = item.price;
    final priceCtrl = TextEditingController(
      text: chosenPrice != null ? chosenPrice.toStringAsFixed(2) : '',
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
            title: Text(item.name),
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
                        'Attenzione: prezzo da confermare a listino. Inserisci l\'importo concordato per questo prodotto:',
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
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: qty > 1
                            ? () => setDlgState(() => qty--)
                            : null,
                      ),
                      Text(
                        '$qty',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => setDlgState(() => qty++),
                      ),
                    ],
                  ),
                  TextField(
                    controller: addCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Aggiungi ingredienti (separati da virgola)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: remCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Togli ingredienti (separati da virgola)',
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
                        content: Text('Inserisci un prezzo valido maggiore di 0'),
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
            content: Text('Inserisci l\'indirizzo per la consegna a domicilio')),
      );
      return;
    }
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aggiungi almeno un prodotto all\'ordine')),
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
        assignedRider: _assignedRider,
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
    final formattedDateTime =
    DateFormat('dd/MM/yyyy • HH:mm').format(_scheduledDateTime);

    return Scaffold(
      appBar: AppBar(title: const Text('Nuovo Ordine Veloce')),
      body: StreamBuilder<List<MenuItemModel>>(
        stream: SupabaseService.instance.watchMenu(),
        builder: (context, snapshot) {
          final menu = snapshot.data ?? [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Provenienza Ordine
              const Text(
                '1. PROVENIENZA E TIPO',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
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
              const SizedBox(height: 10),
              if (_source == OrderSource.diretto)
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

              const SizedBox(height: 18),

              // 2. Orario e Dati Cliente
              const Text(
                '2. ORARIO RICHIESTO E CLIENTE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.brickBrownDark,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickScheduledDateTime,
                icon: const Icon(Icons.access_time),
                label: Text('Giorno e Ora: $formattedDateTime'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nome cliente *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefono'),
              ),
              if (_deliveryType == DeliveryType.consegna) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Indirizzo di consegna *',
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // 3. Prodotti
              const Text(
                '3. PRODOTTI',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.brickBrownDark,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.ovenOrangeAccent,
                ),
                onPressed: menu.isEmpty ? null : () => _openTegliaBuilder(menu),
                icon: const Icon(Icons.crop_square_rounded),
                label: const Text('AGGIUNGI TEGLIA / MEZZA TEGLIA'),
              ),
              const SizedBox(height: 10),
              _buildCategorySection('Pizze Tonde', menu, 'pizza_tonda'),
              _buildCategorySection('Fritti', menu, 'fritti'),
              _buildCategorySection('Bevande', menu, 'bevande'),
              _buildCategorySection(
                'Speciali del Giorno (Solo Mar/Mer)',
                menu,
                'speciale_giorno',
              ),

              // Carrello corrente
              if (_cart.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'RIEPILOGO ORDINE',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.brickBrownDark,
                          ),
                        ),
                        const Divider(),
                        ..._cart.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final item = entry.value;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${item.quantity}x ${item.name}',
                              style:
                              const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              [
                                ...item.addedIngredients.map((e) => '+$e'),
                                ...item.removedIngredients.map((e) => '-$e'),
                                if (item.notes.isNotEmpty) item.notes,
                              ].join(', '),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '€ ${item.subtotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      color: AppTheme.delayAlertRed),
                                  onPressed: () =>
                                      setState(() => _cart.removeAt(idx)),
                                ),
                              ],
                            ),
                          );
                        }),
                        const Divider(),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'TOTALE: € ${_cartTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.terracottaPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // 4. Rider, Pagamento e Note
              const Text(
                '4. PAGAMENTO E CONSEGNA',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.brickBrownDark,
                ),
              ),
              const SizedBox(height: 8),
              if (_deliveryType == DeliveryType.consegna &&
                  _source.usesInternalRiders) ...[
                DropdownButtonFormField<String?>(
                  value: _assignedRider,
                  decoration: const InputDecoration(
                    labelText: 'Rider assegnato (opzionale ora)',
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Non assegnato')),
                    DropdownMenuItem(value: 'rider_1', child: Text('Rider 1')),
                    DropdownMenuItem(value: 'rider_2', child: Text('Rider 2')),
                  ],
                  onChanged: (v) => setState(() => _assignedRider = v),
                ),
                const SizedBox(height: 10),
              ],
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
                title: const Text(
                  'Già pagato dal cliente',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  _isPaid
                      ? 'Il rider NON deve incassare'
                      : 'Da incassare alla consegna / al banco',
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
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveOrder,
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                    'SALVA ORDINE • € ${_cartTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategorySection(
      String title,
      List<MenuItemModel> menu,
      String category,
      ) {
    final items = menu.where((m) => m.category == category).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return ExpansionTile(
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppTheme.brickBrownDark,
        ),
      ),
      children: items.map((item) {
        final isAvailableForOrderDay = item.isAvailableOnDate(_scheduledDateTime);
        final priceText = item.price == null
            ? 'Da confermare'
            : (!item.priceConfirmed
            ? '€ ${item.price!.toStringAsFixed(2)} (?)'
            : '€ ${item.price!.toStringAsFixed(2)}');

        return ListTile(
          enabled: isAvailableForOrderDay,
          title: Text(item.name),
          subtitle: !isAvailableForOrderDay
              ? const Text(
            'Disponibile solo Martedì e Mercoledì',
            style: TextStyle(color: AppTheme.delayAlertRed),
          )
              : null,
          trailing: Text(
            priceText,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: item.priceConfirmed
                  ? AppTheme.terracottaPrimary
                  : AppTheme.ovenOrangeAccent,
            ),
          ),
          onTap: isAvailableForOrderDay ? () => _addMenuItemDialog(item) : null,
        );
      }).toList(),
    );
  }
}