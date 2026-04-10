import 'package:flutter/material.dart';

class MorningCartProvider extends ChangeNotifier {
  final Map<String, Map<String, dynamic>> _items = {};

  Map<String, Map<String, dynamic>> get items => _items;

  // ✅ 100% READY: Fixed floating point precision for financial accuracy
  double get totalAmount {
    double total = 0.0;
    _items.forEach((key, item) {
      // Safely handle both int and double from Firestore
      final double price = (item['price'] as num).toDouble();
      final int quantity = (item['quantity'] as num).toInt();
      total += (price * quantity);
    });
    // Parse to fixed 2 decimals to prevent .99999999 errors in payment gateways
    return double.parse(total.toStringAsFixed(2));
  }

  int get itemCount => _items.length;

  int getQuantity(String id) {
    if (_items.containsKey(id)) {
      // Ensure we return an int even if Firestore sends it as a double
      return (_items[id]!['quantity'] as num).toInt();
    }
    return 0;
  }

  void addItem({
    required String id,
    required String name,
    required double price,
    required String restaurantId,
    required String image,
  }) {
    // 🛡️ Security Check: Prevent adding items with corrupted negative prices
    if (price < 0) return;

    if (_items.containsKey(id)) {
      _items.update(id, (existing) {
        return {
          ...existing,
          'quantity': (existing['quantity'] as int) + 1,
        };
      });
    } else {
      _items[id] = {
        'id': id,
        'name': name,
        'price': price,
        'restaurantId': restaurantId,
        'quantity': 1,
        'image': image,
      };
    }
    notifyListeners();
  }

  void reduceQuantity(String id) {
    if (!_items.containsKey(id)) return;

    final int currentQuantity = (_items[id]!['quantity'] as num).toInt();

    if (currentQuantity > 1) {
      _items.update(id, (existing) {
        return {
          ...existing,
          'quantity': currentQuantity - 1,
        };
      });
    } else {
      _items.remove(id);
    }
    notifyListeners();
  }

  void removeItem(String id) {
    if (_items.containsKey(id)) {
      _items.remove(id);
      notifyListeners();
    }
  }

  /// ✅ Clears all items in the cart (used after order placed)
  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  /// Optional: keep backward compatibility
  void clear() => clearCart();
}