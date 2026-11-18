
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Model representing a single item in the cart.
class CartItem {
  final String id;
  final String name;
  final double price;
  final String restaurantId;
  final String? image;
  final bool isInstaHub;
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    required this.price,
    required this.restaurantId,
    this.image,
    this.quantity = 1,
    this.isInstaHub = false,
  });

  /// Convert CartItem to Map for Firestore.
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

  /// Create CartItem from Firestore Map.
  factory CartItem.fromMap(Map<String, dynamic> map) {
    return CartItem(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unknown',
      price: _parseDouble(map['price']),
      restaurantId: map['restaurantId']?.toString() ?? '',
      image: map['image']?.toString(),
      quantity: _parseInt(map['quantity'], fallback: 1),
      isInstaHub: map['isInstaHub'] == true,
    );
  }

  /// Create a copy with updated values.
  CartItem copyWith({
    String? name,
    double? price,
    String? restaurantId,
    String? image,
    int? quantity,
    bool? isInstaHub,
  }) {
    return CartItem(
      id: id,
      name: name ?? this.name,
      price: price ?? this.price,
      restaurantId: restaurantId ?? this.restaurantId,
      image: image ?? this.image,
      quantity: quantity ?? this.quantity,
      isInstaHub: isInstaHub ?? this.isInstaHub,
    );
  }

  static double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

/// Provider to manage cart state with Firestore sync.
class CartProvider with ChangeNotifier {
  CartProvider() {
    _initAuthListener();
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Local cart state.
  final Map<String, CartItem> _items = {};

  // Subscriptions.
  StreamSubscription? _cartSubscription;
  StreamSubscription? _authSubscription;

  bool _isDisposed = false;

  /// Current user ID.
  String? get _userId => _auth.currentUser?.uid;

  /// Get all cart items.
  Map<String, CartItem> get items => Map.unmodifiable(_items);

  /// Number of distinct items.
  int get distinctItemCount => _items.length;

  /// Total quantity.
  int get totalItems =>
      _items.values.fold(0, (sum, item) => sum + item.quantity);

  /// Total cart amount using the latest locally stored prices.
  double get totalAmount => _items.values.fold(
        0.0,
        (sum, item) => sum + (item.price * item.quantity),
      );

  /// Check if cart is empty.
  bool get isEmpty => _items.isEmpty;

  /// Check if cart is not empty.
  bool get isNotEmpty => !isEmpty;

  /// Safely notify listeners.
  void _notifyListenersSafely() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Initialize authentication listener.
  void _initAuthListener() {
    _authSubscription = _auth.authStateChanges().listen((User? user) async {
      // Cancel the previous user's cart subscription.
      await _cartSubscription?.cancel();
      _cartSubscription = null;

      // Clear previous user's local cart.
      _items.clear();
      _notifyListenersSafely();

      if (_isDisposed) return;

      if (user != null) {
        _subscribeToCart(user.uid);
      }
    });
  }

  /// Subscribe to Firestore cart for a specific user.
  void _subscribeToCart(String uid) {
    _cartSubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('cart')
        .snapshots()
        .listen(
      (snapshot) {
        // Do not apply an old user's data after an account switch.
        if (_isDisposed || _userId != uid) return;

        _items.clear();

        for (final doc in snapshot.docs) {
          try {
            _items[doc.id] = CartItem.fromMap(doc.data());
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Error reading cart item ${doc.id}: $e');
            }
          }
        }

        _notifyListenersSafely();
      },
      onError: (e) {
        if (kDebugMode) {
          debugPrint('Error listening to cart: $e');
        }
      },
    );
  }

  /// Add item to cart.
  Future<void> addItem({
    required String id,
    required String name,
    required double price,
    required String restaurantId,
    String? image,
    int qty = 1,
    bool isInstaHub = false,
  }) async {
    final uid = _userId;

    if (uid == null || qty <= 0 || _isDisposed) {
      if (kDebugMode && uid == null) {
        debugPrint('Cannot add item: User not logged in.');
      }
      return;
    }

    try {
      final docRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('cart')
          .doc(id);

      if (_items.containsKey(id)) {
        final existingItem = _items[id]!;

        final updatedItem = existingItem.copyWith(
          quantity: existingItem.quantity + qty,
        );

        _items[id] = updatedItem;

        _notifyListenersSafely();

        await docRef.update({
          'quantity': updatedItem.quantity,
        });
      } else {
        final newItem = CartItem(
          id: id,
          name: name,
          price: price,
          restaurantId: restaurantId,
          image: image,
          quantity: qty,
          isInstaHub: isInstaHub,
        );

        // Optimistically update local state.
        _items[id] = newItem;
        _notifyListenersSafely();

        await docRef.set(newItem.toMap());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error adding item: $e');
      }
    }
  }

  /// Reduce quantity by one.
  Future<void> reduceQuantity(String id) async {
    final uid = _userId;

    if (uid == null || !_items.containsKey(id) || _isDisposed) return;

    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('cart')
        .doc(id);

    final existingItem = _items[id]!;

    try {
      if (existingItem.quantity > 1) {
        final updatedItem = existingItem.copyWith(
          quantity: existingItem.quantity - 1,
        );

        _items[id] = updatedItem;
        _notifyListenersSafely();

        await docRef.update({
          'quantity': updatedItem.quantity,
        });
      } else {
        _items.remove(id);
        _notifyListenersSafely();

        await docRef.delete();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error reducing cart quantity: $e');
      }
    }
  }

