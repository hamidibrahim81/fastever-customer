
import 'package:fastevergo_v1/features/food/address/address_model.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'order_confirmation_screen.dart';
import 'cart/cart_provider.dart';
import 'cart/AddressFlow.dart';
import 'cart/ManageAddressScreen.dart';

// ===============================================
// HELPER FUNCTIONS
// ===============================================

double parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value is String) return double.tryParse(value) ?? defaultValue;
  if (value is num) return value.toDouble();
  return defaultValue;
}

int parseInt(dynamic value, {int defaultValue = 0}) {
  if (value is String) return int.tryParse(value) ?? defaultValue;
  if (value is num) return value.toInt();
  return defaultValue;
}

// ===============================================
// DATA MODEL: Delivery Settings
// ===============================================

class DeliverySettings {
  final double baseFee;
  final int baseKm;
  final int maxDistance;
  final double perKmFee;
  final double platformFee;

  DeliverySettings({
    required this.baseFee,
    required this.baseKm,
    required this.maxDistance,
    required this.perKmFee,
    required this.platformFee,
  });

  factory DeliverySettings.fromFirestore(Map<String, dynamic> data) {
    return DeliverySettings(
      baseFee: parseDouble(data['baseFee']),
      baseKm: parseInt(data['baseKm']),
      maxDistance: parseInt(data['maxDistance']),
      perKmFee: parseDouble(data['perKmFee']),
      platformFee: parseDouble(data['platformFee']),
    );
  }
}

class FeeBreakdown {
  final double deliveryCharge;
  final double platformFee;
  final double totalFee;
  final double maxDistanceKm;
  final bool isDeliveryAvailable;

  FeeBreakdown({
    required this.deliveryCharge,
    required this.platformFee,
    required this.totalFee,
    required this.maxDistanceKm,
    this.isDeliveryAvailable = true,
  });

  static FeeBreakdown get zero => FeeBreakdown(
        deliveryCharge: 0.0,
        platformFee: 0.0,
        totalFee: 0.0,
        maxDistanceKm: 0.0,
        isDeliveryAvailable: true,
      );

  static FeeBreakdown outOfRange(double maxDist) => FeeBreakdown(
        deliveryCharge: 0.0,
        platformFee: 0.0,
        totalFee: 0.0,
        maxDistanceKm: maxDist,
        isDeliveryAvailable: false,
      );
}

// ===============================================
// CartScreen Widget
// ===============================================

class CartScreen extends StatefulWidget {
  final Position? userPosition;

  const CartScreen({super.key, this.userPosition});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String selectedAddress = "Loading address...";
  String selectedPayment = "COD";
  String? appliedCoupon;
  double discountAmount = 0;

  double _tipAmount = 0;
  final TextEditingController _customTipController = TextEditingController();
  bool _isCustomTip = false;

  Position? currentPosition;
  Position? currentDeliveryPosition;

  DeliverySettings? _deliverySettings;

  Future<FeeBreakdown> _cachedFeesFuture =
      Future.value(FeeBreakdown.zero);

  CartProvider? _cartProvider;
  bool _isListenerAdded = false;

  final TextEditingController _couponController =
      TextEditingController();

  final TextEditingController _instructionController =
      TextEditingController();

  bool _isCheckingStock = false;
  bool _isPlacingOrder = false;
  bool _initialPriceRefreshStarted = false;

  // Prevent overlapping price refresh requests.
  bool _isRefreshingPrices = false;

  // ===============================================
  // CART PRICE REFRESH + STOCK VALIDATION
  // ===============================================

  /// Checks the latest menu documents for every cart item.
  ///
  /// The current menu price is read from the Firestore field `price`.
  /// Updated prices are saved into the customer's Firestore cart.
  ///
  /// If any price changes, checkout is stopped so the customer can
  /// review the updated total before trying again.
  Future<bool> _refreshCartPricesAndCheckStock() async {
    final cart = _cartProvider;

    if (cart == null || cart.isEmpty) {
      return false;
    }

    if (_isRefreshingPrices) {
      return false;
    }

    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      _showSnackBar(
        "Please login again to continue.",
        color: Colors.red,
      );
      return false;
    }

