import 'dart:convert'; // ✅ Added for Base64 support
import 'package:fastevergo_v1/features/cart/morning_cart_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'MorningOrderHomeScreen.dart';
// import 'package:fastevergo_v1/features/cart/morning_cart_bar.dart'; // Unused in this file

class ConfirmationScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final double subtotal;
  final double discount;
  final double deliveryFee;
  final double total;
  final String address;
  final String payment;
  final String deliveryTime;
  final double? latitude; // <-- NEW: Added Latitude
  final double? longitude; // <-- NEW: Added Longitude

  const ConfirmationScreen({
    super.key,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.deliveryFee,
    required this.total,
    required this.address,
    required this.payment,
    required this.deliveryTime,
    this.latitude, // <-- NEW
    this.longitude, // <-- NEW
  });

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  bool _orderSaved = false;
  bool _canChangeItems = true;

  @override
  void initState() {
    super.initState();
    _checkChangeItemsAvailability();
    _clearMorningCartBar(); // ✅ Clear cart bar immediately
    _saveOrderToFirebase();
  }

  void _checkChangeItemsAvailability() {
    final now = DateTime.now();
    if (now.hour >= 22) _canChangeItems = false;
  }

  void _clearMorningCartBar() {
    // ✅ Hide/clear cart when reaching confirmation screen
    Future.delayed(Duration.zero, () {
      final cartProvider =
          Provider.of<MorningCartProvider>(context, listen: false);
      cartProvider.clearCart();
    });
  }

  Future<void> _saveOrderToFirebase() async {
    if (_orderSaved) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final bookingRef =
          FirebaseFirestore.instance.collection('morningbooking').doc();

      final bookingData = {
        "orderId": bookingRef.id,
        "userId": currentUser.uid, // ✅ Matches screenshot user ID
        "items": widget.items.map((item) => {
              "id": item['id'] ?? '',
              "name": item['name'] ?? '',
              "price": (item['price'] ?? 0).toDouble(),
              "quantity": item['quantity'] ?? 1,
              "image": item['image'] ?? '', // ✅ Supports Base64 string
            }).toList(),
        "subtotal": widget.subtotal,
        "discount": widget.discount,
        "deliveryFee": widget.deliveryFee, // ✅ Matches screenshot field
        "total": widget.total,
        "address": widget.address,
        "payment": widget.payment,
        "deliveryTime": widget.deliveryTime, // ✅ Matches screenshot slot
        "latitude": widget.latitude, // <-- NEW: Storing latitude
        "longitude": widget.longitude, // <-- NEW: Storing longitude
        "status": "booked",
        "timestamp": FieldValue.serverTimestamp(), // ✅ Matches screenshot timestamp
      };

      await bookingRef.set(bookingData);
      setState(() => _orderSaved = true);

      debugPrint("✅ Morning order saved: ${bookingRef.id} with Lat: ${widget.latitude}, Lng: ${widget.longitude}");
    } catch (e) {
      debugPrint("❌ Error saving morning order: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Colors.orange.shade700;

    return WillPopScope(
      // ✅ Override back navigation behavior
      onWillPop: () async {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
              builder: (context) => const MorningOrderHomeScreen()),
          (Route<dynamic> route) => false,
        );
        return false; // prevent going back to cart
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text("Morning Order Confirmation",
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: primaryColor,
          iconTheme: const IconThemeData(color: Colors.white),
          automaticallyImplyLeading:
              false, // ✅ remove back icon to force navigation logic
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ✅ Order Status Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryColor.withOpacity(0.5)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 60, color: primaryColor),
                    const SizedBox(height: 10),
                    Text(
                      "Your Morning Order is Booked!",
                      style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: primaryColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Your items will be delivered in the selected time slot.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 🛒 Order Items Section
              _buildSectionTitle("Order Items", primaryColor),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                    children:
                        widget.items.map((item) => _buildItemRow(item)).toList()),
              ),
              const SizedBox(height: 16),

              if (_canChangeItems && !_orderSaved)
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MorningOrderHomeScreen()),
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade400,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Change Items",
                      style: TextStyle(color: Colors.white)),
                ),

              const SizedBox(height: 24),

              // 📍 Delivery & Payment Details
              _buildSectionTitle("Delivery Details", primaryColor),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Delivery Address:",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(widget.address),
                    
                    // NEW: Display Coordinates for verification (Optional, can remove in production)
                    if (widget.latitude != null && widget.longitude != null) ...[
                      const SizedBox(height: 8),
                      Text("Lat: ${widget.latitude!.toStringAsFixed(6)}, Lng: ${widget.longitude!.toStringAsFixed(6)}",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                    
                    const Divider(height: 20),
                    const Text("Delivery Slot:",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(widget.deliveryTime,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: primaryColor)),
                    ),
                    const Divider(height: 20),
                    const Text("Payment Method:",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(widget.payment),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 💰 Price Summary
              _buildSectionTitle("Price Summary", primaryColor),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    _buildSummaryRow("Item Total", widget.subtotal),
                    _buildSummaryRow("Delivery Fee", widget.deliveryFee),
                    _buildSummaryRow("Discount", -widget.discount,
                        color: Colors.green),
                    const Divider(height: 20, thickness: 1.5),
                    _buildSummaryRow("Grand Total", widget.total,
                        isBold: true, fontSize: 20, color: primaryColor),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ✅ Back to MorningOrderHomeScreen
              ElevatedButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const MorningOrderHomeScreen()),
                      (route) => false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Back to Home",
                    style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title,
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      );

  Widget _buildItemRow(Map<String, dynamic> item) {
    final double price = (item['price'] as num?)?.toDouble() ?? 0;
    final int quantity = (item['quantity'] as num?)?.toInt() ?? 0;
    final String imageUrl = item['image'] ?? 'https://via.placeholder.com/50';

    // ✅ FIXED: Support for Base64 images found in your screenshot
    Widget itemImage;
    if (imageUrl.startsWith('data:image')) {
      try {
        final base64Str = imageUrl.split(',')[1];
        itemImage = Image.memory(
          base64Decode(base64Str),
          width: 50, height: 50, fit: BoxFit.cover,
        );
      } catch (e) {
        itemImage = const Icon(Icons.broken_image, size: 40);
      }
    } else if (imageUrl.startsWith('http')) {
      itemImage = Image.network(
        imageUrl, width: 50, height: 50, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
      );
    } else {
      itemImage = Container(
        width: 50, height: 50, color: Colors.grey.shade200,
        child: const Icon(Icons.image),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Sharp Square preview to maintain design consistency
          Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
            child: itemImage,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'] ?? "Item",
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Text("Quantity: $quantity",
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
          ),
          Text("₹${(price * quantity).toStringAsFixed(2)}",
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double value,
      {bool isBold = false, double fontSize = 16, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(
            (value < 0 ? "-" : "") + "₹${value.abs().toStringAsFixed(2)}",
            style: TextStyle(
                fontSize: fontSize,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color),
          ),
        ],
      ),
    );
  }
}