import 'dart:ui'; // Required for ImageFilter.blur
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/login_screen.dart';

// ✅ IMPORT AUTH GUARD
import 'package:fastevergo_v1/utils/auth_guards.dart';

// Instahub Provider & Cart Bar
import 'instahub_cart_provider.dart';
import 'instahub_cart_bar.dart';

class CategoryScreen extends StatefulWidget {
  final String categoryName;
  const CategoryScreen({super.key, required this.categoryName});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen>
    with SingleTickerProviderStateMixin {
  
  String _getTag(String categoryName) {
    final normalized = categoryName.trim().toLowerCase();
    switch (normalized) {
      case "fruits & vegetables": return "fv";
      case "dairy & eggs": return "de";
      case "meat & seafood": return "ms";
      case "grocery & staples": return "gs";
      case "bakery & snacks": return "bs";
      case "beverages": return "b";
      case "household essentials": return "he";
      case "baby & kids": return "bk";
      case "pet care": return "pc";
      default: return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    final tag = _getTag(widget.categoryName);
    final cartProvider = Provider.of<InstahubCartProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          widget.categoryName,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            fontSize: 20,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange, Color(0xFFFF8C00)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 8,
        shadowColor: Colors.orange.withOpacity(0.4),
        foregroundColor: Colors.white,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: tag.isEmpty
          ? Center(
              child: Text(
                "Category tag not found for: ${widget.categoryName}",
                style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
              ),
            )
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("instaitems")
                  .where("tag", arrayContains: tag)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.orange)),
                  );
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          "No items found in ${widget.categoryName}",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }

                final items = snapshot.data!.docs;

                return Stack(
                  children: [
                    GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.72, 
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index].data() as Map<String, dynamic>;
                        
                        return TweenAnimationBuilder(
                          duration: Duration(milliseconds: 400 + (index * 50)),
                          tween: Tween<double>(begin: 0, end: 1),
                          curve: Curves.easeOutCubic,
                          builder: (context, double value, child) {
                            return Transform.translate(
                              offset: Offset(0, 30 * (1 - value)),
                              child: Opacity(
                                opacity: value,
                                child: _ItemCard(item: item),
                              ),
                            );
                          },
                        );
                      },
                    ),

                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.elasticOut,
                      bottom: cartProvider.isNotEmpty ? 20 : -100,
                      left: 16,
                      right: 16,
                      child: const InstahubCartBar(),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _ItemCard extends StatefulWidget {
  final Map<String, dynamic> item;
  const _ItemCard({required this.item});

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  int quantity = 0;
  static const String storeId = "instahub_store";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialCartState();
    });
  }

  void _loadInitialCartState() {
    final cart = Provider.of<InstahubCartProvider>(context, listen: false);
    final itemId = widget.item["id"] ?? widget.item["name"];
    final cartItem = cart.getItem(itemId); 

    if (cartItem != null) {
      setState(() {
        quantity = cartItem.quantity; 
      });
    }
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
            ],
            border: Border.all(color: Colors.orange.shade100),
          ),
          child: Icon(icon, color: Colors.orange, size: 20),
        ),
      ),
    );
  }

  void _updateCartItem({required int newQuantity}) {
    if (!requireLoginGlobal("Login required to add InstaHub items")) return;

    final cart = Provider.of<InstahubCartProvider>(context, listen: false);
    final item = widget.item;
    final itemId = item["id"] ?? item["name"];

    final rawPrice = item["offerPrice"] ?? item["price"] ?? 0;
    final basePrice = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice.toString()) ?? 0.0;

    setState(() {
      quantity = newQuantity;
    });

    if (newQuantity > 0) {
      cart.updateItem(
        id: itemId,
        name: item["name"],
        price: basePrice, 
        restaurantId: storeId,
        image: item["image"],
        quantity: newQuantity, 
      );
    } else {
      cart.removeItem(itemId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final rawPrice = item["offerPrice"] ?? item["price"] ?? 0;
    final basePrice = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice.toString()) ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: CachedNetworkImage(
                    imageUrl: item["image"] ?? "",
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.grey.shade100),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey.shade100,
                      child: const Icon(Icons.fastfood, size: 40, color: Colors.grey),
                    ),
                  ),
                ),
                // FIXED: PROPER FROSTED GLASS EFFECT
                Positioned(
                  top: 10,
                  right: 10,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.5)),
                        ),
                        child: Text(
                          "₹${basePrice.toInt()}",
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item["name"]?.trim() ?? "Unnamed Item",
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF2D3436),
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: quantity == 0
                      ? SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            key: const ValueKey('add_btn'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () => _updateCartItem(newQuantity: 1),
                            child: const Text(
                              "ADD",
                              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
                            ),
                          ),
                        )
                      : Container(
                          key: const ValueKey('qty_ctrl'),
                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _qtyButton(Icons.remove, () {
                                if (quantity > 1) {
                                  _updateCartItem(newQuantity: quantity - 1);
                                } else {
                                  _updateCartItem(newQuantity: 0);
                                }
                              }),
                              Text(
                                "$quantity",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: Colors.orange,
                                ),
                              ),
                              _qtyButton(Icons.add, () {
                                _updateCartItem(newQuantity: quantity + 1);
                              }),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}