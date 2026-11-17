class Order {
  final int? id;
  final int userId;
  final double totalAmount;
  final String status; // pending, completed, cancelled
  final DateTime createdAt;

  Order({
    this.id,
    required this.userId,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
  });

  factory Order.fromMap(Map<String, dynamic> map) => Order(
        id: map['id'] as int?,
        userId: map['userId'] as int,
        totalAmount: (map['totalAmount'] as num).toDouble(),
        status: map['status'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'totalAmount': totalAmount,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
      };
}

class OrderItem {
  final int? id;
  final int orderId;
  final int productId;
  final int quantity;
  final double price;

  OrderItem({
    this.id,
    required this.orderId,
    required this.productId,
    required this.quantity,
    required this.price,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
        id: map['id'] as int?,
        orderId: map['orderId'] as int,
        productId: map['productId'] as int,
        quantity: map['quantity'] as int,
        price: (map['price'] as num).toDouble(),
      );
}

class Product {
  final int? id;
  final String name;
  final double price;
  final int stock;

  Product({
    this.id,
    required this.name,
    required this.price,
    required this.stock,
  });

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as int?,
        name: map['name'] as String,
        price: (map['price'] as num).toDouble(),
        stock: map['stock'] as int,
      );
}

class OrderItemRequest {
  final int productId;
  final int quantity;

  OrderItemRequest({required this.productId, required this.quantity});
}
