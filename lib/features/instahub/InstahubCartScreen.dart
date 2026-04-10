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

import 'instahub_cart_provider.dart'; 
import 'package:fastevergo_v1/features/food/cart/AddressFlow.dart';
import 'package:fastevergo_v1/features/food/order_confirmation_screen.dart';
// 👉 IMPORT THE NEW MANAGEMENT SCREEN
import 'package:fastevergo_v1/features/food/cart/ManageAddressScreen.dart';

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

/// Calculates distance between two lat/lon points in kilometers using Haversine formula.
double _calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371.0; 
  final latDistance = (lat2 - lat1) * (math.pi / 180);
  final lonDistance = (lon2 - lon1) * (math.pi / 180);
  final a = math.sin(latDistance / 2) * math.sin(latDistance / 2) +
      math.cos(lat1 * (math.pi / 180)) *
          math.cos(lat2 * (math.pi / 180)) *
          math.sin(lonDistance / 2) *
          math.sin(lonDistance / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}

// ===============================================
// DATA MODEL: Delivery Settings
// ===============================================
class DeliverySettings {
  final double baseFee;
  final double baseKm;
  final double maxDistanceKm;
  final double perKmFee;
  final double platformFee;

  DeliverySettings.fromFirestore(Map<String, dynamic> data)
      : baseFee = parseDouble(data['baseFee']),
        baseKm = parseDouble(data['baseKm']),
        maxDistanceKm = parseDouble(data['maxDistance']),
        perKmFee = parseDouble(data['perKmFee']),
        platformFee = parseDouble(data['platformFee']);

  static DeliverySettings get zero => DeliverySettings.fromFirestore({
        'baseFee': 0.0,
        'baseKm': 0.0,
        'maxDistance': 0.0,
        'perKmFee': 0.0,
        'platformFee': 0.0,
      });
}

// ===============================================
// DATA MODEL: Store Location
// ===============================================
class InstahubStoreLocation {
  final double latitude;
  final double longitude;
  final double storeRadiusKm;

  InstahubStoreLocation.fromFirestore(Map<String, dynamic> data)
      : latitude = parseDouble(data['latitude']),
        longitude = parseDouble(data['longitude']),
        storeRadiusKm = parseDouble(data['radiusKm']);

  static InstahubStoreLocation get zero =>
      InstahubStoreLocation.fromFirestore({'latitude': 0, 'longitude': 0, 'radiusKm': 0});
}


class FeeBreakdown {
  final double deliveryCharge;
  final double platformFee;
  final double totalFee;
  final double maxDistanceKm; 
  final double currentDistanceKm; 
  final bool isDeliveryAvailable;

  FeeBreakdown({
    this.deliveryCharge = 0.0,
    this.platformFee = 0.0,
    this.totalFee = 0.0,
    this.maxDistanceKm = 0.0,
    this.currentDistanceKm = 0.0,
    this.isDeliveryAvailable = false,
  });

  static FeeBreakdown get zero => FeeBreakdown();
}


// =======================================
// Instahub Cart Screen
// =======================================
class InstahubCartScreen extends StatefulWidget {
  final Position? userPosition;

  const InstahubCartScreen({super.key, this.userPosition});

  @override
  State<InstahubCartScreen> createState() => _InstahubCartScreenState();
}

