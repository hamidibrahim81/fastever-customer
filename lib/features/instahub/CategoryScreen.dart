
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
      case "fruits & vegetables":
        return "fv";
      case "dairy & eggs":
        return "de";
      case "meat & seafood":
        return "ms";
      case "grocery & staples":
        return "gs";
      case "bakery & snacks":
        return "bs";
      case "beverages":
        return "b";
      case "household essentials":
        return "he";
      case "baby & kids":
        return "bk";
      case "pet care":
        return "pc";
      default:
        return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    final tag = _getTag(widget.categoryName);
    final cartProvider = Provider.of<InstahubCartProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: tag.isEmpty
          ? Center(
              child: Text(
                "Category tag not found for: ${widget.categoryName}",
                style: const TextStyle(color: Colors.grey),
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
                    child: CircularProgressIndicator(color: Colors.orange),
                  );
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      "No items found in ${widget.categoryName}",
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  );
                }

                final items = snapshot.data!.docs;

                return Stack(
                  children: [
                    GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item =
                            items[index].data() as Map<String, dynamic>;
                        return _ItemCard(item: item);
                      },
                    ),

                    // Instahub Cart Bar (Animated)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      bottom: cartProvider.isNotEmpty ? 0 : -100,
                      left: 0,
                      right: 0,
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
  String selectedWeight = '1 kg';

  final List<String> weightOptions = ['250 g', '500 g', '1 kg'];
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
    
    // This line requires the 'getItem' method to be in InstahubCartProvider
    final cartItem = cart.getItem(itemId); 

    if (cartItem != null) {
      setState(() {
        // FIX: Change cartItem.qty to cartItem.quantity
        quantity = cartItem.quantity; 
      });
    }
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.orange, size: 18),
      ),
    );
  }

  double _calculatePrice(double basePrice) {
    switch (selectedWeight) {
      case '250 g':
        return basePrice / 4;
      case '500 g':
        return basePrice / 2;
      default:
        return basePrice;
    }
  }

  void _updateCartItem({required int newQuantity}) {
    final cart = Provider.of<InstahubCartProvider>(context, listen: false);
    final item = widget.item;
    final itemId = item["id"] ?? item["name"];
    final basePrice = (item["offerPrice"] ?? item["price"] ?? 0.0).toDouble();
    final currentDisplayPrice = _calculatePrice(basePrice);

    setState(() {
      quantity = newQuantity;
    });

    if (newQuantity > 0) {
      cart.updateItem(
        id: itemId,
        name: item["name"],
        price: currentDisplayPrice,
        restaurantId: storeId,
        image: item["image"],
        // FIX: Change 'qty' to 'quantity'
        quantity: newQuantity, 
      );
    } else {
      cart.removeItem(itemId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    final basePrice =
        (item["offerPrice"] ?? item["price"] ?? 0.0).toDouble();
    final displayPrice = _calculatePrice(basePrice);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Product Image
          Expanded(
            flex: 2,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: CachedNetworkImage(
                imageUrl: item["image"] ?? "",
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported,
                    size: 40, color: Colors.grey),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Product Name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              item["name"]?.trim() ?? "Unnamed Item",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 6),

          // Weight Dropdown - FIX: Updates cart if item is present
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedWeight,
                  items: weightOptions
                      .map((w) => DropdownMenuItem(
                            value: w,
                            child: Text(w, style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setState(() => selectedWeight = val!);
                    
                    // CRUCIAL: If the item is in the cart, update its price/weight
                    if (quantity > 0) {
                      _updateCartItem(newQuantity: quantity);
                    }
                  },
                  icon: const Icon(Icons.unfold_more, size: 16),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Price
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              "₹${displayPrice.toStringAsFixed(2)}",
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Add / Quantity Controls - FIX: Uses _updateCartItem helper
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: child,
              ),
              child: quantity == 0
                  ? ElevatedButton(
                      key: const ValueKey('add'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                      ),
                      onPressed: () {
                        _updateCartItem(newQuantity: 1);
                      },
                      child: const Text("ADD",
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                    )
                  : Row(
                      key: const ValueKey('qty'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _qtyButton(Icons.remove, () {
                          if (quantity > 1) {
                            _updateCartItem(newQuantity: quantity - 1);
                          } else {
                            _updateCartItem(newQuantity: 0);
                          }
                        }),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            "$quantity",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
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
    );
  }
}