    _isRefreshingPrices = true;

    if (mounted) {
      setState(() => _isCheckingStock = true);
    }

    try {
      // Take a snapshot so the list remains stable during the reads.
      final cartItems = cart.items.values.toList();

      if (cartItems.isEmpty) {
        return false;
      }

      // Fetch all menu documents concurrently instead of sequentially.
      final futures = cartItems.map((item) {
        return _firestore
            .collection('restaurants')
            .doc(item.restaurantId)
            .collection('menu')
            .doc(item.id)
            .get();
      }).toList();

      final documents = await Future.wait(futures);

      if (!mounted || _auth.currentUser?.uid != uid) {
        return false;
      }

      final updatedPrices = <String, double>{};
      final unavailableItems = <String>[];
      final outOfStockItems = <String>[];

      for (int i = 0; i < cartItems.length; i++) {
        final item = cartItems[i];
        final doc = documents[i];

        // A deleted or unavailable menu item must not be ordered.
        if (!doc.exists || doc.data() == null) {
          unavailableItems.add(item.name);
          continue;
        }

        final data = doc.data()!;

        // Do not silently replace a price with zero if the price
        // field is missing or invalid.
        if (!data.containsKey('price')) {
          unavailableItems.add(item.name);
          continue;
        }

        final dynamic rawPrice = data['price'];

        final double? currentPrice = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '');

        if (currentPrice == null ||
            !currentPrice.isFinite ||
            currentPrice < 0) {
          unavailableItems.add(item.name);
          continue;
        }

        // Check the latest stock.
        final int currentStock = parseInt(data['stock']);

        if (item.quantity > currentStock) {
          outOfStockItems.add(
            "${item.name} (only $currentStock left)",
          );
        }

        // Compare current Firestore price with the saved cart price.
        if ((item.price - currentPrice).abs() > 0.001) {
          updatedPrices[item.id] = currentPrice;
        }
      }

      if (!mounted || _auth.currentUser?.uid != uid) {
        return false;
      }

      // Update all changed prices in the cart provider and Firestore.
      bool priceChanged = false;

      if (updatedPrices.isNotEmpty) {
        final success = await cart.updateItemPrices(updatedPrices);

        if (!success) {
          _showSnackBar(
            "Unable to refresh item prices. Please try again.",
            color: Colors.red,
          );
          return false;
        }

        priceChanged = true;

        // A previous coupon discount may no longer be correct
        // after the cart subtotal changes.
        if (mounted) {
          setState(() {
            appliedCoupon = null;
            discountAmount = 0;
            _couponController.clear();
          });
        }

        final changedNames = cartItems
            .where((item) => updatedPrices.containsKey(item.id))
            .map((item) => item.name)
            .toList();

        _showSnackBar(
          "Item prices have changed: ${changedNames.join(', ')}. Please review your updated total.",
          color: Colors.orange,
        );
      }

      if (unavailableItems.isNotEmpty) {
        _showSnackBar(
          "Some items are no longer available: ${unavailableItems.join(', ')}. Please remove them from your cart.",
          color: Colors.red,
        );
        return false;
      }

      if (outOfStockItems.isNotEmpty) {
        _showSnackBar(
          "Insufficient stock: ${outOfStockItems.join(', ')}",
          color: Colors.red,
        );
        return false;
      }

      // Important: if prices changed during checkout, stop here.
      // The customer must review the new total and tap Place Order again.
      if (priceChanged) {
        return false;
      }

