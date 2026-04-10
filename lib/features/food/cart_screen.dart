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

  String selectedAddress = "No address saved yet";
  String selectedPayment = "COD";
  String? appliedCoupon;
  double discountAmount = 0;

  Position? currentPosition; 
  Position? currentDeliveryPosition; 

  DeliverySettings? _deliverySettings;
  late Future<FeeBreakdown> _cachedFeesFuture;

  final TextEditingController _couponController = TextEditingController();
  final TextEditingController _instructionController = TextEditingController();

  bool _isCheckingStock = false;

  Future<bool> _isStockAvailable() async {
    final cart = Provider.of<CartProvider>(context, listen: false);
    setState(() => _isCheckingStock = true);
    try {
      for (var item in cart.items.values) {
        final doc = await _firestore
            .collection('restaurants')
            .doc(item.restaurantId)
            .collection('menu')
            .doc(item.id)
            .get();
        
        if (doc.exists) {
          int currentStock = parseInt(doc.data()?['stock']);
          if (item.quantity > currentStock) {
            _showSnackBar("Sorry, only $currentStock left for ${item.name}", color: Colors.red);
            setState(() => _isCheckingStock = false);
            return false;
          }
        }
      }
      setState(() => _isCheckingStock = false);
      return true;
    } catch (e) {
      debugPrint("Stock check error: $e");
      setState(() => _isCheckingStock = false);
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user != null) {
      _loadSavedAddress(user.uid);
    }
    _cachedFeesFuture = _calculateTotalFees();
    Provider.of<CartProvider>(context, listen: false).addListener(_onCartChange);
  }

  void _onCartChange() {
    if (mounted) {
      setState(() {
        _cachedFeesFuture = _calculateTotalFees();
      });
    }
  }

  @override
  void dispose() {
    Provider.of<CartProvider>(context, listen: false).removeListener(_onCartChange);
    _couponController.dispose();
    _instructionController.dispose(); 
    super.dispose();
  }

  Future<void> _initUserLocation() async {
    if (currentPosition != null) return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception("Location services are disabled.");
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          throw Exception("Location permissions are permanently denied.");
        }
      }
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) currentPosition = pos;
    } catch (e) {
      debugPrint("Error getting device location: $e");
    }
  }

  Future<void> _loadDeliverySettings() async {
    if (_deliverySettings != null) return;
    try {
      final doc = await _firestore.collection('deliverySettings').doc('instahub').get();
      if (doc.exists && doc.data() != null) {
        final settings = DeliverySettings.fromFirestore(doc.data()!);
        if (mounted) setState(() { _deliverySettings = settings; });
      }
    } catch (e) {
      debugPrint("🔥 Error loading delivery settings: $e");
    }
  }

  double _calculateDeliveryCharge(double distanceKm) {
    final settings = _deliverySettings!;
    const double geoCorrectionFee = 3.0; 
    if (distanceKm > settings.maxDistance) return 0.0;
    double deliveryCharge = 0.0;
    if (distanceKm <= settings.baseKm) {
      deliveryCharge = settings.baseFee;
    } else {
      deliveryCharge = settings.baseFee + ((distanceKm - settings.baseKm) * settings.perKmFee);
    }
    return deliveryCharge + geoCorrectionFee;
  }

  Future<void> _loadSavedAddress(String uid) async {
    final doc = await _firestore.collection("users").doc(uid).collection("profile").doc("address").get();
    if (doc.exists) {
      final data = doc.data()!;
      final double savedLat = parseDouble(data['latitude']);
      final double savedLon = parseDouble(data['longitude']);
      final String fullAddress = "${data['name'] ?? ''}\n${data['phone'] ?? ''}\n${data['address'] ?? ''}\n${data['landmark'] ?? ''}";

      if (mounted) {
        setState(() {
          selectedAddress = fullAddress.trim().isEmpty ? "No address saved yet" : fullAddress;
          if (savedLat != 0.0 && savedLon != 0.0) {
            currentDeliveryPosition = Position(
              latitude: savedLat, longitude: savedLon, timestamp: DateTime.now(),
              accuracy: 0.0, altitude: 0.0, heading: 0.0, speed: 0.0,
              speedAccuracy: 0.0, altitudeAccuracy: 0.0, headingAccuracy: 0.0,
            );
            _cachedFeesFuture = _calculateTotalFees();
          }
        });
      }
    }
  }

  Future<Map<String, double>> _getDistancesForCart(CartProvider cartProvider, Position userPos) async {
    final restaurantIds = cartProvider.items.values.map((item) => item.restaurantId).toSet().toList();
    double maxDistanceKm = 0.0;

    if (restaurantIds.isNotEmpty) {
      for (var rId in restaurantIds) {
        final doc = await _firestore.collection('restaurants').doc(rId).get();
        if (doc.exists) {
          final data = doc.data()!;
          final rlat = parseDouble(data['latitude']);
          final rlon = parseDouble(data['longitude']);
          if (rlat != 0.0 && rlon != 0.0) {
            double distanceInMeters = Geolocator.distanceBetween(userPos.latitude, userPos.longitude, rlat, rlon);
            double distanceKm = distanceInMeters / 1000.0;
            if (distanceKm > maxDistanceKm) maxDistanceKm = distanceKm;
          }
        }
      }
    }
    return {'maxDistanceKm': maxDistanceKm};
  }

  Future<FeeBreakdown> _calculateTotalFees() async {
    await _loadDeliverySettings();
    if (_deliverySettings == null) return FeeBreakdown.zero;
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    if (cartProvider.items.isEmpty) return FeeBreakdown.zero;

    Position? userPos = currentDeliveryPosition ?? widget.userPosition;
    if (userPos == null) {
      await _initUserLocation();
      userPos = currentPosition;
    }
    if (userPos == null) return FeeBreakdown.zero;

    final distances = await _getDistancesForCart(cartProvider, userPos);
    final maxDistanceKm = distances['maxDistanceKm'] ?? 0.0;
    final settings = _deliverySettings!;

    if (maxDistanceKm > settings.maxDistance) return FeeBreakdown.outOfRange(maxDistanceKm);

    final double deliveryCharge = _calculateDeliveryCharge(maxDistanceKm);
    return FeeBreakdown(
      deliveryCharge: deliveryCharge,
      platformFee: settings.platformFee,
      totalFee: deliveryCharge + settings.platformFee,
      maxDistanceKm: maxDistanceKm,
    );
  }

  void _navigateToOrderConfirmation(double subtotal, double discount, double totalFees) async { 
    bool stockOk = await _isStockAvailable();
    if (!stockOk) return;

    final double? deliveryLat = currentDeliveryPosition?.latitude;
    final double? deliveryLon = currentDeliveryPosition?.longitude;

    if (deliveryLat == null || deliveryLon == null || (deliveryLat == 0.0 && deliveryLon == 0.0)) {
      _showSnackBar("Please select a precise delivery location.", color: Colors.red);
      return;
    }

    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final breakdown = await _cachedFeesFuture;

    if (!breakdown.isDeliveryAvailable) {
      _showSnackBar("Delivery unavailable for this distance.", color: Colors.red);
      return;
    }

    final List<Map<String, dynamic>> cartItems = cartProvider.items.values.map((item) => {
      "name": item.name, "price": item.price, "quantity": item.quantity,
      "id": item.id, "image": item.image, "restaurantId": item.restaurantId,
    }).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderConfirmationScreen(
          items: cartItems, subtotal: subtotal, discount: discount,
          total: subtotal + breakdown.totalFee - discount, address: selectedAddress,
          payment: selectedPayment, 
          deliveryFee: breakdown.deliveryCharge, // Passed separately
          platformFee: breakdown.platformFee,   // Passed separately
          appliedCouponCode: appliedCoupon,
          deliveryLatitude: deliveryLat, deliveryLongitude: deliveryLon,
          deliveryInstructions: _instructionController.text.trim(),
        ),
      ),
    );
  }

  void _showAddressSelectionScreen() async {
    // UPDATED: Navigates to ManageAddressScreen for the new selection flow
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) =>  ManageAddressScreen()));
    if (result != null && result is Map<String, dynamic>) {
      final double newLat = parseDouble(result['lat']);
      final double newLon = parseDouble(result['lng']);
      if (mounted) {
        setState(() {
          selectedAddress = "${result['recipient_name'] ?? ''}\n${result['phone'] ?? ''}\n${result['house_no'] ?? ''}, ${result['street_area'] ?? ''}\n${result['landmark'] ?? ''}\n${result['full_display_address'] ?? ''}";
          currentDeliveryPosition = Position(
            latitude: newLat, longitude: newLon, timestamp: DateTime.now(),
            accuracy: 0.0, altitude: 0.0, heading: 0.0, speed: 0.0,
            speedAccuracy: 0.0, altitudeAccuracy: 0.0, headingAccuracy: 0.0,
          );
          _cachedFeesFuture = _calculateTotalFees();
        });
      }
    }
  }

  void _showSnackBar(String message, {Color color = Colors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _applyCoupon(double subtotal) async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;
    try {
      final snapshot = await _firestore.collection('coupons').where('name', isEqualTo: code).limit(1).get();
      if (snapshot.docs.isEmpty) { _showSnackBar('Invalid coupon'); return; }
      final data = snapshot.docs.first.data();
      final double value = parseDouble(data['value']);
      setState(() {
        appliedCoupon = code;
        discountAmount = data['type'] == 'percentage' ? subtotal * (value / 100.0) : value;
      });
      _showSnackBar("Coupon applied!", color: Colors.green);
    } catch (e) { _showSnackBar('Error applying coupon'); }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FeeBreakdown>(
      future: _cachedFeesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !_isCheckingStock) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.orange)));
        }

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.black), onPressed: () => Navigator.pop(context)),
            title: const Text("My Cart", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            centerTitle: true,
          ),
          body: Consumer<CartProvider>(
            builder: (context, cart, child) {
              if (cart.isEmpty) return _buildEmptyCart();
              final breakdown = snapshot.data ?? FeeBreakdown.zero;
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!breakdown.isDeliveryAvailable) _buildOutOfRangeWarning(breakdown.maxDistanceKm),
                    _buildSectionTitle("Cart Items"),
                    _buildCartItems(cart.items.values.toList()),
                    const SizedBox(height: 24),
                    _buildSectionTitle("Delivery Instructions"),
                    _buildInstructionsField(),
                    const SizedBox(height: 24),
                    _buildSectionTitle("Order Summary"),
                    _buildTotals(cart.totalAmount, breakdown),
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

  // --- UI COMPONENTS ---

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text("Your cart is empty", style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, top: 8.0),
      child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87)),
    );
  }

  Widget _buildCartItems(List<CartItem> items) {
    final cart = Provider.of<CartProvider>(context, listen: false);
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade100)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(item.image ?? "", width: 60, height: 60, fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: Colors.grey.shade100, child: const Icon(Icons.fastfood))),
            ),
            title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text("₹${item.price.toStringAsFixed(2)}", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            trailing: Container(
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.remove, size: 18, color: Colors.orange), onPressed: () => cart.reduceQuantity(item.id)),
                  Text("${item.quantity}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  IconButton(icon: const Icon(Icons.add, size: 18, color: Colors.orange), onPressed: () => cart.addItem(id: item.id, name: item.name, price: item.price, restaurantId: item.restaurantId, image: item.image)),
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
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: TextField(
        controller: _instructionController,
        maxLines: 2,
        decoration: const InputDecoration(hintText: "Add a note for the delivery partner...", contentPadding: EdgeInsets.all(12), border: InputBorder.none, hintStyle: TextStyle(fontSize: 13)),
      ),
    );
  }

  Widget _buildTotals(double subtotal, FeeBreakdown breakdown) {
    final total = subtotal + breakdown.totalFee - discountAmount;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          _buildPriceRow("Subtotal", subtotal),
          _buildPriceRow("Delivery Fee", breakdown.deliveryCharge),
          _buildPriceRow("Platform Fee", breakdown.platformFee),
          if (discountAmount > 0) _buildPriceRow("Discount", -discountAmount, color: Colors.green),
          const Divider(height: 24),
          _buildPriceRow("Total Amount", total, isBold: true, fontSize: 18),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, double val, {bool isBold = false, double fontSize = 14, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: fontSize, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text("₹${val.toStringAsFixed(2)}", style: TextStyle(fontSize: fontSize, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
        ],
      ),
    );
  }

  Widget _buildAddressCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(child: Text(selectedAddress, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          TextButton(onPressed: _showAddressSelectionScreen, child: const Text("Change", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildCouponSection(double subtotal) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
            child: TextField(controller: _couponController, decoration: const InputDecoration(hintText: "Enter Coupon Code", border: InputBorder.none, hintStyle: TextStyle(fontSize: 13))),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () => _applyCoupon(subtotal),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text("Apply"),
        ),
      ],
    );
  }

  Widget _buildPaymentCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange.shade100)),
      child: Row(
        children: const [
          Icon(Icons.payments_outlined, color: Colors.orange),
          SizedBox(width: 12),
          Text("Cash on Delivery", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
          Spacer(),
          Icon(Icons.check_circle, color: Colors.orange, size: 20),
        ],
      ),
    );
  }

  Widget _buildBottomCheckout(FeeBreakdown? breakdown) {
    final cart = Provider.of<CartProvider>(context);
    if (cart.isEmpty) return const SizedBox.shrink();
    final total = (breakdown?.totalFee ?? 0) + cart.totalAmount - discountAmount;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
      child: SafeArea(
        child: ElevatedButton(
          onPressed: (breakdown?.isDeliveryAvailable == true && currentDeliveryPosition != null && !_isCheckingStock) 
              ? () => _navigateToOrderConfirmation(cart.totalAmount, discountAmount, breakdown!.totalFee) 
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            minimumSize: const Size(double.infinity, 55),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            elevation: 0,
          ),
          child: _isCheckingStock 
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(currentDeliveryPosition == null ? "Select Address" : "Place Order • ₹${total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildOutOfRangeWarning(double dist) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade100)),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text("Out of range (${dist.toStringAsFixed(1)}km). We only deliver up to ${_deliverySettings?.maxDistance ?? 0}km.", style: const TextStyle(color: Colors.red, fontSize: 12))),
        ],
      ),
    );
  }
}