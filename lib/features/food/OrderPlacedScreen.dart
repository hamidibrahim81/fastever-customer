import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'cart/cart_provider.dart';
import '../home/home_screen.dart';
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
  bool _orderFailed = false;

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

  double _asDouble(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  Future<void> _placeOrder() async {
    if (hasOrderRun) return;
    setState(() {
      hasOrderRun = true;
      _orderFailed = false;
      isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Please sign in again.');

      final db = FirebaseFirestore.instance;
      final rawItems = widget.orderData['items'];
      if (rawItems is! List || rawItems.isEmpty) {
        throw Exception('Your order contains no items.');
      }

      final items = rawItems
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final grouped = <String, List<Map<String, dynamic>>>{};
      final quantities = <String, int>{};
      final menuRefs = <String, DocumentReference<Map<String, dynamic>>>{};
      for (final item in items) {
        final restaurantId = (item['restaurantId'] ?? '').toString().trim();
        final itemId = (item['id'] ?? '').toString().trim();
        final quantity = _asInt(item['quantity']);
        if (restaurantId.isEmpty || itemId.isEmpty || quantity <= 0) {
          throw Exception('An item has invalid restaurant, ID, or quantity.');
        }
        grouped.putIfAbsent(restaurantId, () => []).add(item);
        // Existing InstaHub products may not be stored in restaurants/menu.
        if (restaurantId != 'instahub') {
          final key = '$restaurantId/$itemId';
          quantities[key] = (quantities[key] ?? 0) + quantity;
          menuRefs[key] = db.collection('restaurants').doc(restaurantId)
              .collection('menu').doc(itemId);
        }
      }

      final subtotal = _asDouble(widget.orderData['subtotal']);
      final discount = _asDouble(widget.orderData['discount']);
      final deliveryFee = _asDouble(widget.orderData['deliveryFee']);
      final platformFee = _asDouble(widget.orderData['platformFee']);
      final tipAmount = _asDouble(widget.orderData['tipAmount']);
      final total = _asDouble(widget.orderData['total']);
      final expected = subtotal + deliveryFee + platformFee + tipAmount - discount;
      if ([subtotal, discount, deliveryFee, platformFee, tipAmount, total]
              .any((v) => !v.isFinite || v < 0) ||
          (total - expected).abs() > 0.02) {
        throw Exception('Order amount mismatch. Please return to cart.');
      }

      final lat = _asDouble(widget.orderData['deliveryLatitude']);
      final lng = _asDouble(widget.orderData['deliveryLongitude']);
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180 ||
          (lat == 0 && lng == 0)) {
        throw Exception('Please choose a valid delivery location.');
      }
      final geoPoint = GeoPoint(lat, lng);
      final location = <String, dynamic>{
        'geoPoint': geoPoint,
        'latitude': lat,
        'longitude': lng,
      };
      final address = (widget.orderData['address'] ?? '').toString();
      final payment = (widget.orderData['payment'] ?? 'COD').toString();
      final instructions =
          (widget.orderData['deliveryInstructions'] ?? '').toString();
      final coupon = widget.orderData['appliedCouponCode']?.toString().trim();
      final createdAt = DateTime.now().toIso8601String();
      final timestamp = FieldValue.serverTimestamp();
      final primaryRestaurantId = grouped.keys.first;
      final restaurantIds = grouped.keys.toList();

      String fcmToken = '';
      try {
        fcmToken = await FirebaseMessaging.instance.getToken() ?? '';
      } catch (e) {
        debugPrint('FCM token unavailable: $e');
      }

      // All order records use the order_status master ID. A transaction avoids
      // partially-created orders and prevents stock from becoming negative.
      final statusRef = db.collection('order_status').doc();
      final masterRef = db.collection('orders').doc(statusRef.id);
      final deliveryRef =
          db.collection('delivery_partner_orders').doc(masterRef.id);
      final historyRef = db.collection('users').doc(user.uid)
          .collection('order_history').doc(masterRef.id);
      final userRef = db.collection('users').doc(user.uid);
      final restaurantRefs = <String, DocumentReference<Map<String, dynamic>>>{
        for (final id in restaurantIds.where((id) => id != 'instahub'))
          id: db.collection('restaurants').doc(id),
      };
      final splitRefs = <String, DocumentReference<Map<String, dynamic>>>{
        for (final id in restaurantIds)
          id: db.collection('restaurant_orders').doc(),
      };
      final usedCouponRef = coupon != null && coupon.isNotEmpty
          ? userRef.collection('usedCoupons').doc(coupon.toUpperCase())
          : null;

      await db.runTransaction((transaction) async {
        // Firestore requires transaction reads to precede all writes.
        final existing = await transaction.get(statusRef);
        if (existing.exists) throw Exception('Master order already exists.');
        final userDoc = await transaction.get(userRef);
        final restaurantDocs = <String, Map<String, dynamic>>{};
        for (final entry in restaurantRefs.entries) {
          final doc = await transaction.get(entry.value);
          if (!doc.exists) throw Exception('Restaurant is unavailable.');
          restaurantDocs[entry.key] = doc.data() ?? {};
        }
        final menuDocs = <String, Map<String, dynamic>>{};
        for (final entry in menuRefs.entries) {
          final doc = await transaction.get(entry.value);
          if (!doc.exists) throw Exception('A menu item is unavailable.');
          menuDocs[entry.key] = doc.data() ?? {};
        }
        if (usedCouponRef != null) {
          final used = await transaction.get(usedCouponRef);
          if (used.exists) throw Exception('This coupon has already been used.');
        }

        for (final entry in quantities.entries) {
          final available = _asInt(menuDocs[entry.key]?['stock']);
          if (available < entry.value) {
            throw Exception('Insufficient stock for an item in your cart.');
          }
        }
        // Check prices again in the same transaction as stock reservation.
        for (final item in items) {
          final rid = item['restaurantId'].toString();
          if (rid == 'instahub') continue;
          final key = '$rid/${item['id']}';
          final currentPrice = _asDouble(menuDocs[key]?['price']);
          if ((currentPrice - _asDouble(item['price'])).abs() > 0.01) {
            throw Exception('Menu prices changed. Please review your cart.');
          }
        }

        final userSnapshot = Map<String, dynamic>.from(userDoc.data() ?? {});
        final userName = (widget.orderData['name'] ??
                user.displayName ?? userSnapshot['name'] ?? 'Customer')
            .toString();
        final userPhone = (widget.orderData['phone'] ??
                user.phoneNumber ?? userSnapshot['phone'] ?? '')
            .toString();

        final restaurantSnapshots = <String, dynamic>{};
        for (final id in restaurantIds) {
          final data = restaurantDocs[id] ?? <String, dynamic>{};
          restaurantSnapshots[id] = {
            'restaurantId': id,
            'name': data['name'] ?? (id == 'instahub' ? 'InstaHub' : ''),
            'phone': data['phone'] ?? data['phonenumber'] ?? '',
            'address': data['address'] ?? '',
            'latitude': data['latitude'],
            'longitude': data['longitude'],
            'statusAtOrder': data['status'],
            'prepTime': data['prepTime'],
          };
        }
        final enrichedItems = <Map<String, dynamic>>[];
        for (final item in items) {
          final rid = item['restaurantId'].toString();
          final key = '$rid/${item['id']}';
          final menu = menuDocs[key] ?? <String, dynamic>{};
          enrichedItems.add({
            ...item,
            'restaurantName': restaurantSnapshots[rid]?['name'] ?? '',
            'menuSnapshot': {
              'name': menu['name'] ?? item['name'],
              'price': menu['price'] ?? item['price'],
              'image': menu['image'] ?? menu['imageUrl'] ?? item['image'],
              'tags': menu['tags'] ?? [],
            },
          });
        }

        final common = <String, dynamic>{
          'orderId': statusRef.id,
          'masterOrderId': statusRef.id,
          'userId': user.uid,
          'userName': userName,
          'userPhone': userPhone,
          'items': enrichedItems,
          'restaurantId': primaryRestaurantId,
          'restaurantIds': restaurantIds,
          'restaurantDetails': restaurantSnapshots,
          'subtotal': subtotal,
          'discount': discount,
          'deliveryFee': deliveryFee,
          'platformFee': platformFee,
          'tipAmount': tipAmount,
          'total': total,
          'timestamp': timestamp,
          'createdAt': createdAt,
          'status': 'pending',
          'address': address,
          'deliveryInstructions': instructions,
          'payment': payment,
          'paymentStatus': 'pending',
          'location': location,
          'destinationLocation': geoPoint,
          'deliveryLatitude': lat,
          'deliveryLongitude': lng,
          'appliedCouponCode': coupon,
          'platform': 'flutter_customer_app',
        };
        final partnerSnapshot = <String, dynamic>{
          'partnerId': null,
          'partnerName': null,
          'partnerPhone': null,
          'assignedAt': null,
          'status': 'unassigned',
        };
        final splitIds = <String, String>{
          for (final entry in splitRefs.entries) entry.key: entry.value.id,
        };
        // order_status is the authoritative master document. Every other
        // collection is a projection of this order, linked by the same ID.
        final restaurantOrdersSnapshot = <String, dynamic>{};
        for (final entry in grouped.entries) {
          final rid = entry.key;
          final rItems = enrichedItems
              .where((item) => item['restaurantId'] == rid).toList();
          final rSubtotal = rItems.fold<double>(0, (sum, item) =>
              sum + _asDouble(item['price']) * _asInt(item['quantity']));
          restaurantOrdersSnapshot[rid] = {
            'orderId': splitIds[rid],
            'masterOrderId': statusRef.id,
            'restaurantId': rid,
            'restaurantDetails': restaurantSnapshots[rid],
            'items': rItems,
            'subtotal': rSubtotal,
            'status': 'pending',
          };
        }
        final deliveryOrderSnapshot = <String, dynamic>{
          'orderId': statusRef.id,
          'userId': user.uid,
          'restaurantIds': restaurantIds,
          'pickupRestaurants': restaurantSnapshots,
          'items': enrichedItems,
          'address': address,
          'location': location,
          'destinationLocation': geoPoint,
          'deliveryInstructions': instructions,
          'deliveryFee': deliveryFee,
          'tipAmount': tipAmount,
          'total': total,
          'payment': payment,
          'status': 'searching_for_partner',
          'deliveryPartner': partnerSnapshot,
        };
        final statusData = <String, dynamic>{
          ...common,
          'masterCollection': 'order_status',
          'fcmToken': fcmToken.isEmpty ? 'no_token' : fcmToken,
          'customerDetails': {
            'userId': user.uid,
            'name': userName,
            'phone': userPhone,
            'email': user.email,
            'address': address,
            'deliveryLatitude': lat,
            'deliveryLongitude': lng,
          },
          'orderDetails': {
            'items': enrichedItems,
            'subtotal': subtotal,
            'discount': discount,
            'deliveryFee': deliveryFee,
            'platformFee': platformFee,
            'tipAmount': tipAmount,
            'total': total,
            'payment': payment,
            'paymentStatus': 'pending',
            'appliedCouponCode': coupon,
          },
          'restaurantOrders': restaurantOrdersSnapshot,
          'deliveryOrder': deliveryOrderSnapshot,
          'deliveryPartner': partnerSnapshot,
          'deliveryPartnerId': null,
          'deliveryPartnerStatus': 'searching_for_partner',
          'restaurantOrderIds': splitIds,
          'orderStatusHistory': [
            {'status': 'pending', 'at': createdAt},
          ],
          'sourceCollections': {
            'orders': masterRef.path,
            'restaurant_orders': {
              for (final entry in splitRefs.entries)
                entry.key: entry.value.path,
            },
            'delivery_partner_orders': deliveryRef.path,
            'order_status': statusRef.path,
            'order_history': historyRef.path,
          },
        };

        // Commit the master and its projections atomically.
        transaction.set(statusRef, statusData);
        transaction.set(masterRef, {
          ...common,
          'restaurantOrderIds': splitIds,
          'deliveryPartner': partnerSnapshot,
        });
        for (final entry in grouped.entries) {
          final id = entry.key;
          final splitItems = enrichedItems
              .where((item) => item['restaurantId'] == id).toList();
          final splitSubtotal = splitItems.fold<double>(0, (sum, item) =>
              sum + _asDouble(item['price']) * _asInt(item['quantity']));
          transaction.set(splitRefs[id]!, {
            ...common,
            'orderId': splitRefs[id]!.id,
            'masterOrderId': statusRef.id,
            'restaurantId': id,
            'restaurantDetails': restaurantSnapshots[id],
            'items': splitItems,
            'subtotal': splitSubtotal,
            // Master order owns delivery fees, discount, tip and grand total.
            // Keep full billing details here for reconciliation; do not
            // represent the restaurant's subtotal as the grand total.
            'restaurantSubtotal': splitSubtotal,
            'masterTotal': total,
            'total': splitSubtotal,
          });
        }
        transaction.set(deliveryRef, {
          ...common,
          'status': 'searching_for_partner',
          'deliveryPartner': partnerSnapshot,
          'deliveryPartnerId': null,
          'restaurantOrderIds': splitIds,
        });
        transaction.set(historyRef, {
          ...common,
          'restaurantOrderIds': splitIds,
        });
        for (final entry in quantities.entries) {
          transaction.update(menuRefs[entry.key]!, {
            'stock': FieldValue.increment(-entry.value),
          });
        }
        if (usedCouponRef != null) {
          transaction.set(usedCouponRef, {
            'couponCode': coupon!.toUpperCase(),
            'orderId': statusRef.id,
            'usedAt': timestamp,
          });
        }
      });

      if (!mounted) return;
      try {
        Provider.of<CartProvider>(context, listen: false).clearCart();
      } catch (e) {
        debugPrint('Order saved but cart clear failed: $e');
      }
      if (!mounted) return;
      setState(() {
        orderId = statusRef.id;
        isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Order placement failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        isLoading = false;
        hasOrderRun = false;
        _orderFailed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to place order: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  void _navigateToHome() {
    if (isLoading) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  Widget _buildBillRow(String label, dynamic value, {bool isTotal = false}) {
    String valueText;
    Color valueColor = isTotal ? _primaryDark : const Color(0xFF1E293B);

    if (value is num) {
      valueText = '\u20B9${value.abs().toStringAsFixed(2)}';
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
    final subtotal =
        double.tryParse(widget.orderData['subtotal'].toString()) ?? 0.0;
    final deliveryFee =
        double.tryParse(widget.orderData['deliveryFee'].toString()) ?? 0.0;
    final platformFee =
        double.tryParse(widget.orderData['platformFee'].toString()) ?? 0.0;
    final discount =
        double.tryParse(widget.orderData['discount'].toString()) ?? 0.0;
    final total = double.tryParse(widget.orderData['total'].toString()) ?? 0.0;
    final tipAmount = _asDouble(widget.orderData['tipAmount']);

    final latitude = widget.orderData['deliveryLatitude'];
    final longitude = widget.orderData['deliveryLongitude'];

    String addressDisplay = widget.orderData['address'] ?? 'N/A';
    if (latitude != null && longitude != null) {
      addressDisplay += "\n($latitude, $longitude)";
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !isLoading) _navigateToHome();
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          title: const Text(
            "Order Status",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: _primaryDark,
            ),
          ),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: _primaryDark,
              size: 20,
            ),
            onPressed: _navigateToHome,
          ),
        ),
        body: _orderFailed
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
                const SizedBox(height: 12),
                const Text('Order could not be placed'),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _placeOrder, child: const Text('Try Again')),
              ]))
            : isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: _accentOrange),
                    SizedBox(height: 16),
                    Text(
                      "Securing your order...",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _primaryDark,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: Column(
                  children: [
                    // SUCCESS HERO HEADER
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _successGreen.withOpacity(0.08),
                            Colors.white,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: _successGreen.withOpacity(0.2),
                        ),
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
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (orderId != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
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
                          ],
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
                              Icon(
                                Icons.restaurant_menu_rounded,
                                color: _accentOrange,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                "Order Items",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _primaryDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ListView.separated(
                            shrinkWrap: true,
                            physics:
                                const ScrollPhysics(), // Ã°Å¸â€˜Ë† FIX: Uses valid ScrollPhysics()
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Divider(
                                height: 1,
                                color: Color(0xFFF1F5F9),
                              ),
                            ),
                            itemBuilder: (context, index) {
                              final item = items[index] as Map<String, dynamic>;
                              final name = item['name'] ?? 'Item';
                              final qty = item['quantity'] ?? 1;
                              final price =
                                  double.tryParse(item['price'].toString()) ??
                                  0.0;
                              return Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _primaryDark.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      "${qty}x",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: _primaryDark,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: _primaryDark,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    "\u20B9${(price * qty).toStringAsFixed(2)}",
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _primaryDark,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          _buildBillRow("Subtotal", subtotal),
                          _buildBillRow("Delivery Fee", deliveryFee),
                          _buildBillRow("Platform Fee", platformFee),
                          if (discount > 0)
                            _buildBillRow("Discount", -discount),
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
                          _buildInfoSection(
                            Icons.location_on_rounded,
                            "DELIVERY LOCATION",
                            addressDisplay,
                          ),
                          if (instructions.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14.0),
                              child: Divider(
                                height: 1,
                                color: Color(0xFFF1F5F9),
                              ),
                            ),
                            _buildInfoSection(
                              Icons.note_alt_rounded,
                              "DELIVERY INSTRUCTIONS",
                              instructions,
                            ),
                          ],
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14.0),
                            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                          ),
                          _buildInfoSection(
                            Icons.payments_rounded,
                            "PAYMENT METHOD",
                            widget.orderData['payment'] ?? 'N/A',
                          ),
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
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
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
