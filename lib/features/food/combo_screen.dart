import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';

// ✅ IMPORT AUTH GUARD
import 'package:fastevergo_v1/utils/auth_guards.dart';
import '../food/cart/cart_provider.dart';
import '../food/cart/cart_bar.dart';
import 'active_order_bottom_bar.dart';

/// ------------------------------
/// Helper Parsers
/// ------------------------------
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

class ComboScreen extends StatefulWidget {
  const ComboScreen({super.key});

  @override
  State<ComboScreen> createState() => _ComboScreenState();
}

class _ComboScreenState extends State<ComboScreen> with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // ✅ Setup background animation loop for pulsing card outlines
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double cartBarHeightPadding = 110.0; 

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text(
          "MEGA COMBO DEALS",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      bottomNavigationBar: const ActiveOrderBottomBar(),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collectionGroup('menu')
                .where('tags', arrayContains: 'combo_deals')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return ListView.builder(
                  padding: const EdgeInsets.only(left: 14, right: 14, top: 12, bottom: cartBarHeightPadding),
                  itemCount: 5,
                  itemBuilder: (context, index) => const ComboShimmerCard(),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.local_offer_outlined, size: 72, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text(
                          "No Active Combos Available",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black54),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Check back later for exclusive multi-item savings!",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final comboDeals = snapshot.data!.docs;

              return ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(left: 14, right: 14, top: 12, bottom: cartBarHeightPadding),
                itemCount: comboDeals.length,
                itemBuilder: (context, index) {
                  final doc = comboDeals[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final id = doc.id;

                  final String imageUrl = data['imageUrl'] ?? '';
                  final String comboName = data['name'] ?? 'Combo Deal';
                  final String restaurantName = data['restaurantName'] ?? 'Unknown Restaurant';
                  
                  final double price = parseDouble(data['price']);
                  // ✅ Read 'mrp' field directly from database setup
                  final double mrp = parseDouble(data['mrp'] ?? data['promoOfferPrice'] ?? price);
                  
                  final String restaurantId = data['restaurantId'] ?? doc.reference.parent.parent?.id ?? '';
                  final int stockAvailable = parseInt(data['stock'], defaultValue: 0);
                  final String offerPriority = data['offerPriority'] ?? 'low';

                  return AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return ComboCard(
                        id: id,
                        imageUrl: imageUrl,
                        comboName: comboName,
                        restaurantName: restaurantName,
                        price: price,
                        mrp: mrp,
                        restaurantId: restaurantId,
                        stockAvailable: stockAvailable,
                        isInstaHub: data['isInstaHub'] == true,
                        offerPriority: offerPriority,
                        pulseValue: _pulseAnimation.value,
                      );
                    },
                  );
                },
              );
            },
          ),

          /// 🛒 Bottom Cart Bar
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CartBar(),
          ),
        ],
      ),
    );
  }
}

class ComboCard extends StatelessWidget {
  final String id;
  final String imageUrl;
  final String comboName;
  final String restaurantName;
  final String restaurantId;
  final double price; 
  final double mrp;   
  final int stockAvailable;
  final bool isInstaHub;
  final String offerPriority;
  final double pulseValue;

  const ComboCard({
    super.key,
    required this.id,
    required this.imageUrl,
    required this.comboName,
    required this.restaurantName,
    required this.price,
    required this.mrp,
    required this.restaurantId,
    required this.stockAvailable,
    required this.isInstaHub,
    required this.offerPriority,
    required this.pulseValue,
  });

  // ✅ Maps priority parameters to target colors smoothly
  Color _getPriorityBlinkColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return const Color(0xFFFF2442).withOpacity(pulseValue); 
      case 'medium':
        return const Color(0xFFFFB300).withOpacity(pulseValue); 
      case 'low':
      default:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final bool hasDiscount = mrp > price;
    
    int discountPercent = 0;
    if (hasDiscount && mrp > 0) {
      discountPercent = (((mrp - price) / mrp) * 100).round();
    }

