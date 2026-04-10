import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:fastevergo_v1/features/cart/morning_cart_provider.dart';
import 'package:fastevergo_v1/features/cart/morning_cart_screen.dart'; 

class MorningCategoryScreen extends StatelessWidget {
  final String categoryName;

  const MorningCategoryScreen({super.key, required this.categoryName});

  /// Map category names → Firestore tags
  String _getTag(String categoryName) {
    switch (categoryName.trim()) {
      case "Fruits & Vegetables":
        return "fv";
      case "Dairy & Eggs":
        return "de";
      case "Meat & Seafood":
        return "ms";
      case "Grocery & Staples":
        return "gs";
      case "Bakery & Snacks":
        return "bs";
      case "Beverages":
        return "b";
      case "Household Essentials":
        return "he";
      case "Baby & Kids":
        return "bk";
      case "Pet Care":
        return "pc";
      default:
        return "";
    }
  }

  // Helper function to handle adding an item to the cart
  void _addToCart(
    BuildContext context,
    Map<String, dynamic> item,
    String itemId,
    MorningCartProvider cartProvider,
  ) {
    cartProvider.addItem(
      id: itemId,
      name: item["name"],
      price: (item["offerPrice"] ?? item["price"]).toDouble(),
      image: item["image"],
      restaurantId: "morning",
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Item added to cart!"),
        duration: Duration(milliseconds: 700),
      ),
    );
  }

  // Helper function to build the individual item card
  Widget _buildItemCard(
    BuildContext context,
    Map<String, dynamic> item,
    String itemId,
    int quantity,
    MorningCartProvider cartProvider,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero, // ✅ SHARP SQUARE BOX
        border: Border.all(color: Colors.orange.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.deepOrange.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Image.network(
              item["image"] ?? "",
              fit: BoxFit.cover, // ✅ PERFECT FIT INSIDE BOX
              width: double.infinity,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.image, size: 50),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item["name"] ?? "",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            "Weight: ${item["weight"] ?? "-"}",
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "₹${item["offerPrice"] ?? item["price"]}",
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange,
            ),
          ),
          if (item["offerPrice"] != null &&
              item["offerPrice"] < item["price"])
            Text(
              "₹${item["price"]}",
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          const SizedBox(height: 8),
          quantity == 0
              ? GestureDetector(
                  onTap: () {
                    _addToCart(context, item, itemId, cartProvider);
                  },
                  child: Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange,
                      borderRadius: BorderRadius.circular(4), // Subtle radius for button
                    ),
                    child: const Center(
                      child: Text(
                        "ADD",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                )
              : Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: Colors.deepOrange, width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      GestureDetector(
                        onTap: () => cartProvider.removeItem(itemId),
                        child: const Icon(Icons.remove,
                            color: Colors.deepOrange, size: 20),
                      ),
                      Text(
                        "$quantity",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange),
                      ),
                      GestureDetector(
                        onTap: () {
                          _addToCart(context, item, itemId, cartProvider);
                        },
                        child: const Icon(Icons.add,
                            color: Colors.deepOrange, size: 20),
                      ),
                    ],
                  ),
                ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String tag = _getTag(categoryName);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          categoryName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("morningitems")
            .where("tag", arrayContains: tag)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("No items available in this category"),
            );
          }

          final items = snapshot.data!.docs;

          return Stack(
            children: [
              // Grid of items (Main content)
              Consumer<MorningCartProvider>(
                builder: (context, cartProvider, _) {
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), 
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.65, // Adjusted for content
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item =
                          items[index].data() as Map<String, dynamic>;
                      final itemId = items[index].id;
                      final quantity = cartProvider.getQuantity(itemId);

                      return _buildItemCard(
                        context,
                        item,
                        itemId,
                        quantity,
                        cartProvider,
                      );
                    },
                  );
                },
              ),

              // Morning Cart Bar (Floating at the bottom)
              Consumer<MorningCartProvider>(
                builder: (context, cartProvider, _) {
                  // ✅ FIX: Using .isEmpty instead of totalItems check
                  if (cartProvider.items.isEmpty) return const SizedBox();

                  return Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MorningCartScreen(),
                          ),
                        );
                      },
                      child: Container(
                        height: 60,
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              // ✅ FIX: Total items from map length
                              "${cartProvider.items.length} item(s) in cart",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                            Text(
                              // ✅ FIX: totalAmount instead of totalPrice
                              "₹${cartProvider.totalAmount.toStringAsFixed(0)}",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}