class _InstahubCartScreenState extends State<InstahubCartScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String selectedAddress = "No address saved yet";
  String selectedPayment = "COD";
  String? appliedCoupon;
  double discountAmount = 0;

  Position? currentPosition;
  Position? currentDeliveryPosition;

  DeliverySettings? _deliverySettings;
  InstahubStoreLocation? _instahubStoreLocation;

  late Future<FeeBreakdown> _cachedFeesFuture;

  final TextEditingController _couponController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;

    _cachedFeesFuture = _initData().then((fees) async {
      if (user != null) {
        await _loadSavedAddress(user.uid);
        return _calculateTotalFees();
      }
      return fees;
    });

    Provider.of<InstahubCartProvider>(context, listen: false)
        .addListener(_onCartChange);
  }
  
  Future<FeeBreakdown> _initData() async {
    await Future.wait([
      _loadDeliverySettings(),
      _loadInstahubStoreLocation(),
    ]);
    return _calculateTotalFees();
  }

  Future<void> _loadDeliverySettings() async {
    if (_deliverySettings != null) return;
    try {
      final doc = await _firestore
          .collection('deliverySettings')
          .doc('instahub')
          .get();

      if (doc.exists && doc.data() != null && mounted) {
        _deliverySettings = DeliverySettings.fromFirestore(doc.data()!);
      }
    } catch (e) {
      debugPrint("Error loading DeliverySettings: $e");
    }
  }

  Future<void> _loadInstahubStoreLocation() async {
    if (_instahubStoreLocation != null) return;
    try {
      final doc = await _firestore
          .collection('instahubStores')
          .doc('2hnTyQfgFFJ9riCy7fL4')
          .get();

      if (doc.exists && doc.data() != null && mounted) {
        _instahubStoreLocation =
            InstahubStoreLocation.fromFirestore(doc.data()!);
      }
    } catch (e) {
      debugPrint("Error loading InstahubStoreLocation: $e");
    }
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
    Provider.of<InstahubCartProvider>(context, listen: false)
        .removeListener(_onCartChange);
    _couponController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  Future<void> _initUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) currentPosition = pos;
    } catch (e) {
      debugPrint("Error getting device location: $e");
    }
  }

  Future<void> _loadSavedAddress(String uid) async {
    final doc = await _firestore
        .collection("users")
        .doc(uid)
        .collection("profile")
        .doc("address")
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      final double savedLat = parseDouble(data['latitude']);
      final double savedLon = parseDouble(data['longitude']);

      final String fullAddress =
          "${data['name'] ?? ''}\n${data['phone'] ?? ''}\n"
          "${data['address'] ?? ''}\n${data['landmark'] ?? ''}";

      if (mounted) {
        setState(() {
          selectedAddress =
              fullAddress.trim().isEmpty ? "No address saved yet" : fullAddress;
          
          if (savedLat != 0.0 && savedLon != 0.0) {
            currentDeliveryPosition = Position(
              latitude: savedLat,
              longitude: savedLon,
              timestamp: DateTime.now(),
              accuracy: 0.0,
              altitude: 0.0,
              heading: 0.0,
              speed: 0.0,
              speedAccuracy: 0.0,
              altitudeAccuracy: 0.0,
              headingAccuracy: 0.0,
            );
          }
          _nameController.text = data["name"] ?? "";
          _phoneController.text = data["phone"] ?? "";
          _addressController.text = data["address"] ?? "";
          _landmarkController.text = data["landmark"] ?? "";
        });
      }
    }
  }

  double _calculateDeliveryCharge(double distanceKm) {
    if (_deliverySettings == null) return 0.0;
    final settings = _deliverySettings!;
    if (distanceKm <= 0.0) return settings.baseFee; 
    if (distanceKm <= settings.baseKm) {
      return settings.baseFee;
    } else {
      final extraDistance = distanceKm - settings.baseKm;
      final extraCharge = extraDistance * settings.perKmFee; 
      return settings.baseFee + extraCharge;
    }
  }

  Future<FeeBreakdown> _calculateTotalFees() async {
    if (_deliverySettings == null || _instahubStoreLocation == null) {
      await _initData();
      if (_deliverySettings == null || _instahubStoreLocation == null) {
        return FeeBreakdown(isDeliveryAvailable: false);
      }
    }

    final deliverySettings = _deliverySettings!;
    final storeLocation = _instahubStoreLocation!;
    Position? deliveryPosition = currentDeliveryPosition;
    
    if (deliveryPosition == null) {
      deliveryPosition = widget.userPosition;
    }
    
    if (deliveryPosition == null) {
      await _initUserLocation();
      deliveryPosition = currentPosition;
    }

    if (deliveryPosition == null) {
      return FeeBreakdown(isDeliveryAvailable: false);
    }
    
    final double distanceKm = _calculateDistanceKm(
      storeLocation.latitude,
      storeLocation.longitude,
      deliveryPosition.latitude,
      deliveryPosition.longitude,
    );

    final double effectiveMaxDistanceKm = math.min(
        deliverySettings.maxDistanceKm, storeLocation.storeRadiusKm);

    bool isAvailable = distanceKm <= effectiveMaxDistanceKm;
    double deliveryCharge = 0.0;
    double platformFee = 0.0;
    double totalFee = 0.0;

    if (isAvailable) {
      deliveryCharge = _calculateDeliveryCharge(distanceKm);
      platformFee = deliverySettings.platformFee;
      totalFee = deliveryCharge + platformFee;
    }

    return FeeBreakdown(
      deliveryCharge: deliveryCharge,
      platformFee: platformFee,
      totalFee: totalFee,
      maxDistanceKm: effectiveMaxDistanceKm,
      currentDistanceKm: distanceKm,
      isDeliveryAvailable: isAvailable,
    );
  }

  void _navigateToOrderConfirmation(
      double subtotal, double discount, FeeBreakdown fees) {
    
    if (currentDeliveryPosition == null) {
      _showSnackBar("Please select a precise delivery address before checkout.",
          color: Colors.red);
      return;
    }

    final double deliveryLat = currentDeliveryPosition!.latitude;
    final double deliveryLon = currentDeliveryPosition!.longitude;
    
    if (deliveryLat == 0.0 && deliveryLon == 0.0) {
        _showSnackBar("Missing or invalid location coordinates for delivery address. Please re-select on map.", color: Colors.red);
        return;
    }

    if (!fees.isDeliveryAvailable) {
      _showSnackBar("Your location is outside the delivery range of this store.",
          color: Colors.red);
      return;
    }
    
    final cartProvider =
        Provider.of<InstahubCartProvider>(context, listen: false);

    if (selectedPayment != "COD") {
      _showSnackBar("Only Cash on Delivery is available right now.",
          color: Colors.orange);
      return;
    }

    final List<Map<String, dynamic>> cartItems =
        cartProvider.items.values.map((item) {
      return {
        "name": item.name,
        "price": item.price,
        "quantity": item.quantity,
        "id": item.id,
        "image": item.image,
        "restaurantId": item.restaurantId,
      };
    }).toList();

    final double total = subtotal + fees.totalFee - discount; 

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderConfirmationScreen(
          items: cartItems.map((item) {
            return {
              "name": item["name"] ?? "Unnamed",
              "price": parseDouble(item["price"]),
              "quantity": parseInt(item["quantity"]),
              "restaurantId": item["restaurantId"],
              "image": item["image"],
            };
          }).toList(),
          subtotal: subtotal,
          discount: discount,
          total: total,
          address: selectedAddress,
          payment: selectedPayment,
          deliveryFee: fees.deliveryCharge, 
          platformFee: fees.platformFee,     
          appliedCouponCode: appliedCoupon,
          deliveryLatitude: deliveryLat,
          deliveryLongitude: deliveryLon,
        ),
      ),
    );
  }

  void _showAddressSelectionScreen() async {
    // 👉 UPDATED: Now uses ManageAddressScreen
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ManageAddressScreen(),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      // Formats display address using keys from ManageAddressScreen result
      final fullAddress =
          "${result['recipient_name'] ?? ''}\n${result['phone'] ?? ''}\n"
          "${result['house_no'] ?? ''}, ${result['street_area'] ?? ''}\n${result['landmark'] ?? ''}\n${result['full_display_address'] ?? ''}";

      // Extracts coordinates safely
      final double newLat = parseDouble(result['lat']);
      final double newLon = parseDouble(result['lng']);

      Position? newDeliveryPosition;

      if (newLat != 0.0 && newLon != 0.0) {
        newDeliveryPosition = Position(
          latitude: newLat,
          longitude: newLon,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
      }

      if (mounted) {
        setState(() {
          selectedAddress = fullAddress.trim().isEmpty ? "No address saved yet" : fullAddress;
          _nameController.text = result['recipient_name'] ?? '';
          _phoneController.text = result['phone'] ?? '';
          _addressController.text = "${result['house_no'] ?? ''}, ${result['street_area'] ?? ''}";
          _landmarkController.text = result['landmark'] ?? '';

          currentDeliveryPosition = newDeliveryPosition;
          _cachedFeesFuture = _calculateTotalFees();
        });

        if (newDeliveryPosition == null) {
          _showSnackBar(
              "Warning: Missing or invalid location data. Please ensure a precise location is picked on the map.",
              color: Colors.orange);
        }
      }
    }
  }

  void _showSnackBar(String message, {Color color = Colors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  Future<void> _applyCoupon(double subtotal) async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;

    final user = _auth.currentUser;
    if (user == null) {
      _showSnackBar("Please sign in to apply a coupon.");
      return;
    }

    try {
      final usageCheck = await _firestore
          .collection('orders')
          .where('userId', isEqualTo: user.uid)
          .where('appliedCouponCode', isEqualTo: code)
          .limit(1)
          .get();

      if (usageCheck.docs.isNotEmpty) {
        _showSnackBar("This coupon has already been used by you.",
            color: Colors.orange);
        _couponController.clear();
        setState(() {
          appliedCoupon = null;
          discountAmount = 0;
        });
        return;
      }
    } catch (e) {
      debugPrint("Error checking coupon usage: $e");
    }

    try {
      final snapshot = await _firestore
          .collection('coupons')
          .where('name', isEqualTo: code)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        _showSnackBar('Invalid coupon code');
        return;
      }

      final data = snapshot.docs.first.data();
      final startDate = (data['startDate'] as Timestamp).toDate();
      final endDate = (data['endDate'] as Timestamp).toDate();
      final now = DateTime.now();

      if (now.isBefore(startDate) || now.isAfter(endDate)) {
        _showSnackBar('This coupon is expired or not yet active.');
        return;
      }

      final type = data['type'] ?? 'flat';
      final value = parseDouble(data['value']);
      double discount = 0.0;

      if (type == 'flat') {
        discount = value;
      } else if (type == 'percent') {
        discount = subtotal * (value / 100);
      }

      final double maxDiscount = parseDouble(data['maxDiscount'] ?? 99999.0);
      if (discount > maxDiscount) discount = maxDiscount;
      if (discount > subtotal) discount = subtotal;

      if (mounted) {
        setState(() {
          appliedCoupon = code;
          discountAmount = discount;
          _cachedFeesFuture = _calculateTotalFees();
        });
      }

      _showSnackBar(
          'Coupon applied successfully! You saved ₹${discount.toStringAsFixed(2)}',
          color: Colors.green);
    } catch (e) {
      _showSnackBar('Failed to apply coupon: $e');
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildOutOfRangeWarning(
      double distanceKm, double maxDistanceKm) {
    if (distanceKm > maxDistanceKm && maxDistanceKm > 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade300),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Delivery not available. You are outside the ${maxDistanceKm.toStringAsFixed(1)} km delivery radius. Your distance is ${distanceKm.toStringAsFixed(1)} km.",
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCartItems(List<Map<String, dynamic>> items) {
    final cart = Provider.of<InstahubCartProvider>(context, listen: false);

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        final String docId = item['id'];
        final int quantity = parseInt(item["quantity"]);
        final double price = parseDouble(item["price"]);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    item["image"] ?? "https://via.placeholder.com/150",
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.fastfood, size: 50, color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item["name"] ?? "Unnamed Item",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "₹${price.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, color: Colors.orange, size: 20),
                      onPressed: () => cart.reduceQuantity(docId),
                    ),
                    Text(
                      quantity.toString(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.orange, size: 20),
                      onPressed: () => cart.addItem(
                        id: docId,
                        name: item['name'] ?? 'Unnamed',
                        price: price,
                        restaurantId: item['restaurantId'],
                        image: item['image'],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTotals(double subtotal, double deliveryCharge,
      double platformFee, double discount, double total, bool isAvailable) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildTotalRow("Subtotal", subtotal),
          if (isAvailable) ...[
            _buildTotalRow("Delivery Charge", deliveryCharge),
            _buildTotalRow("Platform Fee", platformFee),
          ] else
            _buildTotalRow("Delivery Charge & Fees", 0.0,
                isUnavailable: true, color: Colors.red),
          _buildTotalRow("Discount", -discount, color: Colors.green),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _buildTotalRow("Total", total, isBold: true, fontSize: 18),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double value,
      {bool isBold = false,
      double fontSize = 16.0,
      Color? color,
      bool isUnavailable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  fontSize: fontSize)),
          Text(
            isUnavailable ? "N/A" : "₹${value.abs().toStringAsFixed(2)}",
            style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: fontSize,
                color: isUnavailable ? Colors.red : color),
          ),
        ],
      ),
    );
  }

  Widget _buildAddress() {
    final bool hasValidCoords = currentDeliveryPosition != null && 
        (currentDeliveryPosition!.latitude != 0.0 || currentDeliveryPosition!.longitude != 0.0);

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Delivery Address",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: _showAddressSelectionScreen,
                child: const Text(
                  "Change",
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                  hasValidCoords
                      ? Icons.location_on
                      : Icons.warning_amber,
                  color:
                      hasValidCoords ? Colors.orange : Colors.red,
                  size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedAddress,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                  overflow: TextOverflow.visible,
                  maxLines: null,
                ),
              ),
            ],
          ),
          if (!hasValidCoords && selectedAddress != "No address saved yet")
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                "Warning: Location coordinates are missing or zero. Tap 'Change' to set a precise location on the map.",
                style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCoupon(double subtotal) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Apply Coupon",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponController,
                  onChanged: (value) {
                    if (appliedCoupon != null && value.isEmpty) {
                      setState(() {
                        appliedCoupon = null;
                        discountAmount = 0;
                        _cachedFeesFuture = _calculateTotalFees();
                      });
                    }
                  },
                  decoration: InputDecoration(
                    hintText: "Enter coupon code",
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    fillColor: Colors.white,
                    filled: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    suffixIcon: appliedCoupon != null
                        ? IconButton(
                            icon:
                                const Icon(Icons.check_circle, color: Colors.green),
                            onPressed: () {
                              _couponController.clear();
                              setState(() {
                                appliedCoupon = null;
                                discountAmount = 0;
                                _cachedFeesFuture = _calculateTotalFees();
                              });
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: appliedCoupon != null ? null : () => _applyCoupon(subtotal),
                style: ElevatedButton.styleFrom(
                  backgroundColor: appliedCoupon != null ? Colors.green : Colors.orange,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child:
                    appliedCoupon != null ? const Text("Applied", style: TextStyle(color: Colors.white)) : const Text("Apply", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPayment() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Payment Method",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          RadioListTile<String>(
            value: "COD",
            groupValue: selectedPayment,
            onChanged: (val) {
              setState(() => selectedPayment = val!);
            },
            title: const Text("Cash on Delivery"),
            controlAffinity: ListTileControlAffinity.trailing,
            activeColor: Colors.orange,
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<String>(
            value: "UPI",
            groupValue: selectedPayment,
            onChanged: (val) {
              _showSnackBar("Currently not available, coming soon!",
                  color: Colors.orange);
            },
            title: const Text("UPI / Wallets"),
            controlAffinity: ListTileControlAffinity.trailing,
            activeColor: Colors.orange,
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<String>(
            value: "Card",
            groupValue: selectedPayment,
            onChanged: (val) {
              _showSnackBar("Currently not available, coming soon!",
                  color: Colors.orange);
            },
            title: const Text("Credit / Debit Card"),
            controlAffinity: ListTileControlAffinity.trailing,
            activeColor: Colors.orange,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("My Instahub Cart")),
        body: const Center(child: Text("Please sign in to view your cart.")),
      );
    }

    return FutureBuilder<FeeBreakdown>(
      future: _cachedFeesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Colors.orange),
            ),
          );
        }

        if (snapshot.hasError) {
          debugPrint('Fee Calculation Error: ${snapshot.error}');
          return _buildCartUI(context, FeeBreakdown.zero);
        }

        final feeBreakdown = snapshot.data ?? FeeBreakdown.zero;
        return _buildCartUI(context, feeBreakdown);
      },
    );
  }

  Widget _buildCartUI(BuildContext context, FeeBreakdown feeBreakdown) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "My Instahub Cart",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<InstahubCartProvider>(
        builder: (context, cart, child) {
          if (cart.isEmpty) {
            return const Center(
              child: Text(
                "Your cart is empty 🛒",
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 18,
                    fontWeight: FontWeight.w500),
              ),
            );
          }

          final subtotal = cart.totalAmount;
          final discount = discountAmount;
          final double deliveryCharge = feeBreakdown.deliveryCharge;
          final double platformFee = feeBreakdown.platformFee;
          final double totalFees = feeBreakdown.totalFee;
          final bool isAvailable = feeBreakdown.isDeliveryAvailable;
          final double distanceKm = feeBreakdown.currentDistanceKm;
          final double maxDistanceKm = feeBreakdown.maxDistanceKm;

          final double total = isAvailable 
              ? subtotal + totalFees - discount
              : subtotal - discount;

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildOutOfRangeWarning(distanceKm, maxDistanceKm), 
                  _buildSectionTitle("Cart Items"),
                  _buildCartItems(cart.items.values.map((item) {
                    return {
                      "name": item.name,
                      "price": item.price,
                      "quantity": item.quantity,
                      "id": item.id,
                      "image": item.image,
                      "restaurantId": item.restaurantId,
                    };
                  }).toList()),
                  const SizedBox(height: 24),
                  _buildSectionTitle("Order Summary"),
                  _buildTotals(subtotal, deliveryCharge, platformFee,
                      discount, total, isAvailable),
                  const SizedBox(height: 24),
                  _buildSectionTitle("Delivery Address"),
                  _buildAddress(),
                  const SizedBox(height: 24),
                  _buildSectionTitle("Apply Coupon"),
                  _buildCoupon(subtotal),
                  const SizedBox(height: 24),
                  _buildSectionTitle("Payment Method"),
                  _buildPayment(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: Consumer<InstahubCartProvider>(
        builder: (context, cart, child) {
          if (cart.isEmpty) {
            return const SizedBox.shrink();
          }
          
          final subtotal = cart.totalAmount;
          final discount = discountAmount;
          final bool isAvailable = feeBreakdown.isDeliveryAvailable;

          final double total = isAvailable 
              ? subtotal + feeBreakdown.totalFee - discount
              : subtotal - discount;

          final bool isAddressSet = currentDeliveryPosition != null;
          final canPlaceOrder = isAddressSet && isAvailable;

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: !canPlaceOrder
                  ? null
                  : () {
                      _navigateToOrderConfirmation(
                          subtotal, discount, feeBreakdown);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: canPlaceOrder ? Colors.orange : Colors.grey,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                !isAddressSet
                    ? "Select Delivery Address"
                    : !isAvailable 
                        ? "Out of Delivery Range"
                        : "Place Order ₹${total.toStringAsFixed(2)}",
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          );
        },
      ),
    );
  }
}