  /// Remove a specific item completely.
  Future<void> removeItem(String id) async {
    final uid = _userId;

    if (uid == null || !_items.containsKey(id) || _isDisposed) return;

    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('cart')
        .doc(id);

    final removedItem = _items.remove(id);
    _notifyListenersSafely();

    try {
      await docRef.delete();
    } catch (e) {
      // Restore the item if the Firestore operation failed.
      if (removedItem != null && !_isDisposed && _userId == uid) {
        _items[id] = removedItem;
        _notifyListenersSafely();
      }

      if (kDebugMode) {
        debugPrint('Error removing cart item: $e');
      }
    }
  }

  /// Update item quantity directly.
  Future<void> updateItem({
    required String id,
    required String name,
    required double price,
    required String restaurantId,
    String? image,
    required int qty,
    bool isInstaHub = false,
  }) async {
    final uid = _userId;

    if (uid == null || _isDisposed) return;

    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('cart')
        .doc(id);

    try {
      if (qty <= 0) {
        _items.remove(id);
        _notifyListenersSafely();

        await docRef.delete();
      } else {
        final existingItem = _items[id];

        final item = existingItem != null
            ? existingItem.copyWith(
                quantity: qty,
                name: name,
                price: price,
                restaurantId: restaurantId,
                image: image,
                isInstaHub: isInstaHub,
              )
            : CartItem(
                id: id,
                name: name,
                price: price,
                restaurantId: restaurantId,
                image: image,
                quantity: qty,
                isInstaHub: isInstaHub,
              );

        _items[id] = item;
        _notifyListenersSafely();

        await docRef.set(item.toMap());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error updating cart item: $e');
      }
    }
  }

  /// Update the price of one existing cart item.
  ///
  /// Call this after fetching the current price from the relevant
  /// restaurant/menu document in Firestore.
  ///
  /// Returns true when the local and Firestore cart price are updated.
  Future<bool> updateItemPrice({
    required String id,
    required double price,
  }) async {
    final uid = _userId;

    if (uid == null || _isDisposed || price < 0) return false;

    final existingItem = _items[id];
    if (existingItem == null) return false;

    if (existingItem.price == price) return true;

    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('cart')
        .doc(id);

    final previousItem = existingItem;

    // Update locally so the displayed total changes immediately.
    _items[id] = existingItem.copyWith(price: price);
    _notifyListenersSafely();

    try {
      await docRef.update({
        'price': price,
      });

      return true;
    } catch (e) {
      // Restore only if the same user is still active and the item
      // has not been changed again in the meantime.
      if (!_isDisposed && _userId == uid) {
        final currentItem = _items[id];

        if (currentItem != null && currentItem.price == price) {
          _items[id] = previousItem;
          _notifyListenersSafely();
        }
      }

      if (kDebugMode) {
        debugPrint('Error updating cart item price: $e');
      }

      return false;
    }
  }

  /// Update multiple cart item prices together.
  ///
  /// Example:
  /// {
  ///   'menuItemId1': 149.0,
  ///   'menuItemId2': 99.0,
  /// }
  ///
  /// Prices must first be fetched and validated against the actual
  /// menu documents by the CartScreen.
  Future<bool> updateItemPrices(Map<String, double> updatedPrices) async {
    final uid = _userId;

    if (uid == null || _isDisposed || updatedPrices.isEmpty) {
      return false;
    }

    final validPrices = <String, double>{};

    for (final entry in updatedPrices.entries) {
      if (entry.value < 0) continue;

      if (_items.containsKey(entry.key) &&
          _items[entry.key]!.price != entry.value) {
        validPrices[entry.key] = entry.value;
      }
    }

    if (validPrices.isEmpty) return true;

    final previousItems = <String, CartItem>{};

    for (final entry in validPrices.entries) {
      final existingItem = _items[entry.key]!;

      previousItems[entry.key] = existingItem;
      _items[entry.key] = existingItem.copyWith(
        price: entry.value,
      );
    }

    // Update displayed prices and totals immediately.
    _notifyListenersSafely();

    final batch = _firestore.batch();

    for (final entry in validPrices.entries) {
      final docRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('cart')
          .doc(entry.key);

      batch.update(docRef, {
        'price': entry.value,
      });
    }

    try {
      await batch.commit();
      return true;
    } catch (e) {
      // Restore previous prices if the batch fails.
      if (!_isDisposed && _userId == uid) {
        for (final entry in previousItems.entries) {
          final currentItem = _items[entry.key];

          if (currentItem != null &&
              currentItem.price == validPrices[entry.key]) {
            _items[entry.key] = entry.value;
          }
        }

        _notifyListenersSafely();
      }

      if (kDebugMode) {
        debugPrint('Error updating cart item prices: $e');
      }

      return false;
    }
  }

  /// Clear the entire cart.
  Future<void> clearCart() async {
    final uid = _userId;

    if (uid == null || _isDisposed) return;

    // Immediately clear local state.
    _items.clear();
    _notifyListenersSafely();

    try {
      final cartCollection = _firestore
          .collection('users')
          .doc(uid)
          .collection('cart');

      // Delete in batches to avoid Firestore batch limits.
      while (true) {
        if (_userId != uid || _isDisposed) return;

        final snapshot = await cartCollection.limit(450).get();

        if (snapshot.docs.isEmpty) break;

        final batch = _firestore.batch();

        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();

        if (snapshot.docs.length < 450) break;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error clearing Firestore cart: $e');
      }
    }
  }

  /// Get quantity of a specific item.
  int getQuantity(String id) => _items[id]?.quantity ?? 0;

  /// Dispose subscriptions.
  @override
  void dispose() {
    _isDisposed = true;

    _cartSubscription?.cancel();
    _authSubscription?.cancel();

    super.dispose();
  }
}
