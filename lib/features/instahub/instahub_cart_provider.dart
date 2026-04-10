import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 🔹 Instahub Cart Item Model
class InstahubCartItem {
  final String id;
  final String name;
  final double price;
  final String restaurantId; // kept for Firestore schema consistency
  final String? image;
  int quantity;
  final bool isInstaHub;

  InstahubCartItem({
    required this.id,
    required this.name,
    required this.price,
    this.restaurantId = 'instahub_store',
    this.image,
    this.quantity = 1,
    this.isInstaHub = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'restaurantId': restaurantId,
      'image': image,
      'quantity': quantity,
      'isInstaHub': isInstaHub,
    };
  }

  factory InstahubCartItem.fromMap(Map<String, dynamic> map) {
    return InstahubCartItem(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Unknown',
      price: (map['price'] ?? 0).toDouble(),
      restaurantId: map['restaurantId'] ?? 'instahub_store',
      image: map['image'],
      quantity: (map['quantity'] ?? 1).clamp(1, 999),
      isInstaHub: map['isInstaHub'] ?? true,
    );
  }
}

/// 🔹 Instahub Cart Provider (Audited for Play Store)
class InstahubCartProvider with ChangeNotifier {
  final String userId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, InstahubCartItem> _items = {};
  StreamSubscription? _cartSubscription;
  bool _isInitialized = false;

  InstahubCartProvider({required this.userId}) {
    _initializeCartListener();
  }

  bool get isInitialized => _isInitialized;
  Map<String, InstahubCartItem> get items => {..._items};
  int get distinctItemCount => _items.length;
  int get totalItems => _items.values.fold(0, (sum, item) => sum + item.quantity);
  double get totalAmount =>
      _items.values.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  /// 🌟 Returns a specific item from local state
  InstahubCartItem? getItem(String id) {
    return _items[id];
  }

  /// 🔸 Realtime sync with Firestore
  void _initializeCartListener() {
    _cartSubscription = _firestore
        .collection('users')
        .doc(userId)
        .collection('instahub_cart')
        .snapshots()
        .listen((snapshot) {
      _items.clear();
      for (var doc in snapshot.docs) {
        _items[doc.id] = InstahubCartItem.fromMap(doc.data()); 
      }
      _isInitialized = true;
      notifyListeners();
    }, onError: (error) {
      if (kDebugMode) print("⚠️ Instahub Cart Listener Error: $error");
    });
  }

  /// 🔹 Add item (instant local update + async Firestore write)
  Future<void> addItem({
    required String id,
    required String name,
    required double price,
    String restaurantId = 'instahub_store',
    String? image,
    int quantity = 1,
  }) async {
    try {
      if (_items.containsKey(id)) {
        await updateItem(
          id: id,
          name: name,
          price: price,
          restaurantId: restaurantId,
          image: image,
          quantity: _items[id]!.quantity + quantity,
        );
      } else {
        await updateItem(
          id: id,
          name: name,
          price: price,
          restaurantId: restaurantId,
          image: image,
          quantity: quantity,
        );
      }
    } catch (e) {
      if (kDebugMode) print("❌ Error adding Instahub item: $e");
    }
  }

  /// 🔹 Update item quantity and price (Optimistic UI)
  Future<void> updateItem({
    required String id,
    required String name,
    required double price,
    String restaurantId = 'instahub_store',
    String? image,
    required int quantity,
  }) async {
    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('instahub_cart')
          .doc(id);
          
      if (quantity <= 0) {
        _items.remove(id);
        notifyListeners();
        await docRef.delete();
      } else {
        _items[id] = InstahubCartItem(
          id: id,
          name: name,
          price: price,
          restaurantId: restaurantId,
          image: image,
          quantity: quantity,
        );
        notifyListeners();
        await docRef.set(_items[id]!.toMap());
      }
    } catch (e) {
      if (kDebugMode) print("❌ Error updating Instahub item: $e");
    }
  }

  /// 🔹 Reduce quantity by one
  Future<void> reduceQuantity(String id) async {
    if (!_items.containsKey(id)) return;

    final item = _items[id]!;
    if (item.quantity > 1) {
      item.quantity -= 1;
      notifyListeners();
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('instahub_cart')
          .doc(id)
          .update({'quantity': item.quantity});
    } else {
      await removeItem(id);
    }
  }

  /// 🔹 Remove item entirely
  Future<void> removeItem(String id) async {
    if (!_items.containsKey(id)) return;

    _items.remove(id);
    notifyListeners();

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('instahub_cart')
        .doc(id)
        .delete();
  }

  /// 🔹 Clear entire cart with high-performance batch commit
  Future<void> clearCart() async {
    try {
      final cartRef =
          _firestore.collection('users').doc(userId).collection('instahub_cart');
      final snapshots = await cartRef.get();
      final batch = _firestore.batch();

      for (var doc in snapshots.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      _items.clear();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print("❌ Error clearing Instahub cart: $e");
    }
  }

  int getQuantity(String id) => _items[id]?.quantity ?? 0;

  @override
  void dispose() {
    _cartSubscription?.cancel();
    super.dispose();
  }
}