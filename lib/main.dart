import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/models.dart';
import 'services/order_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OrdersApp());
}

class OrdersApp extends StatelessWidget {
  const OrdersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ПР №10: Система замовлень',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final OrderService _service = OrderService();
  int _tabIndex = 0;

  List<Product> _products = [];
  List<Order> _orders = [];
  final Map<int, int> _cart = {}; // productId -> quantity
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _topProducts = [];

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    final products = await _service.getProducts();
    final orders = await _service.getOrders();
    final stats = await _service.getSalesStats();
    final top = await _service.getTopProducts(5);

    setState(() {
      _products = products;
      _orders = orders;
      _stats = stats;
      _topProducts = top;
    });
  }

  void _showMsg(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  Future<void> _submitOrder() async {
    if (_cart.isEmpty) {
      _showMsg('Кошик порожній!', isError: true);
      return;
    }

    final items = _cart.entries
        .map((e) => OrderItemRequest(productId: e.key, quantity: e.value))
        .toList();

    try {
      final orderId = await _service.createOrder(1, items);
      setState(() => _cart.clear());
      await _refreshAll();
      _showMsg('Замовлення #$orderId успішно створено (транзакція COMMIT)');
    } catch (e) {
      _showMsg('ROLLBACK транзакції: ${e.toString().replaceAll('Exception: ', '')}', isError: true);
    }
  }

  // Демонстрація атомарності та Rollback: перший товар є в наявності, другого не вистачає
  Future<void> _testRollbackTransaction() async {
    if (_products.length < 2) return;
    final p1 = _products[0];
    final p2 = _products[1];

    try {
      await _service.createOrder(1, [
        OrderItemRequest(productId: p1.id!, quantity: 1),
        OrderItemRequest(productId: p2.id!, quantity: p2.stock + 50), // Перевищуємо залишок
      ]);
    } catch (e) {
      await _refreshAll();
      _showMsg(
        'Тест Rollback успішний! Залишок "${p1.name}" не змінився. Помилка: ${e.toString().replaceAll('Exception: ', '')}',
        isError: true,
      );
    }
  }

  Future<void> _showOrderDetailsDialog(int orderId) async {
    final details = await _service.getOrderDetails(orderId);
    if (details == null || !mounted) return;

    final order = details['order'] as Map<String, dynamic>;
    final items = details['items'] as List<Map<String, dynamic>>;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Замовлення #${order['id']} (${order['status']})'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Дата: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(order['createdAt']))}'),
              Text('Позицій: ${order['itemsCount']}'),
              const Divider(),
              ...items.map((item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(item['productName']),
                    subtitle: Text('${item['quantity']} шт. × ${item['price']} ₴'),
                    trailing: Text('${(item['quantity'] * item['price']).toStringAsFixed(2)} ₴'),
                  )),
              const Divider(),
              Text(
                'Разом: ${order['totalAmount']} ₴',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ),
        actions: [
          if (order['status'] != 'cancelled')
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final ok = await _service.cancelOrder(orderId);
                await _refreshAll();
                if (ok) _showMsg('Замовлення #$orderId скасовано, товари повернуто на склад');
              },
              child: const Text('Скасувати замовлення', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрити'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildCatalogTab(),
      _buildOrdersTab(),
      _buildReportsTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Система замовлень (SQLite)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
            tooltip: 'Оновити дані',
          ),
        ],
      ),
      body: pages[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) {
          setState(() => _tabIndex = idx);
          _refreshAll();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.store), label: 'Товари'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Замовлення'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Звіти'),
        ],
      ),
    );
  }

  Widget _buildCatalogTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testRollbackTransaction,
                  icon: const Icon(Icons.warning_amber, color: Colors.orange),
                  label: const Text('Тест Rollback (нестача товару)', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await _service.batchAddProducts([
                    {'name': 'Веб-камера HD', 'price': 1850.0, 'stock': 10},
                    {'name': 'Килимок для миші', 'price': 450.0, 'stock': 30},
                  ]);
                  await _refreshAll();
                  _showMsg('Batch: додано 2 нові товари на склад');
                },
                icon: const Icon(Icons.playlist_add),
                label: const Text('Batch +товари', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _products.length,
            itemBuilder: (context, index) {
              final p = _products[index];
              final inCart = _cart[p.id] ?? 0;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Ціна: ${p.price} ₴ | На складі: ${p.stock} шт.'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: inCart > 0
                            ? () => setState(() {
                                  if (inCart == 1) {
                                    _cart.remove(p.id);
                                  } else {
                                    _cart[p.id!] = inCart - 1;
                                  }
                                })
                            : null,
                      ),
                      Text('$inCart', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => setState(() => _cart[p.id!] = inCart + 1),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_cart.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Обрано позицій: ${_cart.values.fold(0, (a, b) => a + b)} шт.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                FilledButton.icon(
                  onPressed: _submitOrder,
                  icon: const Icon(Icons.check),
                  label: const Text('Оформити замовлення'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildOrdersTab() {
    final pendingIds = _orders.where((o) => o.status == 'pending').map((o) => o.id!).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: pendingIds.isEmpty
                      ? null
                      : () async {
                          await _service.updateOrdersStatus(pendingIds, 'completed');
                          await _refreshAll();
                          _showMsg('Batch: ${pendingIds.length} замовлень переведено в completed');
                        },
                  icon: const Icon(Icons.done_all),
                  label: Text('Виконати всі (${pendingIds.length})'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  // Видаляємо виконані замовлення, створені до поточного моменту (для демонстрації)
                  final deleted = await _service.deleteOldOrders(DateTime.now().add(const Duration(seconds: 1)));
                  await _refreshAll();
                  _showMsg('Batch: видалено старих виконаних замовлень: $deleted');
                },
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                label: const Text('Очистити виконані'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _orders.isEmpty
              ? const Center(child: Text('Замовлень ще немає'))
              : ListView.builder(
                  itemCount: _orders.length,
                  itemBuilder: (context, index) {
                    final o = _orders[index];
                    Color statusColor = Colors.orange;
                    if (o.status == 'completed') statusColor = Colors.green;
                    if (o.status == 'cancelled') statusColor = Colors.red;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        onTap: () => _showOrderDetailsDialog(o.id!),
                        title: Text('Замовлення #${o.id} — ${o.totalAmount.toStringAsFixed(2)} ₴'),
                        subtitle: Text(DateFormat('dd.MM.yyyy HH:mm:ss').format(o.createdAt)),
                        trailing: Chip(
                          label: Text(o.status, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          backgroundColor: statusColor,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReportsTab() {
    final revenue = (_stats['revenue'] as double?) ?? 0.0;
    final counts = (_stats['orders'] as Map<String, dynamic>?) ?? {};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.indigo.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Загальна виручка (completed)', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  '${revenue.toStringAsFixed(2)} ₴',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.indigo),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statBadge('Всього', '${counts['total'] ?? 0}', Colors.black87),
                    _statBadge('Pending', '${counts['pending'] ?? 0}', Colors.orange),
                    _statBadge('Completed', '${counts['completed'] ?? 0}', Colors.green),
                    _statBadge('Cancelled', '${counts['cancelled'] ?? 0}', Colors.red),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Найпопулярніші продукти (ТОП-5)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_topProducts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Немає завершених замовлень. Переведіть замовлення у статус "completed" на вкладці Замовлення.'),
            ),
          )
        else
          ..._topProducts.map((p) => Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.star)),
                  title: Text(p['name']),
                  subtitle: Text('Ціна: ${p['price']} ₴ | Залишок: ${p['stock']} шт.'),
                  trailing: Text(
                    'Продано: ${p['totalSold']} шт.',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ),
              )),
      ],
    );
  }

  Widget _statBadge(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
