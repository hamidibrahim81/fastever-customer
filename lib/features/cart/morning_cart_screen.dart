import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'morning_cart_provider.dart';
import 'package:intl/intl.dart';

import 'package:fastevergo_v1/features/food/coupon/coupon_service.dart';
import 'package:fastevergo_v1/features/food/coupon/coupon_model.dart';
import 'package:fastevergo_v1/features/instahub/confirmation_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

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
// 🔹 Theme Tokens
// -------------------------
class _CartTheme {
  static const Color primaryDark = Color(0xFF111827);
  static const Color accentOrange = Color(0xFFFF6B00);
  static const Color successGreen = Color(0xFF16A34A);
  static const Color bgColor = Color(0xFFF8FAFC);
  static const Color cardBorder = Color(0xFFE2E8F0);
  static const Color textMuted = Color(0xFF64748B);
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
  
  DateTime selectedDate = DateTime.now().add(const Duration(days: 1));

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

  double? _serviceLat;
  double? _serviceLng;

  double _calculatedDeliveryFee = 0.0;
  bool _isFeeLoading = true;
  bool _isOutOfRange = false;

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

  Future<void> _initCartScreen({bool isRefresh = false}) async {
    try {
      if (mounted) setState(() => _isFeeLoading = true);

      final user = _auth.currentUser;

      await Future.wait([
        _loadStoreLocationAndFees(),
        _loadServiceAreaRadius(),
      ]);

      if (!isRefresh && user != null) {
        await _loadSavedAddress(user.uid);
      }

      if (_deliveryLat == 0.0) _deliveryLat = null;
      if (_deliveryLng == 0.0) _deliveryLng = null;

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

  Future<void> _loadStoreLocationAndFees() async {
    try {
      final storeDoc = await _firestore.collection('instahubStores').doc(_STORE_DOC_ID).get();
      if (storeDoc.exists) {
        final data = storeDoc.data()!;
        _storeLat = parseDouble(data['latitude']);
        _storeLng = parseDouble(data['longitude']);
      } else {
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
      }
    } catch (e) {
      debugPrint("Firestore load error: $e");
    }
  }

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
      }
    } catch (e) {
      debugPrint("Service area load error: $e");
    }
  }

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
      debugPrint("Address load error: $e");
    }
  }

  void _showAddressSelectionScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManageAddressScreen()),
    );

    if (result != null && result is Map<String, dynamic>) {
      if (mounted) {
        setState(() {
          _isFeeLoading = true; 
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

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now(), 
      lastDate: DateTime.now().add(const Duration(days: 7)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _CartTheme.primaryDark,
              onPrimary: Colors.white,
              onSurface: _CartTheme.primaryDark,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  void _navigateToOrderConfirmation(double subtotal, double discount, double totalDeliveryFee) {
    final bool coordsMissing = _deliveryLat == null || _deliveryLng == null || _storeLat == null || _storeLng == null || _deliveryLat == 0.0;

    if (selectedAddress == "No address saved yet" || coordsMissing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a delivery address."), backgroundColor: Colors.redAccent),
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
        "paymentStatus": "waiting for grant", // 👈 Added paymentStatus field here
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
          deliveryFee: _calculatedDeliveryFee, 
          deliveryTime: selectedTimeSlot, 
          deliveryDate: selectedDate,    
          latitude: _deliveryLat,
          longitude: _deliveryLng,
        ),
      ),
    );
  }

  Future<void> _applyCoupon(double subtotal) async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;

    final coupon = await _couponService.validateCoupon(code);
    if (coupon == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid coupon"), backgroundColor: Colors.redAccent),
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

  Widget _buildCardContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: _CartTheme.cardBorder.withOpacity(0.6)),
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(icon, color: _CartTheme.accentOrange, size: 20),
            const SizedBox(width: 8),
            Text(
              title, 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _CartTheme.primaryDark),
            ),
          ],
        ),
      );

  Widget _buildAddress() => _buildCardContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionTitle(Icons.location_on_rounded, "Delivery Address"),
                TextButton(
                  onPressed: _showAddressSelectionScreen,
                  child: const Text(
                    "Change",
                    style: TextStyle(color: _CartTheme.accentOrange, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _CartTheme.primaryDark.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.home_rounded, color: _CartTheme.primaryDark, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    selectedAddress,
                    style: const TextStyle(fontSize: 14, color: _CartTheme.primaryDark, height: 1.3, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buildDeliveryTimeSlot() => _buildCardContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(Icons.schedule_rounded, "Delivery Schedule"),
            InkWell(
              onTap: _selectDate,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: _CartTheme.cardBorder),
                  borderRadius: BorderRadius.circular(14),
                  color: _CartTheme.bgColor,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded, color: _CartTheme.accentOrange, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat('EEEE, d MMM yyyy').format(selectedDate),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _CartTheme.primaryDark),
                        ),
                      ],
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: _CartTheme.textMuted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedTimeSlot,
              decoration: InputDecoration(
                labelText: 'Select Time Slot',
                labelStyle: const TextStyle(color: _CartTheme.textMuted, fontSize: 13),
                filled: true,
                fillColor: _CartTheme.bgColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _CartTheme.cardBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _CartTheme.cardBorder)),
                prefixIcon: const Icon(Icons.alarm_rounded, color: _CartTheme.accentOrange, size: 20),
              ),
              onChanged: (String? newValue) { if (newValue != null) setState(() => selectedTimeSlot = newValue); },
              items: _deliverySlots.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)))).toList(),
            ),
          ],
        ),
      );

  Widget _buildCoupon(double subtotal) => _buildCardContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(Icons.local_offer_rounded, "Apply Coupon"),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _couponController,
                    decoration: InputDecoration(
                      hintText: "Enter coupon code",
                      hintStyle: const TextStyle(color: _CartTheme.textMuted, fontSize: 14),
                      filled: true,
                      fillColor: _CartTheme.bgColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => _applyCoupon(subtotal),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _CartTheme.primaryDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Apply", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buildPayment() => _buildCardContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(Icons.payments_rounded, "Payment Method"),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _CartTheme.bgColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _CartTheme.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _CartTheme.accentOrange.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.payments_rounded, color: _CartTheme.accentOrange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Cash on Delivery", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _CartTheme.primaryDark)),
                        SizedBox(height: 2),
                        Text("Pay in cash upon delivery", style: TextStyle(fontSize: 12, color: _CartTheme.textMuted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.check_circle_rounded, color: _CartTheme.accentOrange, size: 22),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildTotals(double subtotal, double deliveryFee, double platformFee, double discount, bool isLoading, bool isUnavailable) {
    final bool coordsMissing = (_deliveryLat == null || _deliveryLat == 0.0) && !isLoading;
    final bool showDeliveryUnavailable = isUnavailable || coordsMissing;
    final actualDeliveryFee = showDeliveryUnavailable ? 0.0 : deliveryFee;
    final total = subtotal - discount + actualDeliveryFee + platformFee;

    return _buildCardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(Icons.receipt_long_rounded, "Order Summary"),
          _buildTotalRow("Subtotal", subtotal),
          _buildTotalRow("Delivery Fee", deliveryFee, isPlaceholder: isLoading, isUnavailable: showDeliveryUnavailable),
          _buildTotalRow("Platform Fee", platformFee, isPlaceholder: isLoading),
          if (discount > 0) _buildTotalRow("Discount", -discount, color: _CartTheme.successGreen),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),
          _buildTotalRow("Total Amount", total, isBold: true, fontSize: 17, color: _CartTheme.accentOrange, isPlaceholder: isLoading, isUnavailable: coordsMissing),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double value, {bool isBold = false, double fontSize = 14, Color? color, bool isPlaceholder = false, bool isUnavailable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, 
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w500, fontSize: fontSize, color: isBold ? _CartTheme.primaryDark : _CartTheme.textMuted)),
          isPlaceholder 
              ? const SizedBox(width: 60, child: LinearProgressIndicator(color: _CartTheme.accentOrange)) 
              : Text(
                  isUnavailable ? "N/A" : "₹${value.abs().toStringAsFixed(2)}", 
                  style: TextStyle(
                    fontWeight: isBold ? FontWeight.w900 : FontWeight.bold, 
                    fontSize: fontSize, 
                    color: isUnavailable ? Colors.redAccent : (color ?? (isBold ? _CartTheme.primaryDark : _CartTheme.primaryDark)),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildPlaceOrderButton(double subtotal) {
    final bool noAddressSelected =
        selectedAddress == "No address saved yet" ||
        _deliveryLat == null ||
        _deliveryLng == null ||
        _deliveryLat == 0.0 ||
        _deliveryLng == 0.0;

    final bool isReady = !_isFeeLoading && !_isOutOfRange && !noAddressSelected;

    final total = subtotal - appliedDiscount + _calculatedDeliveryFee + _platformFee;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: isReady
                ? () => _navigateToOrderConfirmation(
                      subtotal,
                      appliedDiscount,
                      _calculatedDeliveryFee + _platformFee,
                    )
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isReady ? _CartTheme.primaryDark : Colors.grey.shade400,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isFeeLoading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    noAddressSelected
                        ? "Select Delivery Address"
                        : "Place Order • ₹${total.toStringAsFixed(2)}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildCartItems(MorningCartProvider cart) {
    return _buildCardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(Icons.shopping_bag_rounded, "Cart Items"),
          ListView.separated(
            shrinkWrap: true,
            physics: const ScrollPhysics(),
            itemCount: cart.items.length,
            separatorBuilder: (_, __) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Divider(height: 1, color: Color(0xFFF1F5F9)),
            ),
            itemBuilder: (_, i) {
              final item = cart.items.values.toList()[i];
              final id = item['id'];
              final quantity = parseInt(item['quantity']);
              final price = parseDouble(item['price']);
              final imageUrl = item['image'] ?? "https://via.placeholder.com/70";

              return Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      imageUrl, 
                      width: 55, 
                      height: 55, 
                      fit: BoxFit.cover, 
                      errorBuilder: (_, __, ___) => Container(color: _CartTheme.bgColor, child: const Icon(Icons.image_outlined, color: _CartTheme.textMuted)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name'] ?? '', 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _CartTheme.primaryDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "₹${price.toStringAsFixed(2)}", 
                          style: const TextStyle(fontSize: 13, color: _CartTheme.textMuted, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded, color: _CartTheme.accentOrange, size: 22), 
                        onPressed: () => cart.reduceQuantity(id),
                      ),
                      Text(
                        "$quantity", 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _CartTheme.primaryDark),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded, color: _CartTheme.accentOrange, size: 22), 
                        onPressed: () => cart.addItem(id: id, name: item['name'] ?? '', price: price, restaurantId: "morningHub", image: imageUrl),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<MorningCartProvider>(context);
    return Scaffold(
      backgroundColor: _CartTheme.bgColor,
      appBar: AppBar(
        title: const Text("Morning Cart", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _CartTheme.primaryDark)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _CartTheme.primaryDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: cart.items.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wb_sunny_outlined, size: 80, color: _CartTheme.textMuted),
                  SizedBox(height: 16),
                  Text(
                    "Your morning cart is empty ☀️", 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _CartTheme.primaryDark),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCartItems(cart),
                  _buildAddress(),
                  _buildDeliveryTimeSlot(),
                  _buildTotals(cart.totalAmount, _calculatedDeliveryFee, _platformFee, appliedDiscount, _isFeeLoading, _isOutOfRange),
                  _buildCoupon(cart.totalAmount),
                  _buildPayment(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
      bottomNavigationBar: cart.items.isEmpty ? null : _buildPlaceOrderButton(cart.totalAmount),
    );
  }
}