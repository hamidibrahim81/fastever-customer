import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart'; // ✅ Added Provider Import
import 'cart/cart_provider.dart'; // ✅ Added Cart Provider Import
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

  @override
  void initState() {
    super.initState();
    // Ensure order is placed only once
    if (!hasOrderRun) {
      _placeOrder();
    }
  }

  Future<void> _placeOrder() async {
    if (hasOrderRun) return; 
    setState(() => hasOrderRun = true); // ✅ Prevent double order entry

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not signed in");

      // --- 1. DATA PREPARATION ---
      final List allItems = widget.orderData['items'] ?? [];
      
      // Extract numeric values safely
      final double deliveryFee = double.tryParse(widget.orderData['deliveryFee'].toString()) ?? 0.0;
      final double platformFee = double.tryParse(widget.orderData['platformFee'].toString()) ?? 0.0; // ✅ Extracted Platform Fee
      final double totalAmount = double.tryParse(widget.orderData['total'].toString()) ?? 0.0;
      final double subtotal = double.tryParse(widget.orderData['subtotal'].toString()) ?? 0.0;
      final double discount = double.tryParse(widget.orderData['discount'].toString()) ?? 0.0;

      // ✅ NEW: Extract instructions for the driver/restaurant
      final String deliveryInstructions = widget.orderData['deliveryInstructions'] ?? "";

      // Determine Primary ID 
      String primaryRestaurantId = widget.orderData['restaurantId']?.toString() ?? "UNKNOWN";
      
      // Fallback: If root ID is missing, try to find it in the first item
      if ((primaryRestaurantId == "UNKNOWN" || primaryRestaurantId.isEmpty) && allItems.isNotEmpty) {
        final firstItem = allItems.first as Map<String, dynamic>;
        primaryRestaurantId = firstItem['restaurantId']?.toString() ?? "UNKNOWN";
      }

      if (primaryRestaurantId == "UNKNOWN") {
        throw Exception("Critical Error: No Restaurant ID found in order data.");
      }

      // Group Items by Restaurant ID (for Split Orders)
      final Map<String, List<Map<String, dynamic>>> itemsByRestaurant = {};
      for (var item in allItems) {
        final String rId = item['restaurantId']?.toString() ?? "UNKNOWN";
        if (!itemsByRestaurant.containsKey(rId)) {
          itemsByRestaurant[rId] = [];
        }
        itemsByRestaurant[rId]!.add(item as Map<String, dynamic>);
      }

      // Common Data
      final timestamp = FieldValue.serverTimestamp();
      final createdDate = DateTime.now().toIso8601String();
      final address = widget.orderData['address'] ?? "N/A";
      final payment = widget.orderData['payment'] ?? "N/A";
      final location = widget.orderData['location'] ?? {};

      // Attempt to get Name/Phone from orderData first, then Auth user
      final String userName = widget.orderData['name'] ?? user.displayName ?? "Valued Customer";
      final String userPhone = widget.orderData['phone'] ?? user.phoneNumber ?? "N/A";

      // ==============================================================================
      // STEP 2: CREATE MASTER ORDER ('orders' collection)
      // ==============================================================================
      
      final masterOrderData = {
        "userId": user.uid,
        "userName": userName,
        "userPhone": userPhone,
        "items": allItems, 
        "subtotal": subtotal,
        "discount": discount,
        "deliveryFee": deliveryFee, 
        "platformFee": platformFee, // ✅ Saved separately in Master
        "total": totalAmount,
        "timestamp": timestamp,
        "createdAt": createdDate,
        "status": "pending",
        "restaurantId": primaryRestaurantId, 
        "address": address,
        "deliveryInstructions": deliveryInstructions, 
        "payment": payment,
        "location": location,
        "appliedCouponCode": widget.orderData['appliedCouponCode'],
        "platform": "flutter_customer_app",
      };

      final DocumentReference masterRef = await FirebaseFirestore.instance
          .collection("orders")
          .add(masterOrderData);

      await masterRef.update({"orderId": masterRef.id});
      
      debugPrint("✅ Master Order Created in 'orders': ${masterRef.id}");

      // Start Batch
      final batch = FirebaseFirestore.instance.batch();

      // ==============================================================================
      // STEP 3: CREATE SPLIT ORDERS ('restaurant_orders' collection)
      // ==============================================================================

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
          "platform": "flutter_customer_app",
        };

        batch.set(splitRef, splitOrderData);
      });

      // ==============================================================================
      // STEP 4: CREATE DELIVERY PARTNER ORDER ('delivery_partner_orders')
      // ==============================================================================
      
      List<String> restaurantIds = itemsByRestaurant.keys.toList();

      List<Map<String, dynamic>> deliveryItems = allItems.map((item) {
        final Map<String, dynamic> itemMap = item as Map<String, dynamic>;
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
      debugPrint("✅ Delivery Order staged for 'delivery_partner_orders'");

      // ==============================================================================
      // STEP 5: CREATE ORDER STATUS ('order_status' collection)
      // ==============================================================================

      final String? fcmToken = await FirebaseMessaging.instance.getToken();
      debugPrint("🔥 FCM TOKEN: $fcmToken");

      final DocumentReference statusRef = FirebaseFirestore.instance
          .collection("order_status")
          .doc(masterRef.id);

      final statusData = {
        ...masterOrderData, // ✅ Now includes platformFee automatically
        "orderId": masterRef.id,
        "status": "pending",
        "timestamp": timestamp,
        "userId": user.uid,
        "fcmToken": fcmToken,
        "restaurantId": primaryRestaurantId, 
      };

      batch.set(statusRef, statusData);

      // ==============================================================================
      // STEP 5.5: CREATE USER HISTORY
      // ==============================================================================

      final DocumentReference userHistoryRef = FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .collection("order_history")
          .doc(masterRef.id);

      final historyData = Map<String, dynamic>.from(masterOrderData);
      historyData["orderId"] = masterRef.id;
      batch.set(userHistoryRef, historyData);

      // ==============================================================================
      // STEP 5.7: ATOMIC STOCK DECREASE LOGIC
      // ==============================================================================
      for (var item in allItems) {
        final Map<String, dynamic> itemMap = item as Map<String, dynamic>;
        final String rId = itemMap['restaurantId']?.toString() ?? "";
        final String itemId = itemMap['id']?.toString() ?? ""; 
        final int qty = int.tryParse(itemMap['quantity'].toString()) ?? 0;

        if (rId.isNotEmpty && itemId.isNotEmpty && rId != 'instahub') {
          debugPrint("📉 DECREASING STOCK FOR -> Restaurant: $rId | Doc ID: $itemId | Qty: -$qty");

          final DocumentReference stockRef = FirebaseFirestore.instance
              .collection('restaurants')
              .doc(rId)
              .collection('menu')
              .doc(itemId);

          batch.update(stockRef, {'stock': FieldValue.increment(-qty)});
        }
      }

      // ==============================================================================
      // STEP 6: COMMIT & UI UPDATE
      // ==============================================================================

      await batch.commit(); 
      debugPrint("✅ Batch Committed successfully with stock updates");

      if (mounted) {
        Provider.of<CartProvider>(context, listen: false).clearCart();
        setState(() {
          orderId = masterRef.id;
          isLoading = false;
        });
      }
      
    } catch (e) {
      debugPrint("🔴 ERROR: $e");
      if (mounted) {
        setState(() { isLoading = false; });
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(SnackBar(content: Text("Failed to place order: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildBillRow(String label, dynamic value) {
    String valueText;
    Color? valueColor;
    bool isBold = label == 'Total';

    if (value is num) {
      valueText = '₹${value.abs().toStringAsFixed(2)}';
      if (value < 0) {
        valueColor = Colors.green;
        valueText = '- $valueText';
      }
    } else {
      valueText = value.toString();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w500, fontSize: 15, color: isBold ? Colors.black : Colors.grey[700])),
          Text(valueText, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w500, fontSize: 15, color: valueColor ?? (isBold ? Colors.black : Colors.grey[700]))),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(content.isNotEmpty ? content : 'N/A', style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final instructions = widget.orderData['deliveryInstructions'] ?? "";
    final items = (widget.orderData['items'] as List?) ?? [];
    final subtotal = double.tryParse(widget.orderData['subtotal'].toString()) ?? 0.0;
    final deliveryFee = double.tryParse(widget.orderData['deliveryFee'].toString()) ?? 0.0;
    final platformFee = double.tryParse(widget.orderData['platformFee'].toString()) ?? 0.0; // ✅ Added for UI
    final discount = double.tryParse(widget.orderData['discount'].toString()) ?? 0.0;
    final total = double.tryParse(widget.orderData['total'].toString()) ?? 0.0;

    final latitude = widget.orderData['location']?['latitude'];
    final longitude = widget.orderData['location']?['longitude'];

    String addressDisplay = widget.orderData['address'] ?? 'N/A';
    if (latitude != null && longitude != null) {
      addressDisplay += "\nLat: $latitude\nLong: $longitude";
    }

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const FoodHomeScreen()), (route) => false);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: const Text("Order Placed", style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 1,
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const FoodHomeScreen()), (route) => false);
          }),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.orange))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    const Text("Order Placed Successfully!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    SizedBox(width: 200, height: 200, child: Lottie.asset('assets/animations/order_success.json', repeat: false, errorBuilder: (_, __, ___) => const Icon(Icons.check_circle, color: Colors.green, size: 120))),
                    const SizedBox(height: 8),
                    if (orderId != null) Text("Order ID: $orderId", style: const TextStyle(fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic)),
                    const SizedBox(height: 24),

                    // Order Summary Card
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Order Summary", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index] as Map<String, dynamic>;
                                final name = item['name'] ?? 'Item';
                                final qty = item['quantity'] ?? 1;
                                final price = double.tryParse(item['price'].toString()) ?? 0.0;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(child: Text("$name x$qty", style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
                                      Text("₹${(price * qty).toStringAsFixed(2)}", style: const TextStyle(fontSize: 14)),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const Divider(height: 24),
                            _buildBillRow("Subtotal", subtotal),
                            _buildBillRow("Delivery Fee", deliveryFee),
                            _buildBillRow("Platform Fee", platformFee), // ✅ Platform Fee UI added
                            if (discount > 0) _buildBillRow("Discount", -discount),
                            const SizedBox(height: 8),
                            _buildBillRow("Total", total),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Address + Payment + Instructions Card
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoSection("Delivery Address", addressDisplay),
                            if (instructions.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildInfoSection("Delivery Instructions", instructions), 
                            ],
                            const SizedBox(height: 16),
                            _buildInfoSection("Payment Method", widget.orderData['payment'] ?? 'N/A'),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const FoodHomeScreen()), (route) => false);
                          },
                          icon: const Icon(Icons.home),
                          label: const Text("Home"),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}