      return true;
    } catch (e, stackTrace) {
      debugPrint("Cart price/stock validation error: $e");
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _showSnackBar(
          "Unable to verify item prices and stock. Please try again.",
          color: Colors.red,
        );
      }

      return false;
    } finally {
      _isRefreshingPrices = false;

      if (mounted) {
        setState(() => _isCheckingStock = false);
      }
    }
  }

  /// Retained stock-check method.
  /// It also verifies current prices before allowing checkout.
  Future<bool> _isStockAvailable() async {
    return _refreshCartPricesAndCheckStock();
  }

  // ===============================================
  // INITIALIZATION
  // ===============================================

  @override
  void initState() {
    super.initState();

    final user = _auth.currentUser;

    if (user != null) {
      _loadSavedAddress(user.uid);
    } else {
      selectedAddress = "No address saved yet";
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isListenerAdded) {
      _cartProvider = Provider.of<CartProvider>(
        context,
        listen: false,
      );

      _cartProvider!.addListener(_onCartChange);
      _isListenerAdded = true;

      _cachedFeesFuture = _calculateTotalFees();

      // Refresh prices when the cart screen is first opened.
      if (!_initialPriceRefreshStarted) {
        _initialPriceRefreshStarted = true;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          unawaited(_refreshCartPricesAndCheckStock());
        });
      }
    }
  }

  void _onCartChange() {
    if (!mounted) return;

    setState(() {
      _cachedFeesFuture = _calculateTotalFees();
    });
  }

  @override
  void dispose() {
    if (_isListenerAdded && _cartProvider != null) {
      _cartProvider!.removeListener(_onCartChange);
    }

    _couponController.dispose();
    _instructionController.dispose();
    _customTipController.dispose();

    super.dispose();
  }

  // ===============================================
  // LOCATION
  // ===============================================

  Future<void> _initUserLocation() async {
    if (currentPosition != null) return;

    try {
      final bool serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        throw Exception("Location services are disabled.");
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception("Location permission is denied.");
      }

      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() => currentPosition = pos);
      }
    } catch (e) {
      debugPrint("Error getting device location: $e");
    }
  }

  // ===============================================
  // DELIVERY SETTINGS
  // ===============================================

  Future<void> _loadDeliverySettings() async {
    if (_deliverySettings != null) return;

    try {
      final doc = await _firestore
          .collection('deliverySettings')
          .doc('instahub')
          .get();

      if (doc.exists && doc.data() != null) {
        final settings =
            DeliverySettings.fromFirestore(doc.data()!);

        if (mounted) {
          setState(() {
            _deliverySettings = settings;
          });
        } else {
          _deliverySettings = settings;
        }
      }
    } catch (e) {
      debugPrint("Error loading delivery settings: $e");
    }
  }

  double _calculateDeliveryCharge(double distanceKm) {
    final settings = _deliverySettings!;

    const double geoCorrectionFee = 3.0;

    if (distanceKm > settings.maxDistance) {
      return 0.0;
    }

    double deliveryCharge = 0.0;

    if (distanceKm <= settings.baseKm) {
      deliveryCharge = settings.baseFee;
    } else {
      deliveryCharge = settings.baseFee +
          ((distanceKm - settings.baseKm) *
              settings.perKmFee);
    }

    return deliveryCharge + geoCorrectionFee;
  }

  // ===============================================
  // SAVED ADDRESS
  // ===============================================

  Future<void> _loadSavedAddress(String uid) async {
    try {
      final doc = await _firestore
          .collection("users")
          .doc(uid)
          .collection("profile")
          .doc("address")
          .get();

      if (!mounted) return;

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        final double savedLat =
            parseDouble(data['latitude']);

        final double savedLon =
            parseDouble(data['longitude']);

        final String fullAddress =
            "${data['name'] ?? ''}\n"
            "${data['phone'] ?? ''}\n"
            "${data['address'] ?? ''}\n"
            "${data['landmark'] ?? ''}";

        setState(() {
          selectedAddress = fullAddress.trim().isEmpty
              ? "No address saved yet"
              : fullAddress.trim();

          if (savedLat != 0.0 && savedLon != 0.0) {
            currentDeliveryPosition = Position(
              latitude: savedLat,
              longitude: savedLon,
              timestamp: DateTime.now(),
              accuracy: 1,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              altitudeAccuracy: 1,
              headingAccuracy: 1,
            );

            _cachedFeesFuture = _calculateTotalFees();
          }
        });

        return;
      }

      // Fallback to the most recent order address.
      final lastOrderQuery = await _firestore
          .collection("orders")
          .where("userId", isEqualTo: uid)
          .orderBy("timestamp", descending: true)
          .limit(1)
          .get();

      if (!mounted) return;

      if (lastOrderQuery.docs.isNotEmpty) {
        final orderData =
            lastOrderQuery.docs.first.data();

        final double oLat = parseDouble(
          orderData['deliveryLatitude'] ??
              orderData['latitude'],
        );

        final double oLon = parseDouble(
          orderData['deliveryLongitude'] ??
              orderData['longitude'],
        );

        final String oAddr =
            (orderData['address'] ?? '').toString();

        if (oAddr.isNotEmpty) {
          setState(() {
            selectedAddress = oAddr;

            if (oLat != 0.0 && oLon != 0.0) {
              currentDeliveryPosition = Position(
                latitude: oLat,
                longitude: oLon,
                timestamp: DateTime.now(),
                accuracy: 1,
                altitude: 0,
                heading: 0,
                speed: 0,
                speedAccuracy: 0,
                altitudeAccuracy: 1,
                headingAccuracy: 1,
              );

              _cachedFeesFuture = _calculateTotalFees();
            }
          });

          return;
        }
      }

      setState(() {
        selectedAddress = "No address saved yet";
      });
    } catch (e) {
      debugPrint("Error loading saved address: $e");

      if (mounted) {
        setState(() {
          selectedAddress = "No address saved yet";
        });
      }
    }
  }

  // ===============================================
  // DISTANCE CALCULATION - PARALLEL READS
  // ===============================================

  Future<Map<String, double>> _getDistancesForCart(
    CartProvider cartProvider,
    Position userPos,
  ) async {
    final restaurantIds = cartProvider.items.values
        .map((item) => item.restaurantId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    double maxDistanceKm = 0.0;

    if (restaurantIds.isEmpty) {
      return {'maxDistanceKm': 0.0};
    }

    // Fetch restaurant documents concurrently.
    final documents = await Future.wait(
      restaurantIds.map(
        (rId) => _firestore
            .collection('restaurants')
            .doc(rId)
            .get(),
      ),
    );

    for (final doc in documents) {
      if (!doc.exists || doc.data() == null) continue;

      final data = doc.data()!;

      final double rlat = parseDouble(data['latitude']);
      final double rlon = parseDouble(data['longitude']);

      if (rlat == 0.0 || rlon == 0.0) continue;

      final double distanceInMeters =
          Geolocator.distanceBetween(
        userPos.latitude,
        userPos.longitude,
        rlat,
        rlon,
      );

      final double distanceKm =
          distanceInMeters / 1000.0;

      if (distanceKm > maxDistanceKm) {
        maxDistanceKm = distanceKm;
      }
    }

    return {'maxDistanceKm': maxDistanceKm};
  }

  // ===============================================
  // TOTAL DELIVERY FEE
  // ===============================================

  Future<FeeBreakdown> _calculateTotalFees() async {
    await _loadDeliverySettings();

    if (!mounted) return FeeBreakdown.zero;

    if (_deliverySettings == null) {
      return FeeBreakdown.zero;
    }

    final cartProvider = _cartProvider;

    if (cartProvider == null || cartProvider.items.isEmpty) {
      return FeeBreakdown.zero;
    }

    Position? userPos =
        currentDeliveryPosition ?? widget.userPosition;

    if (userPos == null) {
      await _initUserLocation();

      if (!mounted) return FeeBreakdown.zero;

      userPos = currentPosition;
    }

    if (userPos == null) {
      return FeeBreakdown.zero;
    }

    final distances = await _getDistancesForCart(
      cartProvider,
      userPos,
    );

    if (!mounted) return FeeBreakdown.zero;

    final maxDistanceKm =
        distances['maxDistanceKm'] ?? 0.0;

    final settings = _deliverySettings!;

    if (maxDistanceKm > settings.maxDistance) {
      return FeeBreakdown.outOfRange(maxDistanceKm);
    }

    final double deliveryCharge =
        _calculateDeliveryCharge(maxDistanceKm);

    return FeeBreakdown(
      deliveryCharge: deliveryCharge,
      platformFee: settings.platformFee,
      totalFee: deliveryCharge + settings.platformFee,
      maxDistanceKm: maxDistanceKm,
    );
  }

  // ===============================================
  // CHECKOUT
  // ===============================================

  Future<void> _navigateToOrderConfirmation(
    double subtotal,
    double discount,
    double totalFees,
  ) async {
    if (_isPlacingOrder || _isCheckingStock) return;
    if (_isCustomTip && (double.tryParse(_customTipController.text.trim()) ?? 0) > 1000) {
      _showSnackBar("Maximum custom tip is \u20B91,000.");
      return;
    }

    final cartProvider = _cartProvider;

    if (cartProvider == null || cartProvider.isEmpty) {
      _showSnackBar(
        "Your cart is empty.",
        color: Colors.red,
      );
      return;
    }

    setState(() {
      _isPlacingOrder = true;
    });

    try {
      // Verify current prices and stock immediately before checkout.
      final bool stockAndPriceOk =
          await _isStockAvailable();

      if (!mounted || !stockAndPriceOk) return;

      final double? deliveryLat =
          currentDeliveryPosition?.latitude;

      final double? deliveryLon =
          currentDeliveryPosition?.longitude;

      if (deliveryLat == null ||
          deliveryLon == null ||
          (deliveryLat == 0.0 && deliveryLon == 0.0)) {
        _showSnackBar(
          "Please select a precise delivery location.",
          color: Colors.red,
        );
        return;
      }

      // Recalculate fees using the current cart and address.
      final breakdown = await _calculateTotalFees();

      if (!mounted) return;

      setState(() {
        _cachedFeesFuture = Future.value(breakdown);
      });

      if (!breakdown.isDeliveryAvailable) {
        _showSnackBar(
          "Delivery unavailable for this distance.",
          color: Colors.red,
        );
        return;
      }

      // Read the latest cart state after all asynchronous checks.
      final latestItems = cartProvider.items.values.toList();

      if (latestItems.isEmpty) {
        _showSnackBar(
          "Your cart is empty.",
          color: Colors.red,
        );
        return;
      }

      final double latestSubtotal =
          cartProvider.totalAmount;

      final double latestDiscount =
          discountAmount.clamp(0.0, latestSubtotal).toDouble();

      final List<Map<String, dynamic>> cartItems =
          latestItems.map((item) {
        return {
          "name": item.name,
          "price": item.price,
          "quantity": item.quantity,
          "id": item.id,
          "image": item.image,
          "restaurantId": item.restaurantId,
        };
      }).toList();

      final double latestTotal =
          latestSubtotal +
          breakdown.totalFee +
          _tipAmount -
          latestDiscount;

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OrderConfirmationScreen(
            items: cartItems,
            subtotal: latestSubtotal,
            discount: latestDiscount,
            total: latestTotal,
            address: selectedAddress,
            payment: selectedPayment,
            deliveryFee: breakdown.deliveryCharge,
            platformFee: breakdown.platformFee,
            appliedCouponCode: appliedCoupon,
            deliveryLatitude: deliveryLat,
            deliveryLongitude: deliveryLon,
            deliveryInstructions: _checkoutDeliveryInstructions(),
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint("Checkout error: $e");
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _showSnackBar(
          "Unable to continue checkout. Please try again.",
          color: Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPlacingOrder = false;
        });
      }
    }
  }

  // ===============================================
  // ADDRESS SELECTION
  // ===============================================

  Future<void> _showAddressSelectionScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ManageAddressScreen(),
      ),
    );

    if (!mounted) return;

    if (result != null && result is Map<String, dynamic>) {
      final double newLat = parseDouble(result['lat']);
      final double newLon = parseDouble(result['lng']);

      if (newLat == 0.0 && newLon == 0.0) {
        _showSnackBar(
          "Please select a valid delivery location.",
          color: Colors.red,
        );
        return;
      }

      final String fullAddress =
          "${result['recipient_name'] ?? ''}\n"
          "${result['phone'] ?? ''}\n"
          "${result['house_no'] ?? ''}, "
          "${result['street_area'] ?? ''}\n"
          "${result['landmark'] ?? ''}\n"
          "${result['full_display_address'] ?? ''}"
              .trim();

      setState(() {
        selectedAddress = fullAddress;

        currentDeliveryPosition = Position(
          latitude: newLat,
          longitude: newLon,
          timestamp: DateTime.now(),
          accuracy: 1,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 1,
          headingAccuracy: 1,
        );

        _cachedFeesFuture = _calculateTotalFees();
      });

      // Persist the selected address for future sessions.
      final user = _auth.currentUser;

      if (user != null) {
        try {
          await _firestore
              .collection("users")
              .doc(user.uid)
              .collection("profile")
              .doc("address")
              .set({
            'name': result['recipient_name'] ?? '',
            'phone': result['phone'] ?? '',
            'address':
                "${result['house_no'] ?? ''}, "
                "${result['street_area'] ?? ''}".trim(),
            'landmark':
                "${result['landmark'] ?? ''} "
                "${result['full_display_address'] ?? ''}".trim(),
            'latitude': newLat,
            'longitude': newLon,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint("Error saving address: $e");
        }
      }
    }
  }

  // ===============================================
  // SNACKBAR
  // ===============================================

  void _showSnackBar(
    String message, {
    Color color = Colors.red,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  // ===============================================
  // COUPON
  // ===============================================

  Future<void> _applyCoupon(double subtotal) async {
    final code = _couponController.text.trim();

    if (code.isEmpty) return;

    try {
      final snapshot = await _firestore
          .collection('coupons')
          .where('name', isEqualTo: code)
          .limit(1)
          .get();

      if (!mounted) return;

      if (snapshot.docs.isEmpty) {
        _showSnackBar('Invalid coupon');
        return;
      }

      final data = snapshot.docs.first.data();

      final double value = parseDouble(data['value']);

      final double calculatedDiscount =
          data['type'] == 'percentage'
              ? subtotal * (value / 100.0)
              : value;

      setState(() {
        appliedCoupon = code;

        // Discount cannot exceed the current subtotal.
        discountAmount = calculatedDiscount
            .clamp(0.0, subtotal)
            .toDouble();
      });

      _showSnackBar(
        "Coupon applied!",
        color: Colors.green,
      );
    } catch (e) {
      debugPrint("Coupon error: $e");

      _showSnackBar('Error applying coupon');
    }
  }

  // ===============================================
  // BUILD
  // ===============================================

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FeeBreakdown>(
      future: _cachedFeesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState ==
                ConnectionState.waiting &&
            !_isCheckingStock) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: Colors.orange,
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios,
                color: Colors.black,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              "My Cart",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: true,
          ),
          body: Consumer<CartProvider>(
            builder: (context, cart, child) {
              if (cart.isEmpty) {
                return _buildEmptyCart();
              }

              final breakdown =
                  snapshot.data ?? FeeBreakdown.zero;

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    if (!breakdown.isDeliveryAvailable)
                      _buildOutOfRangeWarning(
                        breakdown.maxDistanceKm,
                      ),
                    _buildSectionTitle("Cart Items"),
                    _buildCartItems(
                      cart.items.values.toList(),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle(
                      "Delivery Instructions",
                    ),
                    _buildInstructionsField(),
                    const SizedBox(height: 24),
                    _buildSectionTitle("Tip Your Delivery Partner"),
                    _buildTipSelector(),
                    const SizedBox(height: 24),
                    _buildSectionTitle("Order Summary"),
                    _buildTotals(
                      cart.totalAmount,
                      breakdown,
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle("Delivery Address"),
                    _buildAddressCard(),
                    const SizedBox(height: 24),
                    _buildSectionTitle("Apply Coupon"),
                    _buildCouponSection(cart.totalAmount),
                    const SizedBox(height: 24),
                    _buildSectionTitle("Payment Method"),
                    _buildPaymentCard(),
                    const SizedBox(height: 120),
                  ],
                ),
              );
            },
          ),
          bottomSheet: _buildBottomCheckout(snapshot.data),
        );
      },
    );
  }

  // ===============================================
  // UI COMPONENTS
  // ===============================================

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          const Text(
            "Your cart is empty",
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12.0,
        top: 8.0,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildCartItems(List<CartItem> items) {
    final cart = _cartProvider;

    if (cart == null) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.grey.shade100,
        ),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (context, index) {
          return Divider(
            height: 1,
            color: Colors.grey.shade100,
          );
        },
        itemBuilder: (context, index) {
          final item = items[index];

          return ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                item.image ?? "",
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) {
                  return Container(
                    width: 60,
                    height: 60,
                    color: Colors.grey.shade100,
                    child: const Icon(Icons.fastfood),
                  );
                },
              ),
            ),
            title: Text(
              item.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              "\u20B9${item.price.toStringAsFixed(2)}",
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
            trailing: Container(
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.remove,
                      size: 18,
                      color: Colors.orange,
                    ),
                    onPressed: _isPlacingOrder ||
                            _isCheckingStock
                        ? null
                        : () => cart.reduceQuantity(item.id),
                  ),
                  Text(
                    "${item.quantity}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add,
                      size: 18,
                      color: Colors.orange,
                    ),
                    onPressed: _isPlacingOrder ||
                            _isCheckingStock
                        ? null
                        : () => cart.addItem(
                              id: item.id,
                              name: item.name,
                              price: item.price,
                              restaurantId: item.restaurantId,
                              image: item.image,
                              isInstaHub: item.isInstaHub,
                            ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInstructionsField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: TextField(
        controller: _instructionController,
        maxLines: 2,
        decoration: const InputDecoration(
          hintText:
              "Add a note for the delivery partner...",
          contentPadding: EdgeInsets.all(12),
          border: InputBorder.none,
          hintStyle: TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  // Tip is voluntary and is not included in the delivery/platform fee.
  // The existing confirmation constructor has no separate tipAmount field,
  // so the tip is included in the final total and explicitly recorded in
  // deliveryInstructions until the confirmation/order model is upgraded.
  String _checkoutDeliveryInstructions() {
    final note = _instructionController.text.trim();
    if (_tipAmount <= 0) return note;
    final tipNote = 'Delivery partner tip: \u20B9${_tipAmount.toStringAsFixed(2)}';
    return note.isEmpty ? tipNote : '$note\n$tipNote';
  }

  void _selectTip(double amount) {
    if (_isPlacingOrder || _isCheckingStock) return;
    setState(() {
      _tipAmount = _tipAmount == amount && !_isCustomTip ? 0 : amount;
      _isCustomTip = false;
      _customTipController.clear();
    });
  }

  void _selectCustomTip() {
    if (_isPlacingOrder || _isCheckingStock) return;
    setState(() {
      _isCustomTip = !_isCustomTip;
      _tipAmount = 0;
      if (!_isCustomTip) _customTipController.clear();
    });
  }

  void _updateCustomTip(String value) {
    final amount = double.tryParse(value.trim());
    setState(() {
      _tipAmount = amount != null && amount.isFinite && amount > 0
          ? amount.clamp(0.0, 1000.0).toDouble()
          : 0;
    });
  }

  Widget _buildTipSelector() {
    const amounts = [10.0, 20.0, 30.0, 50.0];
    final disabled = _isPlacingOrder || _isCheckingStock;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Say thanks with a tip',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Optional â€¢ You can choose no tip',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final amount in amounts)
                ChoiceChip(
                  label: Text('\u20B9${amount.toStringAsFixed(0)}'),
                  selected: !_isCustomTip && _tipAmount == amount,
                  onSelected: disabled ? null : (_) => _selectTip(amount),
                  selectedColor: Colors.orange.shade200,
                  backgroundColor: Colors.white,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ChoiceChip(
                label: const Text('Custom'),
                selected: _isCustomTip,
                onSelected: disabled ? null : (_) => _selectCustomTip(),
                selectedColor: Colors.orange.shade200,
                backgroundColor: Colors.white,
              ),
            ],
          ),
          if (_isCustomTip) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customTipController,
              enabled: !disabled,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: _updateCustomTip,
              decoration: InputDecoration(
                labelText: 'Custom tip amount',
                prefixText: '\u20B9 ',
                helperText: 'Maximum \u20B91,000',
                errorText: (double.tryParse(_customTipController.text) ?? 0) > 1000
                    ? 'Maximum allowed tip is \u20B91,000'
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          if (_tipAmount > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text('Added tip: \u20B9${_tipAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                TextButton(
                  onPressed: disabled ? null : () => setState(() {
                    _tipAmount = 0;
                    _isCustomTip = false;
                    _customTipController.clear();
                  }),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTotals(
    double subtotal,
    FeeBreakdown breakdown,
  ) {
    final total =
        subtotal + breakdown.totalFee + _tipAmount - discountAmount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          _buildPriceRow("Subtotal", subtotal),
          _buildPriceRow(
            "Delivery Fee",
            breakdown.deliveryCharge,
          ),
          _buildPriceRow(
            "Platform Fee",
            breakdown.platformFee,
          ),
          if (_tipAmount > 0)
            _buildPriceRow("Delivery Partner Tip", _tipAmount, color: Colors.green),
          if (discountAmount > 0)
            _buildPriceRow(
              "Discount",
              -discountAmount,
              color: Colors.green,
            ),
          const Divider(height: 24),
          _buildPriceRow(
            "Total Amount",
            total,
            isBold: true,
            fontSize: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(
    String label,
    double val, {
    bool isBold = false,
    double fontSize = 14,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
          Text(
            "\u20B9${val.toStringAsFixed(2)}",
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_on,
            color: Colors.orange,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              selectedAddress,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _isPlacingOrder
                ? null
                : _showAddressSelectionScreen,
            child: const Text(
              "Change",
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCouponSection(double subtotal) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
            ),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey.shade200,
              ),
            ),
            child: TextField(
              controller: _couponController,
              decoration: const InputDecoration(
                hintText: "Enter Coupon Code",
                border: InputBorder.none,
                hintStyle: TextStyle(fontSize: 13),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _isPlacingOrder
              ? null
              : () => _applyCoupon(subtotal),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            "Apply",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.orange.shade100,
        ),
      ),
      child: Row(
        children: const [
          Icon(
            Icons.payments_outlined,
            color: Colors.orange,
          ),
          SizedBox(width: 12),
          Text(
            "Cash on Delivery",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
          Spacer(),
          Icon(
            Icons.check_circle,
            color: Colors.orange,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCheckout(FeeBreakdown? breakdown) {
    final cart = context.watch<CartProvider>();

    if (cart.isEmpty) {
      return const SizedBox.shrink();
    }

    final total =
        (breakdown?.totalFee ?? 0) +
        cart.totalAmount +
        _tipAmount -
        discountAmount;

    final bool canCheckout =
        breakdown?.isDeliveryAvailable == true &&
        currentDeliveryPosition != null &&
        !_isCheckingStock &&
        !_isPlacingOrder;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: ElevatedButton(
          onPressed: canCheckout
              ? () => _navigateToOrderConfirmation(
                    cart.totalAmount,
                    discountAmount,
                    breakdown!.totalFee,
                  )
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            minimumSize: const Size(
              double.infinity,
              55,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            elevation: 0,
          ),
          child: _isCheckingStock || _isPlacingOrder
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  currentDeliveryPosition == null
                      ? "Select Address"
                      : "Place Order  \u20B9${total.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildOutOfRangeWarning(double dist) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.red.shade100,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Out of range (${dist.toStringAsFixed(1)}km). "
              "We only deliver up to "
              "${_deliverySettings?.maxDistance ?? 0}km.",
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