    final bool isMegaOffer = discountPercent >= 50 || offerPriority.toLowerCase() == 'high';
    final Color activeBlinkColor = _getPriorityBlinkColor(offerPriority);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      // ✅ Dynamic pulsing layout wrappers for promotional priorities
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: offerPriority != 'low' ? activeBlinkColor : (isMegaOffer ? Colors.amber.shade400 : Colors.transparent),
          width: (offerPriority != 'low' || isMegaOffer) ? 2.0 : 0.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isMegaOffer ? Colors.orange.withOpacity(0.15) : Colors.black12,
            blurRadius: 6,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Card(
        margin: EdgeInsets.zero, // Resets card margin to align with parent box decoration
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Image Block
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                  child: ColorFiltered(
                    colorFilter: stockAvailable <= 0 
                      ? const ColorFilter.mode(Colors.grey, BlendMode.saturation) 
                      : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 125,
                      height: 125,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Shimmer.fromColors(
                        baseColor: Colors.grey.shade300,
                        highlightColor: Colors.grey.shade100,
                        child: Container(width: 125, height: 125, color: Colors.white),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 125,
                        height: 125,
                        color: Colors.grey.shade100,
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                if (discountPercent > 0 && stockAvailable > 0)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: isMegaOffer 
                          ? const LinearGradient(colors: [Colors.deepOrange, Colors.purple]) 
                          : LinearGradient(colors: [Colors.red.shade700, Colors.red.shade400]),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: isMegaOffer ? [const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))] : null,
                      ),
                      child: Text(
                        isMegaOffer ? "🔥 $discountPercent% OFF" : "$discountPercent% OFF",
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                      ),
                    ),
                  ),
              ],
            ),
            
            // Details Block
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isMegaOffer ? Colors.amber.shade100 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isMegaOffer ? "BUMPER COMBO" : "COMBO DEAL",
                        style: TextStyle(
                          color: isMegaOffer ? Colors.deepOrange.shade900 : Colors.orange, 
                          fontSize: 9, 
                          fontWeight: FontWeight.bold, 
                          letterSpacing: 0.5
                        ),
                      ),
                    ),
                    Text(
                      comboName,
                      style: TextStyle(
                        fontSize: 15, 
                        fontWeight: FontWeight.bold, 
                        color: stockAvailable <= 0 ? Colors.grey : Colors.black87
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      restaurantName,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    
                    // Price and Button Layout
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ✅ MRP Strike-Through Style Layout Section
                            if (hasDiscount)
                              Text(
                                "MRP ₹${mrp.toStringAsFixed(0)}", 
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.lineThrough,
                                  decorationThickness: 1.8,
                                ),
                              ),
                            // ✅ Offer price active layout layer
                            Text(
                              "₹${price.toStringAsFixed(0)}", 
                              style: TextStyle(
                                color: stockAvailable <= 0 ? Colors.grey : primaryColor,
                                fontSize: 17,
                                fontWeight: FontWeight.w800, // Fixed syntax error parameters
                              ),
                            ),
                          ],
                        ),
                        
                        Selector<CartProvider, int>(
                          selector: (_, cart) => cart.getQuantity(id),
                          builder: (context, quantity, child) {
                            final cartProvider = Provider.of<CartProvider>(context, listen: false);
                            
                            if (stockAvailable <= 0) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  "SOLD OUT",
                                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              );
                            }

                            if (quantity > 0) {
                              return Container(
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove, size: 16, color: Colors.red),
                                      onPressed: () {
                                        if (!requireLoginGlobal("Please login to update cart")) return;
                                        cartProvider.reduceQuantity(id);
                                      },
                                    ),
                                    Text(
                                      '$quantity',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.add, size: 16, color: primaryColor),
                                      onPressed: () {
                                        if (!requireLoginGlobal("Please login to update cart")) return;
                                        if (quantity >= stockAvailable) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text("Only $stockAvailable left in stock!"))
                                          );
                                          return;
                                        }
                                        // ✅ Securely loads ONLY the discount offer price
                                        cartProvider.addItem(
                                          id: id,
                                          name: comboName,
                                          price: price, 
                                          restaurantId: restaurantId,
                                          image: imageUrl,
                                          isInstaHub: isInstaHub,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            }
                            
                            return ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                minimumSize: const Size(80, 36),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              onPressed: () {
                                if (!requireLoginGlobal("Please login to add combo deals")) return;
                                // ✅ Securely loads ONLY the discount offer price
                                cartProvider.addItem(
                                  id: id,
                                  name: comboName,
                                  price: price, 
                                  restaurantId: restaurantId,
                                  image: imageUrl,
                                  isInstaHub: isInstaHub,
                                );
                              },
                              child: const Text("ADD", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ComboShimmerCard extends StatelessWidget {
  const ComboShimmerCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(width: 125, height: 125, color: Colors.white),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 12, width: 60, color: Colors.white),
                    const SizedBox(height: 6),
                    Container(height: 15, width: 140, color: Colors.white),
                    const SizedBox(height: 4),
                    Container(height: 12, width: 90, color: Colors.white),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(height: 16, width: 50, color: Colors.white),
                        Container(height: 32, width: 75, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}