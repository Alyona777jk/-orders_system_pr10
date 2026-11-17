import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class OrdersDatabase {
  static final OrdersDatabase instance = OrdersDatabase._init();
  static Database? _database;

  OrdersDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('orders_pr10.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        // Обов'язково для підтримки ON DELETE CASCADE у SQLite
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        stock INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL,
        totalAmount REAL NOT NULL,
        status TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderId INTEGER NOT NULL,
        productId INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        price REAL NOT NULL,
        FOREIGN KEY (orderId) REFERENCES orders (id) ON DELETE CASCADE,
        FOREIGN KEY (productId) REFERENCES products (id)
      )
    ''');

    // Індекси для оптимізації запитів
    await db.execute('CREATE INDEX idx_order_user ON orders (userId)');
    await db.execute('CREATE INDEX idx_item_order ON order_items (orderId)');
    await db.execute('CREATE INDEX idx_item_product ON order_items (productId)');

    // Тестові товари на складі
    await db.insert('products', {'name': 'Ноутбук Pro 15', 'price': 42000.0, 'stock': 5});
    await db.insert('products', {'name': 'Бездротова миша', 'price': 1200.0, 'stock': 15});
    await db.insert('products', {'name': 'Механічна клавіатура', 'price': 3500.0, 'stock': 8});
    await db.insert('products', {'name': 'Монітор 27" 4K', 'price': 16500.0, 'stock': 3});
    await db.insert('products', {'name': 'USB-C Хаб', 'price': 950.0, 'stock': 20});
  }
}
