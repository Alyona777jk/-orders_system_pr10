import 'package:sqflite/sqflite.dart';
import '../database/orders_database.dart';
import '../models/models.dart';

class OrderService {
  final OrdersDatabase _db = OrdersDatabase.instance;

  Future<List<Product>> getProducts() async {
    final db = await _db.database;
    final maps = await db.query('products', orderBy: 'id ASC');
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<List<Order>> getOrders() async {
    final db = await _db.database;
    final maps = await db.query('orders', orderBy: 'id DESC');
    return maps.map((m) => Order.fromMap(m)).toList();
  }

  // ТРАНЗАКЦІЯ 1: Створення замовлення з перевіркою залишків і rollback при помилці
  Future<int?> createOrder(int userId, List<OrderItemRequest> items) async {
    if (items.isEmpty) return null;
    final db = await _db.database;

    try {
      return await db.transaction((txn) async {
        double totalAmount = 0;
        final Map<int, double> productPrices = {};

        // 1. Перевірка наявності товарів та підрахунок суми
        for (var item in items) {
          final product = await txn.query(
            'products',
            where: 'id = ?',
            whereArgs: [item.productId],
          );

          if (product.isEmpty) {
            throw Exception('Товар ID ${item.productId} не знайдено');
          }

          final stock = product.first['stock'] as int;
          final price = (product.first['price'] as num).toDouble();

          if (stock < item.quantity) {
            throw Exception(
              'Недостатньо товару "${product.first['name']}" (доступно: $stock, потрібно: ${item.quantity})',
            );
          }

          productPrices[item.productId] = price;
          totalAmount += price * item.quantity;
        }

        // 2. Створення запису замовлення
        final orderId = await txn.insert('orders', {
          'userId': userId,
          'totalAmount': totalAmount,
          'status': 'pending',
          'createdAt': DateTime.now().toIso8601String(),
        });

        // 3. Додавання позицій та оновлення залишків на складі
        for (var item in items) {
          await txn.insert('order_items', {
            'orderId': orderId,
            'productId': item.productId,
            'quantity': item.quantity,
            'price': productPrices[item.productId],
          });

          await txn.rawUpdate(
            'UPDATE products SET stock = stock - ? WHERE id = ?',
            [item.quantity, item.productId],
          );
        }

        return orderId;
      });
    } catch (e) {
      // При будь-якому throw всередині db.transaction SQLite автоматично робить ROLLBACK
      rethrow;
    }
  }

  // ТРАНЗАКЦІЯ 2: Скасування замовлення з поверненням товару на склад
  Future<bool> cancelOrder(int orderId) async {
    final db = await _db.database;
    try {
      return await db.transaction((txn) async {
        final order = await txn.query('orders', where: 'id = ?', whereArgs: [orderId]);
        if (order.isEmpty || order.first['status'] == 'cancelled') {
          return false;
        }

        final items = await txn.query(
          'order_items',
          where: 'orderId = ?',
          whereArgs: [orderId],
        );

        for (var item in items) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ? WHERE id = ?',
            [item['quantity'], item['productId']],
          );
        }

        await txn.update(
          'orders',
          {'status': 'cancelled'},
          where: 'id = ?',
          whereArgs: [orderId],
        );

        return true;
      });
    } catch (e) {
      return false;
    }
  }

  // BATCH 1: Додати множину items одночасно (наприклад, поповнення складу або додавання товарів)
  Future<void> batchAddProducts(List<Map<String, dynamic>> newProducts) async {
    final db = await _db.database;
    Batch batch = db.batch();
    for (var prod in newProducts) {
      batch.insert('products', prod);
    }
    await batch.commit(noResult: true);
  }

  // BATCH 2: Оновити статус множини замовлень
  Future<void> updateOrdersStatus(List<int> orderIds, String status) async {
    final db = await _db.database;
    Batch batch = db.batch();
    for (var orderId in orderIds) {
      batch.update(
        'orders',
        {'status': status},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    }
    await batch.commit(noResult: true);
  }

  // BATCH 3: Видалити старі виконані замовлення (CASCADE автоматично видалить order_items)
  Future<int> deleteOldOrders(DateTime before) async {
    final db = await _db.database;
    final oldOrders = await db.query(
      'orders',
      columns: ['id'],
      where: 'createdAt < ? AND status = ?',
      whereArgs: [before.toIso8601String(), 'completed'],
    );

    if (oldOrders.isEmpty) return 0;

    Batch batch = db.batch();
    for (var row in oldOrders) {
      batch.delete('orders', where: 'id = ?', whereArgs: [row['id']]);
    }
    await batch.commit(noResult: true);
    return oldOrders.length;
  }

  // ЗВІТ 1: Деталі замовлення
  Future<Map<String, dynamic>?> getOrderDetails(int orderId) async {
    final db = await _db.database;
    final orderData = await db.rawQuery('''
      SELECT o.*, COUNT(oi.id) as itemsCount
      FROM orders o
      LEFT JOIN order_items oi ON o.id = oi.orderId
      WHERE o.id = ?
      GROUP BY o.id
    ''', [orderId]);

    if (orderData.isEmpty) return null;

    final items = await db.rawQuery('''
      SELECT oi.*, p.name as productName
      FROM order_items oi
      INNER JOIN products p ON oi.productId = p.id
      WHERE oi.orderId = ?
    ''', [orderId]);

    return {
      'order': orderData.first,
      'items': items,
    };
  }

  // ЗВІТ 2: Найпопулярніші продукти (серед виконаних замовлень)
  Future<List<Map<String, dynamic>>> getTopProducts(int limit) async {
    final db = await _db.database;
    return await db.rawQuery('''
      SELECT p.*, SUM(oi.quantity) as totalSold
      FROM products p
      INNER JOIN order_items oi ON p.id = oi.productId
      INNER JOIN orders o ON oi.orderId = o.id
      WHERE o.status = 'completed'
      GROUP BY p.id
      ORDER BY totalSold DESC
      LIMIT ?
    ''', [limit]);
  }

  // ЗВІТ 3: Загальна статистика продажів
  Future<Map<String, dynamic>> getSalesStats() async {
    final db = await _db.database;
    final totalRevenue = await db.rawQuery('''
      SELECT SUM(totalAmount) as revenue
      FROM orders
      WHERE status = 'completed'
    ''');

    final ordersCount = await db.rawQuery('''
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
        SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) as cancelled
      FROM orders
    ''');

    return {
      'revenue': (totalRevenue.first['revenue'] as num?)?.toDouble() ?? 0.0,
      'orders': ordersCount.first,
    };
  }
}
