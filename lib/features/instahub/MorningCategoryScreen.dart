import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/login_screen.dart';
import 'package:fastevergo_v1/features/cart/morning_cart_provider.dart';
import 'package:fastevergo_v1/features/cart/morning_cart_screen.dart';

// ✅ IMPORT GLOBAL AUTH GUARD
import 'package:fastevergo_v1/utils/auth_guards.dart';

class MorningCategoryScreen extends StatelessWidget {
  final String categoryName;

  const MorningCategoryScreen({super.key, required this.categoryName});

  // LOGIC PRESERVED 100%
  String _getTag(String categoryName) {
    switch (categoryName.trim()) {
      case "Fruits & Vegetables": return "fv";
      case "Dairy & Eggs": return "de";
      case "Meat & Seafood": return "ms";
      case "Grocery & Staples": return "gs";
      case "Bakery & Snacks": return "bs";
      case "Beverages": return "b";
      case "Household Essentials": return "he";
      case "Baby & Kids": return "bk";
      case "Pet Care": return "pc";
      default: return "";
    }
  }

  double _parseDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  void _addToCart(
    BuildContext context,
    Map<String, dynamic> item,
    String itemId,
    MorningCartProvider cartProvider,
  ) {
    if (!requireLoginGlobal("Login required to add morning items")) return;

    cartProvider.addItem(
      id: itemId,
      name: item["name"],
      price: _parseDouble(item["offerPrice"] ?? item["price"]),
      image: item["image"],
      restaurantId: "morning",
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Added to cart!", style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.black,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String tag = _getTag(categoryName);
    const Color morningRed = Color(0xFFD32F2F);

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFB),
      appBar: AppBar(
        title: Text(
          categoryName.toUpperCase(),
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1),
        ),
        backgroundColor: morningRed,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("morningitems")
            .where("tag", arrayContains: tag)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: morningRed));
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text("No items available.", style: GoogleFonts.inter(color: Colors.grey)),
            );
          }

          final items = snapshot.data!.docs;

          return Stack(
            children: [
              Consumer<MorningCartProvider>(
                builder: (context, cartProvider, _) {
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.62, // Adjusted for Jumbo Button
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index].data() as Map<String, dynamic>;
                      final itemId = items[index].id;
                      final quantity = cartProvider.getQuantity(itemId);

                      return TweenAnimationBuilder(
                        duration: Duration(milliseconds: 300 + (index * 50)),
                        tween: Tween<double>(begin: 0, end: 1),
                        curve: Curves.easeOutCubic,
                        builder: (context, double value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.scale(
                              scale: value,
                              child: _buildItemCard(
                                context,
                                item,
                                itemId,
                                quantity,
                                cartProvider,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
              _buildFloatingCartBar(context, morningRed),
            ],
          );
        },
      ),
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    Map<String, dynamic> item,
    String itemId,
    int quantity,
    MorningCartProvider cartProvider,
  ) {
    final price = _parseDouble(item["price"]);
    final offerPrice = _parseDouble(item["offerPrice"] ?? item["price"]);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // IMAGE SECTION
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Stack(
                children: [
                  Center(
                    child: CachedNetworkImage(
                      imageUrl: item["image"] ?? "",
                      fit: BoxFit.contain,
                      width: 100,
                      errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported, color: Colors.grey),
                    ),
                  ),
                  if (offerPrice < price)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD32F2F),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "OFFER",
                          style: GoogleFonts.montserrat(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // INFO SECTION
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item["name"] ?? "",
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, height: 1.2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  item["weight"] ?? "-",
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text("₹${offerPrice.toInt()}",
                        style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 17)),
                    if (offerPrice < price) ...[
                      const SizedBox(width: 4),
                      Text("₹${price.toInt()}",
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey, decoration: TextDecoration.lineThrough)),
                    ]
                  ],
                ),
                const SizedBox(height: 12),
                
                // JUMBO SELECTOR
                _JumboMorningSelector(
                  quantity: quantity,
                  onAdd: () => _addToCart(context, item, itemId, cartProvider),
                  onRemove: () {
                    if (!requireLoginGlobal("Login required to update items")) return;
                    cartProvider.reduceQuantity(itemId);
                  },
                  onIncrement: () => _addToCart(context, item, itemId, cartProvider),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingCartBar(BuildContext context, Color themeColor) {
    return Consumer<MorningCartProvider>(
      builder: (context, cartProvider, _) {
        if (cartProvider.items.isEmpty) return const SizedBox();

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut,
          bottom: 20,
          left: 16,
          right: 16,
          child: GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MorningCartScreen()));
            },
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [themeColor, themeColor.withOpacity(0.8)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: themeColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${cartProvider.items.length} ITEM(S)",
                          style: GoogleFonts.montserrat(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800)),
                      Text("₹${cartProvider.totalAmount.toStringAsFixed(0)}",
                          style: GoogleFonts.montserrat(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  Row(
                    children: [
                      Text("VIEW CART", style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                      const SizedBox(width: 8),
                      const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// 🛒 JUMBO SELECTOR FOR CONSISTENCY
class _JumboMorningSelector extends StatelessWidget {
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onIncrement;

  const _JumboMorningSelector({required this.quantity, required this.onAdd, required this.onRemove, required this.onIncrement});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: quantity == 0
          ? InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                height: 44, // Jumbo Height
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))],
                ),
                child: Center(
                  child: Text("ADD", style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                ),
              ),
            )
          : Container(
              height: 44,
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: onRemove,
                      child: const Center(child: Icon(Icons.remove_rounded, color: Colors.white, size: 22)),
                    ),
                  ),
                  Text('$quantity', style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                  Expanded(
                    child: InkWell(
                      onTap: onIncrement,
                      child: const Center(child: Icon(Icons.add_rounded, color: Colors.white, size: 22)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}