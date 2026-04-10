import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'morning_cart_provider.dart';
import 'package:fastevergo_v1/features/food/cart/AddressFlow.dart';
import 'package:fastevergo_v1/features/food/coupon/coupon_service.dart';
import 'package:fastevergo_v1/features/food/coupon/coupon_model.dart';
import 'package:fastevergo_v1/features/instahub/confirmation_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' show max;
// 👉 IMPORT THE NEW MANAGEMENT SCREEN
import 'package:fastevergo_v1/features/food/cart/ManageAddressScreen.dart';

// -------------------------
// 🔹 Helper Functions
// -------------------------
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

// -------------------------
// 🔹 Morning Cart Screen
// -------------------------
class MorningCartScreen extends StatefulWidget {
  final Position? userPosition;
  const MorningCartScreen({super.key, this.userPosition});

  @override
  State<MorningCartScreen> createState() => _MorningCartScreenState();
}

class _MorningCartScreenState extends State<MorningCartScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _couponService = CouponService();

  // Delivery Slots
  final List<String> _deliverySlots = [
    "5:00 AM - 6:00 AM",
    "6:00 AM - 7:00 AM",
    "7:00 AM - 8:00 AM",
    "8:00 AM - 9:00 AM",
  ];

  String selectedAddress = "No address saved yet";
  String selectedPayment = "COD";
  Coupon? appliedCoupon;
  double appliedDiscount = 0;
  String selectedTimeSlot = "5:00 AM - 6:00 AM";

  Position? currentPosition;

  // -------------------------
  // Delivery Fee Configuration
  // -------------------------
  double _baseFee = 20.0; 
  double _baseKm = 2.0; 
  double _perKmFee = 8.0; 
  double _platformFee = 20.0; 
  double _maxDeliveryDistanceKm = 8.0; 

  static const String _STORE_DOC_ID = '2hnTyQfgFFJ9riCy7fl4';

  double? _storeLat;
  double? _storeLng;
  double? _deliveryLat;
  double? _deliveryLng;

  // ✅ ADDED SERVICE AREA VARIABLES
  double? _serviceLat;
  double? _serviceLng;

  double _calculatedDeliveryFee = 0.0;
  bool _isFeeLoading = true;
  bool _isOutOfRange = false;

  // Controllers
  final _couponController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _landmarkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initCartScreen();
  }

  /// Initializes the screen by loading necessary data in the correct sequence.
  Future<void> _initCartScreen({bool isRefresh = false}) async {
    try {
      if (mounted) setState(() => _isFeeLoading = true);
      final user = _auth.currentUser;
      
      // Load rules and locations in parallel
      await Future.wait([
        _loadStoreLocationAndFees(),
        _loadServiceAreaRadius(),
      ]);

      if (!isRefresh && user != null) await _loadSavedAddress(user.uid);

      await _initUserLocation();

      // Skip fallback if coords are 0.0 to prevent bad distance math
      if (_deliveryLat == 0.0) _deliveryLat = null;
      if (_deliveryLng == 0.0) _deliveryLng = null;

      _deliveryLat ??= _storeLat;
      _deliveryLng ??= _storeLng;

      debugPrint("Delivery Coords after all loads: $_deliveryLat, $_deliveryLng");

      await _calculateDeliveryFee();
    } catch (e) {
      debugPrint("Initialization error: $e");
    } finally {
      if (mounted) setState(() => _isFeeLoading = false);
    }
  }

  @override
  void dispose() {
    _couponController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  // -------------------------
  // Load Store Location & Fee Config
  // -------------------------
  Future<void> _loadStoreLocationAndFees() async {
    try {
      final storeDoc = await _firestore.collection('instahubStores').doc(_STORE_DOC_ID).get();
      if (storeDoc.exists) {
        final data = storeDoc.data()!;
        _storeLat = parseDouble(data['latitude']);
        _storeLng = parseDouble(data['longitude']);
        debugPrint("Store Location Loaded: $_storeLat, $_storeLng");
      } else {
        debugPrint("⚠️ Store document not found. Using fallback coordinates.");
        _storeLat ??= 9.224346500;
        _storeLng ??= 76.84841150;
      }

      final feeDoc = await _firestore.collection('deliveryfee').doc('morning service').get();

      if (feeDoc.exists) {
        final data = feeDoc.data()!;
        _baseFee = parseDouble(data['baseFee'], defaultValue: _baseFee);
        _baseKm = parseDouble(data['baseKm'], defaultValue: _baseKm);
        _perKmFee = parseDouble(data['perKmFee'], defaultValue: _perKmFee);
        _platformFee = parseDouble(data['platformFee'], defaultValue: _platformFee);
        debugPrint("✅ Delivery Fees Loaded: Platform Fee is $_platformFee");
      }
    } catch (e) {
      debugPrint("⚠️ Firestore load error: $e");
    }
  }

  // -------------------------
  // Load Service Area Radius
  // -------------------------
  Future<void> _loadServiceAreaRadius() async {
    try {
      final snapshot = await _firestore
          .collection('morning_service_areas')
          .where('active', isEqualTo: true)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();

        _maxDeliveryDistanceKm = parseDouble(
          data['radiusKm'],
          defaultValue: _maxDeliveryDistanceKm,
        );

        _serviceLat = parseDouble(data['latitude']);
        _serviceLng = parseDouble(data['longitude']);

        debugPrint("✅ Service Area Radius Loaded: $_maxDeliveryDistanceKm km");
      }
    } catch (e) {
      debugPrint("⚠️ Service area load error: $e");
    }
  }

  // -------------------------
  // Load Saved Address
  // -------------------------
  Future<void> _loadSavedAddress(String uid) async {
    try {
      final doc = await _firestore.collection("users").doc(uid).collection("profile").doc("address").get();
      if (doc.exists) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            selectedAddress = data["fullAddress"] ?? "No address saved yet";
            _nameController.text = data["name"] ?? '';
            _phoneController.text = data["phone"] ?? '';
            _addressController.text = data["address"] ?? '';
            _landmarkController.text = data["landmark"] ?? '';
            _deliveryLat = parseDouble(data['latitude']);
            _deliveryLng = parseDouble(data['longitude']);
          });
        }
      }
    } catch (e) {
      debugPrint("⚠️ Address load error: $e");
    }
  }

  // -------------------------
  // Initialize User Location
  // -------------------------
  Future<void> _initUserLocation() async {
    if (_deliveryLat != null && _deliveryLng != null && _deliveryLat != 0.0) return;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
          debugPrint("⚠️ Location services disabled.");
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        if (mounted) {
          setState(() {
            currentPosition = pos;
            _deliveryLat = pos.latitude;
            _deliveryLng = pos.longitude;
          });
        }
      }
    } catch (e) {
      debugPrint("⚠️ Location error: $e");
    }
  }

  // -------------------------
  // Address Selection
  // -------------------------
  void _showAddressSelectionScreen() async {
    // 👉 UPDATED: Navigates to ManageAddressScreen for the new selection flow
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ManageAddressScreen()),
    );

    if (result != null && result is Map<String, dynamic>) {
      if (mounted) {
        setState(() {
          _isFeeLoading = true; 
          // MATCHING FOOD CART KEYS: 'lat' and 'lng'
          _deliveryLat = parseDouble(result['lat']);
          _deliveryLng = parseDouble(result['lng']);
          selectedAddress = "${result['recipient_name'] ?? ''}\n${result['phone'] ?? ''}\n${result['house_no'] ?? ''}, ${result['street_area'] ?? ''}\n${result['landmark'] ?? ''}";
          _nameController.text = result['recipient_name'] ?? '';
          _phoneController.text = result['phone'] ?? '';
          _addressController.text = "${result['house_no'] ?? ''}, ${result['street_area'] ?? ''}";
          _landmarkController.text = result['landmark'] ?? '';
        });
      }
      
      await _refreshDeliveryDataOnly();
    }
  }

  Future<void> _refreshDeliveryDataOnly() async {
    try {
      await _loadStoreLocationAndFees();
      await _loadServiceAreaRadius();
      await _calculateDeliveryFee();
    } catch (e) {
      debugPrint("Refresh error: $e");
    } finally {
      if (mounted) setState(() => _isFeeLoading = false);
    }
  }

  // -------------------------
  // Calculate Delivery Fee
  // -------------------------
  Future<double> _calculateDeliveryFee() async {
    if (_storeLat == null || _storeLng == null || _deliveryLat == null || _deliveryLng == null || _serviceLat == null || _deliveryLat == 0.0) {
      if (mounted) setState(() => _isFeeLoading = false);
      return 0.0;
    }

    double distanceToServiceCenter = Geolocator.distanceBetween(
      _serviceLat!, 
      _serviceLng!, 
      _deliveryLat!, 
      _deliveryLng!,
    ) / 1000;

    if (distanceToServiceCenter > _maxDeliveryDistanceKm) {
      if (mounted) {
        setState(() {
          _isOutOfRange = true;
          _calculatedDeliveryFee = 0.0;
          _isFeeLoading = false;
        });
      }
      return 0.0;
    }

    double distanceInKmFromStore = Geolocator.distanceBetween(
      _storeLat!, 
      _storeLng!, 
      _deliveryLat!, 
      _deliveryLng!,
    ) / 1000;

    double deliveryFee = distanceInKmFromStore <= _baseKm 
        ? _baseFee 
        : _baseFee + (distanceInKmFromStore - _baseKm) * _perKmFee;

    if (mounted) {
      setState(() {
        _calculatedDeliveryFee = double.parse(deliveryFee.toStringAsFixed(2));
        _isOutOfRange = false; 
        _isFeeLoading = false;
      });
    }
    return _calculatedDeliveryFee;
  }

  // -------------------------
  // Navigate to Confirmation
  // -------------------------
  void _navigateToOrderConfirmation(double subtotal, double discount, double totalDeliveryFee) {
    final bool coordsMissing = _deliveryLat == null || _deliveryLng == null || _storeLat == null || _storeLng == null || _deliveryLat == 0.0;

    if (selectedAddress == "No address saved yet" || coordsMissing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a delivery address."), backgroundColor: Colors.red),
      );
      return;
    }

    if (_isOutOfRange) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Delivery unavailable (Max ${_maxDeliveryDistanceKm.toStringAsFixed(0)} km)")),
      );
      return;
    }

    final total = subtotal - discount + totalDeliveryFee;
    final cart = Provider.of<MorningCartProvider>(context, listen: false);
    final List<Map<String, dynamic>> cartItems = cart.items.values.map((item) {
      return {
        "id": item['id'],
        "name": item['name'] ?? 'Unnamed',
        "price": item['price'],
        "quantity": item['quantity'],
        "image": item['image'] ?? "https://via.placeholder.com/70",
        "restaurantId": "morningHub",
      };
    }).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConfirmationScreen(
          items: cartItems,
          subtotal: subtotal,
          discount: discount,
          total: total,
          address: selectedAddress,
          payment: selectedPayment,
          deliveryFee: totalDeliveryFee,
          deliveryTime: selectedTimeSlot,
          latitude: _deliveryLat,
          longitude: _deliveryLng,
        ),
      ),
    );
  }

  // -------------------------
  // Apply Coupon
  // -------------------------
  Future<void> _applyCoupon(double subtotal) async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;

    final coupon = await _couponService.validateCoupon(code);
    if (coupon == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid coupon"), backgroundColor: Colors.red),
      );
      return;
    }

    double discount = coupon.type == "percentage" ? subtotal * (coupon.value / 100) : coupon.value;

    if (mounted) {
      setState(() {
        appliedCoupon = coupon;
        appliedDiscount = discount;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<MorningCartProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Morning Cart"),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
      ),
      body: cart.items.isEmpty
          ? const Center(child: Text("Your cart is empty ☀️"))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionTitle("🛒 Cart Items"),
                  _buildCartItems(cart),
                  const SizedBox(height: 16),
                  _buildSectionTitle("📍 Delivery Address"),
                  _buildAddress(),
                  const SizedBox(height: 16),
                  _buildSectionTitle("⏰ Select Delivery Time"),
                  _buildDeliveryTimeSlot(),
                  const SizedBox(height: 16),
                  _buildSectionTitle("💰 Order Summary"),
                  _buildTotals(cart.totalAmount, _calculatedDeliveryFee, _platformFee, appliedDiscount, _isFeeLoading, _isOutOfRange),
                  const SizedBox(height: 16),
                  _buildSectionTitle("🏷️ Apply Coupon"),
                  _buildCoupon(cart.totalAmount),
                  const SizedBox(height: 16),
                  _buildSectionTitle("💳 Payment Method"),
                  _buildPayment(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar: cart.items.isEmpty ? null : _buildPlaceOrderButton(cart.totalAmount),
    );
  }

  // -------------------------
  // UI Helper Widgets
  // -------------------------
  Widget _buildSectionTitle(String title) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      );

  Widget _buildAddress() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Delivery Address", style: TextStyle(fontWeight: FontWeight.bold)),
              TextButton(onPressed: _showAddressSelectionScreen, child: Text("Change", style: TextStyle(color: Colors.orange.shade700))),
            ]),
            const SizedBox(height: 8),
            Text(selectedAddress),
            if (_deliveryLat != null && _deliveryLng != null && _deliveryLat != 0.0) ...[
              const SizedBox(height: 8),
              Text("Lat: ${_deliveryLat!.toStringAsFixed(6)}, Lng: ${_deliveryLng!.toStringAsFixed(6)}",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ],
        ),
      );

  Widget _buildDeliveryTimeSlot() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
        child: DropdownButtonFormField<String>(
          value: selectedTimeSlot,
          decoration: InputDecoration(
            labelText: 'Select Slot',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.alarm, color: Colors.orange),
          ),
          onChanged: (String? newValue) { if (newValue != null) setState(() => selectedTimeSlot = newValue); },
          items: _deliverySlots.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        ),
      );

  Widget _buildCoupon(double subtotal) => Row(children: [
        Expanded(child: TextField(controller: _couponController, decoration: InputDecoration(hintText: "Enter coupon", filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
        const SizedBox(width: 8),
        ElevatedButton(onPressed: () => _applyCoupon(subtotal), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white), child: const Text("Apply")),
      ]);

  Widget _buildPayment() => Column(children: [
        RadioListTile<String>(value: "COD", groupValue: selectedPayment, onChanged: (val) => setState(() => selectedPayment = val!), title: const Text("Cash on Delivery"), activeColor: Colors.orange.shade700),
      ]);

  Widget _buildTotals(double subtotal, double deliveryFee, double platformFee, double discount, bool isLoading, bool isUnavailable) {
    final bool coordsMissing = (_deliveryLat == null || _deliveryLat == 0.0) && !isLoading;
    final bool showDeliveryUnavailable = isUnavailable || coordsMissing;
    final actualDeliveryFee = showDeliveryUnavailable ? 0.0 : deliveryFee;
    final total = subtotal - discount + actualDeliveryFee + platformFee;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        _buildTotalRow("Subtotal", subtotal),
        _buildTotalRow("Delivery Fee", deliveryFee, isPlaceholder: isLoading, isUnavailable: showDeliveryUnavailable),
        _buildTotalRow("Platform Fee", platformFee, isPlaceholder: isLoading),
        _buildTotalRow("Discount", -discount, color: Colors.green),
        const Divider(),
        _buildTotalRow("Total", total, isBold: true, fontSize: 18, color: Colors.orange.shade700, isPlaceholder: isLoading, isUnavailable: coordsMissing),
      ]),
    );
  }

  Widget _buildTotalRow(String label, double value, {bool isBold = false, double fontSize = 16, Color? color, bool isPlaceholder = false, bool isUnavailable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: fontSize)),
        isPlaceholder ? const SizedBox(width: 80, child: LinearProgressIndicator()) : Text(isUnavailable ? "N/A" : "₹${value.toStringAsFixed(2)}", style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: fontSize, color: isUnavailable ? Colors.red : color)),
      ]),
    );
  }

  Widget _buildPlaceOrderButton(double subtotal) {
    final bool coordsMissing = (_deliveryLat == null || _deliveryLat == 0.0) && !_isFeeLoading;
    final bool isReady = !_isFeeLoading && !_isOutOfRange && !coordsMissing;
    final total = subtotal - appliedDiscount + _calculatedDeliveryFee + _platformFee;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ElevatedButton(
        onPressed: isReady ? () => _navigateToOrderConfirmation(subtotal, appliedDiscount, _calculatedDeliveryFee + _platformFee) : null,
        style: ElevatedButton.styleFrom(backgroundColor: isReady ? Colors.orange.shade700 : Colors.grey, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: _isFeeLoading ? const CircularProgressIndicator(color: Colors.white) : Text("Place Order ₹${total.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildCartItems(MorningCartProvider cart) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cart.items.length,
      itemBuilder: (_, i) {
        final item = cart.items.values.toList()[i];
        final id = item['id'];
        final quantity = parseInt(item['quantity']);
        final price = parseDouble(item['price']);
        final imageUrl = item['image'] ?? "https://via.placeholder.com/70";

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.zero),
          child: Row(children: [
            Container(width: 60, height: 60, child: Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image))),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)), Text("₹${price.toStringAsFixed(2)} x $quantity")])),
            IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => cart.reduceQuantity(id)),
            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => cart.addItem(id: id, name: item['name'] ?? '', price: price, restaurantId: "morningHub", image: imageUrl)),
          ]),
        );
      },
    );
  }
}