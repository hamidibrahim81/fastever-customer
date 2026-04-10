// offer_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import 'cart/cart_provider.dart';
import 'RestaurantMenuScreen.dart';
import 'cart/cart_bar.dart'; // <-- ADDED: Import CartBar

// Helper functions for safe parsing of Firestore data
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

class OfferScreen extends StatefulWidget {
  final String title;
  final String offerTag;

  const OfferScreen({
    super.key,
    required this.title,
    required this.offerTag,
  });

  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color.fromARGB(255, 67, 160, 71),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collectionGroup('menu')
            .where('tags', arrayContains: widget.offerTag)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint("🔥 Firestore Offer Items Error: ${snapshot.error}");
            return const Center(child: Text('Error loading offers.'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No offers found.'));
          }

          final offerItems = snapshot.data!.docs;
          
          return Stack( // <-- MODIFIED: Wrap content in Stack
            children: [
              // List of Offer Items
              ListView.builder(
                itemCount: offerItems.length,
                // MODIFIED: Add extra padding at the bottom to prevent CartBar from obscuring the last item
                padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 100.0), 
                itemBuilder: (context, index) {
                  final itemDoc = offerItems[index];
                  return _OfferItemCard(itemDoc: itemDoc);
                },
              ),
              
              // CartBar Positioned at the bottom
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: CartBar(), // <-- ADDED: The CartBar widget
              ),
            ],
          ); // <-- END: Stack
        },
      ),
    );
  }
}

class _OfferItemCard extends StatefulWidget {
  final DocumentSnapshot itemDoc;
  
  const _OfferItemCard({
    required this.itemDoc,
    Key? key,
  }) : super(key: key);

  @override
  State<_OfferItemCard> createState() => _OfferItemCardState();
}

class _OfferItemCardState extends State<_OfferItemCard> {
  late Map<String, dynamic> itemData;
  late String imageUrl;
  int quantity = 0;
  String? restaurantName;
  double? restaurantRating;
  late bool isAvailable;
  String status = 'open'; // ✅ String status variable

  @override
  void initState() {
    super.initState();
    itemData = widget.itemDoc.data() as Map<String, dynamic>;
    imageUrl = itemData['imageUrl'] ?? 'https://via.placeholder.com/150';
    isAvailable = parseInt(itemData['stock']) > 0;
    
    _fetchRestaurantInfo();
    
    final cart = Provider.of<CartProvider>(context, listen: false);
    cart.addListener(_updateQuantityFromCart);
    quantity = cart.getQuantity(widget.itemDoc.id);
  }

  @override
  void dispose() {
    Provider.of<CartProvider>(context, listen: false)
        .removeListener(_updateQuantityFromCart);
    super.dispose();
  }

  Future<void> _fetchRestaurantInfo() async {
    try {
      final restaurantDocRef = widget.itemDoc.reference.parent.parent;
      if (restaurantDocRef != null) {
        final restaurantSnapshot = await restaurantDocRef.get();
        final restaurantData = restaurantSnapshot.data() as Map<String, dynamic>?;
        if (mounted && restaurantData != null) {
          setState(() {
            restaurantName = restaurantData['name']?.toString() ?? 'Unknown Restaurant';
            restaurantRating = parseDouble(restaurantData['rating'], defaultValue: 0.0);
            status = restaurantData['status'] ?? 'open'; // ✅ Read string status
          });
        }
      }
    } catch (e) {
      debugPrint("🔥 Error fetching restaurant info: $e");
    }
  }
  
  void _updateQuantityFromCart() {
    final cart = Provider.of<CartProvider>(context, listen: false);
    final newQuantity = cart.getQuantity(widget.itemDoc.id);
    if (newQuantity != quantity) {
      setState(() {
        quantity = newQuantity;
      });
    }
  }

  void _changeQuantity(int newQuantity) {
    if (newQuantity < 0) return;

    // ✅ ADDED: CLIENT-SIDE STOCK LIMIT VALIDATION
    final int stockAvailable = parseInt(itemData['stock'], defaultValue: 0);
    if (newQuantity > stockAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Only $stockAvailable left in stock!"),
          duration: const Duration(seconds: 2),
        ),
      );
      return; // Exit without updating quantity
    }

    final cart = Provider.of<CartProvider>(context, listen: false);
    final itemId = widget.itemDoc.id;
    final restaurantId = widget.itemDoc.reference.parent.parent?.id ?? '';
    final price = parseDouble(itemData['price'], defaultValue: 0.0);

    if (newQuantity == 0) {
      cart.removeItem(itemId);
    } else {
      cart.updateItem(
        id: itemId,
        name: itemData['name'] ?? 'Unknown',
        price: price,
        restaurantId: restaurantId,
        image: imageUrl,
        qty: newQuantity,
        isInstaHub: itemData['isInstaHub'] ?? false,
      );
    }
  }

  Widget _buildQuantitySelector() {
    if (!isAvailable) {
      return Container();
    }
    
    return quantity > 0
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // ✅ INCREASED PADDING
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 21, 101, 192),
              borderRadius: BorderRadius.circular(10), // ✅ SLIGHTLY MORE ROUNDED
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _changeQuantity(quantity - 1),
                  child: const Icon(Icons.remove, size: 22, color: Colors.white), // ✅ INCREASED SIZE
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12), // ✅ INCREASED SPACING
                  child: Text('$quantity',
                      style: const TextStyle(
                          fontSize: 16, // ✅ INCREASED FONT
                          fontWeight: FontWeight.bold, 
                          color: Colors.white)),
                ),
                InkWell(
                  onTap: () => _changeQuantity(quantity + 1),
                  child: const Icon(Icons.add, size: 22, color: Colors.white), // ✅ INCREASED SIZE
                ),
              ],
            ),
          )
        : ElevatedButton(
            onPressed: () => _changeQuantity(1),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 82, 11, 225),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8), // ✅ ADDED VERTICAL PADDING
              minimumSize: const Size(120, 44), // ✅ INCREASED MINIMUM SIZE
            ),
            child: const Text('ADD', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), // ✅ IMPROVED TEXT
          );
  }
  
  @override
  Widget build(BuildContext context) {
    // ✅ HIDE COMPLETELY IF CLOSED
    if (status == 'closed') {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onTap: () {
          final restaurantId = widget.itemDoc.reference.parent.parent?.id;
          if (restaurantId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RestaurantMenuScreen(restaurantId: restaurantId),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      imageUrl,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.fastfood, size: 80, color: Colors.grey),
                    ),
                  ),
                  if (!isAvailable)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text(
                            "Sold Out",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemData['name']?.toString() ?? 'N/A',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      restaurantName ?? 'Loading...',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (itemData['isVeg'] == true) ? "Veg" : "Non-Veg",
                      style: TextStyle(
                        fontSize: 12,
                        color: (itemData['isVeg'] == true)
                            ? Colors.green[800]
                            : Colors.red[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "₹${parseDouble(itemData['price']).toStringAsFixed(0)}",
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                    ),
                    const SizedBox(height: 12), // ✅ ADDED EXTRA SPACING
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 130, // ✅ INCREASED WIDTH TO ACCOMMODATE LARGER BUTTON
                        child: _buildQuantitySelector(),
                      ),
                    ),
                  ],
                ),
              ),
              if (restaurantRating != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, color: Colors.orange, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        restaurantRating!.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}