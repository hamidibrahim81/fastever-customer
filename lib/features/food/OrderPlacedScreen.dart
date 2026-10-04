import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'cart/cart_provider.dart';
import 'food_home_screen.dart'; 
import 'package:firebase_messaging/firebase_messaging.dart';

class OrderPlacedScreen extends StatefulWidget {
  final Map<String, dynamic> orderData;

  const OrderPlacedScreen({super.key, required this.orderData});

  @override
  State<OrderPlacedScreen> createState() => _OrderPlacedScreenState();
}

class _OrderPlacedScreenState extends State<OrderPlacedScreen> {
  String? orderId;
  bool isLoading = true;
  bool hasOrderRun = false; 

  static const Color _primaryDark = Color(0xFF111827);
  static const Color _accentOrange = Color(0xFFFF6B00);
  static const Color _successGreen = Color(0xFF16A34A);
  static const Color _bgColor = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    if (!hasOrderRun) {
      _placeOrder();
    }
  }

  Future<void> _placeOrder() async {
    if (hasOrderRun) return; 
    setState(() => hasOrderRun = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not signed in");

      // --- 1. DATA PREPARATION ---
      final List allItems = (widget.orderData['items'] is List)
          ? List.from(widget.orderData['items'])
          : [];
      
      final double deliveryFee = double.tryParse(widget.orderData['deliveryFee'].toString()) ?? 0.0;
      final double platformFee = double.tryParse(widget.orderData['platformFee'].toString()) ?? 0.0;
      final double totalAmount = double.tryParse(widget.orderData['total'].toString()) ?? 0.0;
      final double subtotal = double.tryParse(widget.orderData['subtotal'].toString()) ?? 0.0;
      final double discount = double.tryParse(widget.orderData['discount'].toString()) ?? 0.0;
      final String deliveryInstructions = widget.orderData['deliveryInstructions'] ?? "";

      String primaryRestaurantId = widget.orderData['restaurantId']?.toString() ?? "UNKNOWN";
      
      if ((primaryRestaurantId == "UNKNOWN" || primaryRestaurantId.isEmpty) && allItems.isNotEmpty) {
        final firstItem = Map<String, dynamic>.from(allItems.first as Map);
        primaryRestaurantId = firstItem['restaurantId']?.toString() ?? "UNKNOWN";
      }

      if (primaryRestaurantId == "UNKNOWN") {
        throw Exception("Critical Error: No Restaurant ID found in order data.");
      }

      final Map<String, List<Map<String, dynamic>>> itemsByRestaurant = {};
      for (var item in allItems) {
        final itemMap = Map<String, dynamic>.from(item as Map);
        final String rId = itemMap['restaurantId']?.toString() ?? "UNKNOWN";
        if (!itemsByRestaurant.containsKey(rId)) {
          itemsByRestaurant[rId] = [];
        }
        itemsByRestaurant[rId]!.add(itemMap);
      }

      final timestamp = FieldValue.serverTimestamp();
      final createdDate = DateTime.now().toIso8601String();
      final address = widget.orderData['address'] ?? "N/A";
      final payment = widget.orderData['payment'] ?? "N/A";

      Map<String, dynamic> location = {};
      
      final lat = widget.orderData['deliveryLatitude'];
      final lng = widget.orderData['deliveryLongitude'];

      if (lat != null && lng != null) {
        location = {
          "geoPoint": GeoPoint(lat, lng),
          "latitude": lat,
          "longitude": lng,
        };
      }

      final String userName = widget.orderData['name'] ?? user.displayName ?? "Valued Customer";
      final String userPhone = widget.orderData['phone'] ?? user.phoneNumber ?? "N/A";

      // STEP 2: MASTER ORDER
      final masterOrderData = {
        "userId": user.uid,
        "userName": userName,
        "userPhone": userPhone,
        "items": allItems, 
        "subtotal": subtotal,
        "discount": discount,
        "deliveryFee": deliveryFee, 
        "platformFee": platformFee,
        "total": totalAmount,
        "timestamp": timestamp,
        "createdAt": createdDate,
        "status": "pending",
        "restaurantId": primaryRestaurantId, 
        "address": address,
        "deliveryInstructions": deliveryInstructions, 
        "payment": payment,
        "location": location,
        "destinationLocation": location["geoPoint"],
        "appliedCouponCode": widget.orderData['appliedCouponCode'],
        "platform": "flutter_customer_app",
      };

      final DocumentReference masterRef = await FirebaseFirestore.instance
          .collection("orders")
          .add(masterOrderData);

      await masterRef.update({"orderId": masterRef.id});

      final batch = FirebaseFirestore.instance.batch();

      // STEP 3: SPLIT ORDERS
      itemsByRestaurant.forEach((rId, rItems) {
        double rTotal = 0;
        for (var item in rItems) {
            double price = double.tryParse(item['price'].toString()) ?? 0;
            int qty = int.tryParse(item['quantity'].toString()) ?? 1;
            rTotal += (price * qty);
        }

        final DocumentReference splitRef = FirebaseFirestore.instance.collection("restaurant_orders").doc();
        
        final splitOrderData = {
          "orderId": splitRef.id,
          "masterOrderId": masterRef.id,
          "userId": user.uid,
          "restaurantId": rId, 
          "items": rItems,    
          "total": rTotal,    
          "subtotal": rTotal,
          "deliveryFee": 0, 
          "discount": 0,      
          "status": "pending",
          "timestamp": timestamp,
          "createdAt": createdDate,
          "address": address,
          "deliveryInstructions": deliveryInstructions, 
          "payment": payment,
          "location": location,
          "destinationLocation": location["geoPoint"],
          "platform": "flutter_customer_app",
        };

        batch.set(splitRef, splitOrderData);
      });

      // STEP 4: DELIVERY PARTNER ORDER
      List<String> restaurantIds = itemsByRestaurant.keys.toList();

      List<Map<String, dynamic>> deliveryItems = allItems.map((item) {
        final Map<String, dynamic> itemMap = Map<String, dynamic>.from(item as Map);
        return {
          ...itemMap,
          "restaurantName": itemMap['restaurantName'] ?? "Unknown Restaurant", 
          "restaurantId": itemMap['restaurantId'],
        };
      }).toList();

      final DocumentReference deliveryRef = FirebaseFirestore.instance
          .collection("delivery_partner_orders")
          .doc(masterRef.id);

      final deliveryData = {
        "orderId": masterRef.id,
        "userId": user.uid,
        "userName": userName,        
        "userPhone": userPhone,      
        "address": address,          
        "deliveryInstructions": deliveryInstructions, 
        "location": location,
        "destinationLocation": location["geoPoint"],        
        "restaurantIds": restaurantIds, 
        "deliveryFee": deliveryFee,
        "items": deliveryItems,  
        "total": totalAmount,
        "payment": payment,
        "status": "searching_for_partner", 
        "timestamp": timestamp,
        "createdAt": createdDate,
      };

      batch.set(deliveryRef, deliveryData);

      // STEP 5: ORDER STATUS
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        fcmToken = "";
      }

      final DocumentReference statusRef = FirebaseFirestore.instance
          .collection("order_status")
          .doc(masterRef.id);

      final statusData = {
        ...masterOrderData,
        "orderId": masterRef.id,
        "status": "pending",
        "timestamp": timestamp,
        "userId": user.uid,
        "fcmToken": fcmToken ?? "no_token",
        "restaurantId": primaryRestaurantId,
        "userName": userName,
        "userPhone": userPhone,
        "address": address,
        "deliveryInstructions": deliveryInstructions,
        "location": location,
        "destinationLocation": location["geoPoint"],
        "deliveryFee": deliveryFee,
        "items": deliveryItems, 
        "total": totalAmount,
        "payment": payment,
        "createdAt": createdDate,
        "subtotal": subtotal,
      };

      batch.set(statusRef, statusData);

      // STEP 5.5: USER HISTORY
      final DocumentReference userHistoryRef = FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .collection("order_history")
          .doc(masterRef.id);

      final historyData = Map<String, dynamic>.from(masterOrderData);
      historyData["orderId"] = masterRef.id;
      batch.set(userHistoryRef, historyData);

      // STEP 5.7: STOCK UPDATE
      for (var item in allItems) {
        final Map<String, dynamic> itemMap = Map<String, dynamic>.from(item as Map);
        final String rId = itemMap['restaurantId']?.toString() ?? "";
        final String itemId = itemMap['id']?.toString() ?? ""; 
        final int qty = int.tryParse(itemMap['quantity'].toString()) ?? 0;

        if (rId.isNotEmpty && itemId.isNotEmpty && rId != 'instahub') {
          final DocumentReference stockRef = FirebaseFirestore.instance
              .collection('restaurants')
              .doc(rId)
              .collection('menu')
              .doc(itemId);

          batch.set(stockRef, {'stock': FieldValue.increment(-qty)}, SetOptions(merge: true));
        }
      }

      // STEP 6: COMMIT
      await batch.commit(); 

      final String? usedCoupon = widget.orderData['appliedCouponCode']?.toString().trim();
      if (usedCoupon != null && usedCoupon.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('usedCoupons')
            .doc(usedCoupon.toUpperCase())
            .set({
          'couponCode': usedCoupon.toUpperCase(),
          'orderId': masterRef.id,
          'usedAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Provider.of<CartProvider>(context, listen: false).clearCart();
        setState(() {
          orderId = masterRef.id;
          isLoading = false;
        });
      }
      
    } catch (e) {
      if (mounted) {
        setState(() { isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to place order: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _navigateToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const FoodHomeScreen()), 
      (route) => false,
    );
  }

  Widget _buildBillRow(String label, dynamic value, {bool isTotal = false}) {
    String valueText;
    Color valueColor = isTotal ? _primaryDark : const Color(0xFF1E293B);

    if (value is num) {
      valueText = '₹${value.abs().toStringAsFixed(2)}';
      if (value < 0) {
        valueColor = _successGreen;
        valueText = '- $valueText';
      }
    } else {
      valueText = value.toString();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label, 
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500, 
              fontSize: isTotal ? 16 : 14, 
              color: isTotal ? _primaryDark : const Color(0xFF64748B),
            ),
          ),
          Text(
            valueText, 
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600, 
              fontSize: isTotal ? 18 : 14, 
              color: isTotal ? _accentOrange : valueColor,
            ),
          ),
        ],
      ),
    );
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
        border: Border.all(color: const Color(0xFFE2E8F0).withOpacity(0.6)),
      ),
      child: child,
    );
  }

  Widget _buildInfoSection(IconData icon, String title, String content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _primaryDark.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _primaryDark, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title, 
                style: const TextStyle(
                  fontSize: 13, 
                  fontWeight: FontWeight.bold, 
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content.isNotEmpty ? content : 'N/A', 
                style: const TextStyle(
                  fontSize: 14, 
                  fontWeight: FontWeight.w600, 
                  color: _primaryDark,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final instructions = widget.orderData['deliveryInstructions'] ?? "";
    final items = (widget.orderData['items'] as List?) ?? [];
    final subtotal = double.tryParse(widget.orderData['subtotal'].toString()) ?? 0.0;
    final deliveryFee = double.tryParse(widget.orderData['deliveryFee'].toString()) ?? 0.0;
    final platformFee = double.tryParse(widget.orderData['platformFee'].toString()) ?? 0.0;
    final discount = double.tryParse(widget.orderData['discount'].toString()) ?? 0.0;
    final total = double.tryParse(widget.orderData['total'].toString()) ?? 0.0;

    final latitude = widget.orderData['deliveryLatitude'];
    final longitude = widget.orderData['deliveryLongitude'];

    String addressDisplay = widget.orderData['address'] ?? 'N/A';
    if (latitude != null && longitude != null) {
      addressDisplay += "\n($latitude, $longitude)";
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _navigateToHome();
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          title: const Text(
            "Order Status", 
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _primaryDark),
          ),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _primaryDark, size: 20),
            onPressed: _navigateToHome,
          ),
        ),
        body: isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: _accentOrange),
                    SizedBox(height: 16),
                    Text(
                      "Securing your order...",
                      style: TextStyle(fontWeight: FontWeight.bold, color: _primaryDark, fontSize: 15),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  children: [
                    // SUCCESS HERO HEADER
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_successGreen.withOpacity(0.08), Colors.white],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: _successGreen.withOpacity(0.2)),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 140,
                            height: 140,
                            child: Lottie.asset(
                              'assets/animations/order_success.json', 
                              repeat: false, 
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.check_circle_rounded, 
                                color: _successGreen, 
                                size: 100,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "Order Placed!", 
                            style: TextStyle(
                              fontSize: 24, 
                              fontWeight: FontWeight.w900, 
                              color: _primaryDark,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Your meal is being prepared with care", 
                            style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                          ),
                          if (orderId != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: _primaryDark,
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Text(
                                "ID: $orderId", 
                                style: const TextStyle(
                                  fontSize: 12, 
                                  color: Colors.white, 
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ORDER SUMMARY CARD
                    _buildCardContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.restaurant_menu_rounded, color: _accentOrange, size: 20),
                              SizedBox(width: 8),
                              Text("Order Items", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _primaryDark)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const ScrollPhysics(), // 👈 FIX: Uses valid ScrollPhysics()
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                            ),
                            itemBuilder: (context, index) {
                              final item = items[index] as Map<String, dynamic>;
                              final name = item['name'] ?? 'Item';
                              final qty = item['quantity'] ?? 1;
                              final price = double.tryParse(item['price'].toString()) ?? 0.0;
                              return Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _primaryDark.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      "${qty}x", 
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _primaryDark),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      name, 
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryDark), 
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    "₹${(price * qty).toStringAsFixed(2)}", 
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _primaryDark),
                                  ),
                                ],
                              );
                            },
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                          ),
                          _buildBillRow("Subtotal", subtotal),
                          _buildBillRow("Delivery Fee", deliveryFee),
                          _buildBillRow("Platform Fee", platformFee),
                          if (discount > 0) _buildBillRow("Discount", -discount),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                          ),
                          _buildBillRow("Total Amount", total, isTotal: true),
                        ],
                      ),
                    ),

                    // FULFILLMENT DETAILS CARD
                    _buildCardContainer(
                      child: Column(
                        children: [
                          _buildInfoSection(Icons.location_on_rounded, "DELIVERY LOCATION", addressDisplay),
                          if (instructions.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14.0),
                              child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                            ),
                            _buildInfoSection(Icons.note_alt_rounded, "DELIVERY INSTRUCTIONS", instructions),
                          ],
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14.0),
                            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                          ),
                          _buildInfoSection(Icons.payments_rounded, "PAYMENT METHOD", widget.orderData['payment'] ?? 'N/A'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // NAVIGATION ACTIONS
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _navigateToHome,
                        icon: const Icon(Icons.home_rounded, size: 20),
                        label: const Text(
                          "Back to Home", 
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}