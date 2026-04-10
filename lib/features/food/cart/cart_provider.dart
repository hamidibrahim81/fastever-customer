import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ Added for Auth Check

/// 🔹 Model representing a single item in the cart
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

  /// Convert CartItem to Map for Firestore
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

  /// Create CartItem from Firestore Map
  factory CartItem.fromMap(Map<String, dynamic> map) {
    return CartItem(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Unknown',
      price: (map['price'] ?? 0).toDouble(),
      restaurantId: map['restaurantId'] ?? '',
      image: map['image'],
      quantity: (map['quantity'] ?? 1) as int,
      isInstaHub: map['isInstaHub'] ?? false,
    );
  }
}

/// 🔹 Provider to manage cart state with Firestore sync
class CartProvider with ChangeNotifier {
  
  // ✅ FIX: No userId in constructor. We listen to Auth changes dynamically.
  CartProvider() {
    _initAuthListener();
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Local state
  final Map<String, CartItem> _items = {};
  
  // Subscriptions
  StreamSubscription? _cartSubscription;
  StreamSubscription? _authSubscription;

  /// Helper to get current User ID safely
  String? get _userId => _auth.currentUser?.uid;

  /// Get all items
  Map<String, CartItem> get items => {..._items};

  /// Number of distinct items
  int get distinctItemCount => _items.length;

  /// Total quantity
  int get totalItems => _items.values.fold(0, (sum, item) => sum + item.quantity);

  /// Total price
  double get totalAmount => _items.values
      .fold(0.0, (sum, item) => sum + (item.price * item.quantity));

  /// Check if cart is empty
  bool get isEmpty => _items.isEmpty;

  /// Check if cart is not empty
  bool get isNotEmpty => !isEmpty;

  /// 🔹 Initialize Auth Listener (Auto-detect Login/Logout)
  void _initAuthListener() {
    // Listen to Login/Logout events
    _authSubscription = _auth.authStateChanges().listen((User? user) {
      // 1. Always cancel old cart subscription first
      _cartSubscription?.cancel();
      
      // 2. Clear local data to prevent showing old user's cart
      _items.clear();

      if (user != null) {
        // 3. User is Logged In -> Subscribe to their Firestore Cart
        _subscribeToCart(user.uid);
      } else {
        // 4. User Logged Out -> Notify UI that cart is empty
        notifyListeners();
      }
    });
  }

  /// 🔹 Internal: Subscribe to Firestore for a specific User ID
  void _subscribeToCart(String uid) {
    _cartSubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('cart')
        .snapshots()
        .listen((snapshot) {
      _items.clear();
      for (var doc in snapshot.docs) {
        _items[doc.id] = CartItem.fromMap(doc.data());
      }
      notifyListeners();
    }, onError: (e) {
      if (kDebugMode) print("❌ Error listening to cart: $e");
    });
  }

  /// 🔹 Add item to cart
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
    if (uid == null) {
      if (kDebugMode) print("⚠️ Cannot add item: User not logged in.");
      return; // Stop if not logged in
    }

    try {
      final docRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('cart')
          .doc(id);

      if (_items.containsKey(id)) {
        // Item exists: update quantity
        _items[id]!.quantity += qty;
        await docRef.update({'quantity': _items[id]!.quantity});
      } else {
        // New item: add to Firestore
        final newItem = CartItem(
          id: id,
          name: name,
          price: price,
          restaurantId: restaurantId,
          image: image,
          quantity: qty,
          isInstaHub: isInstaHub,
        );
        // Optimistically update local state for speed
        _items[id] = newItem; 
        await docRef.set(newItem.toMap());
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print("❌ Error adding item: $e");
    }
  }

  /// 🔹 Reduce quantity by 1
  Future<void> reduceQuantity(String id) async {
    final uid = _userId;
    if (uid == null || !_items.containsKey(id)) return;

    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('cart')
        .doc(id);

    if (_items[id]!.quantity > 1) {
      _items[id]!.quantity -= 1;
      await docRef.update({'quantity': _items[id]!.quantity});
    } else {
      _items.remove(id);
      await docRef.delete();
    }
    notifyListeners();
  }

  /// 🔹 Remove a specific item completely
  Future<void> removeItem(String id) async {
    final uid = _userId;
    if (uid == null || !_items.containsKey(id)) return;

    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('cart')
        .doc(id);

    _items.remove(id);
    await docRef.delete();
    notifyListeners();
  }

  /// 🔹 Update item quantity directly
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
    if (uid == null) return;

    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('cart')
        .doc(id);

    if (qty <= 0) {
      _items.remove(id);
      await docRef.delete();
    } else {
      // Create temp item if not exists locally, just to save
      final item = _items[id] ?? CartItem(
        id: id, name: name, price: price, restaurantId: restaurantId, image: image, isInstaHub: isInstaHub
      );
      item.quantity = qty;
      _items[id] = item;
      await docRef.set(item.toMap());
    }
    notifyListeners();
  }

  /// 🔹 Clear the entire cart
  Future<void> clearCart() async {
    final uid = _userId;
    if (uid == null) return;

    // 1. Immediately clear local state to update UI
    _items.clear();
    notifyListeners();

    // 2. Clear Firestore in the background
    try {
      final batch = _firestore.batch();
      final cartCollection = _firestore.collection('users').doc(uid).collection('cart');

      var snapshots = await cartCollection.get();
      for (var doc in snapshots.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
    } catch (e) {
      if (kDebugMode) print("Error clearing Firestore cart: $e");
    }
  }

  /// 🔹 Get quantity of a specific item
  int getQuantity(String id) => _items[id]?.quantity ?? 0;

  /// 🔹 Dispose Subscriptions
  @override
  void dispose() {
    _cartSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}