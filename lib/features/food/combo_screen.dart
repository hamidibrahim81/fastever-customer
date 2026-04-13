// combo_screen.dart (FINAL FIXED CODE)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import '../food/cart/cart_provider.dart';
import '../food/cart/cart_bar.dart';
import 'active_order_bottom_bar.dart';

class ComboScreen extends StatelessWidget {
  const ComboScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Get userId directly from Firebase Auth
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text("Please sign in to view combo deals")),
      );
    }

    // ⭐ ADJUSTED PADDING FOR CART BAR VISIBILITY ⭐
    const double cartBarHeightPadding = 110.0; 

    return Scaffold(
      appBar: AppBar(
        title: const Text("Combo Deals"),
        backgroundColor: const Color.fromARGB(255, 67, 160, 71),
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      bottomNavigationBar: const ActiveOrderBottomBar(),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('combodeals')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return ListView.builder(
                  padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: cartBarHeightPadding),
                  itemCount: 6,
                  itemBuilder: (context, index) => const ComboShimmerCard(),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.local_offer_outlined, size: 72, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          "No Combo Deals Yet!",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "We’re working on new combo offers. Please check back soon!",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final comboDeals = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: cartBarHeightPadding),
                itemCount: comboDeals.length,
                itemBuilder: (context, index) {
                  final data = comboDeals[index].data() as Map<String, dynamic>;
                  final id = comboDeals[index].id;

                  final String imageUrl = data['image'] ?? '';
                  final String comboName = data['name'] ?? 'Combo Deal';
                  final String restaurantName =
                      data['restaurant'] ?? data['restaurantName'] ?? 'Unknown Restaurant';
                  
                  // Safe double parsing
                  final double price = (data['price'] ?? 0).toDouble();
                  final double offerPrice = (data['offerPrice'] ?? price).toDouble();
                  
                  final String restaurantId =
                      data['restaurantId'] ?? 'ASygXN0cjM3IlxayGZ1C'; 

                  return ComboCard(
                    id: id,
                    imageUrl: imageUrl,
                    comboName: comboName,
                    restaurantName: restaurantName,
                    price: price,
                    offerPrice: offerPrice,
                    restaurantId: restaurantId,
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
  final double offerPrice;

  const ComboCard({
    super.key,
    required this.id,
    required this.imageUrl,
    required this.comboName,
    required this.restaurantName,
    required this.price,
    required this.offerPrice,
    required this.restaurantId,
  });

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final quantity = cart.getQuantity(id);
    final bool hasDiscount = offerPrice < price;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: 110,
              height: 110,
              fit: BoxFit.cover,
              placeholder: (context, url) => Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Container(width: 110, height: 110, color: Colors.white),
              ),
              errorWidget: (context, url, error) => Container(
                width: 110,
                height: 110,
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comboName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    restaurantName,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        "₹${offerPrice.toStringAsFixed(0)}",
                        style: const TextStyle(
                          color: Color.fromARGB(255, 67, 160, 71),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (hasDiscount) ...[
                        const SizedBox(width: 6),
                        Text(
                          "₹${price.toStringAsFixed(0)}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: quantity > 0
                        ? Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 18),
                                  onPressed: () {
                                    cart.reduceQuantity(id);
                                  },
                                ),
                                Text(
                                  '$quantity',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 18),
                                  onPressed: () {
                                    cart.addItem(
                                      id: id,
                                      name: comboName,
                                      price: offerPrice,
                                      restaurantId: restaurantId,
                                      image: imageUrl,
                                    );
                                  },
                                ),
                              ],
                            ),
                          )
                        : OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.orange),
                              foregroundColor: Colors.orange,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                            ),
                            onPressed: () {
                              cart.addItem(
                                id: id,
                                name: comboName,
                                price: offerPrice,
                                restaurantId: restaurantId,
                                image: imageUrl,
                              );
                            },
                            child: const Text("Add"),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Container(width: 110, height: 110, color: Colors.white),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 14, width: 120, color: Colors.white),
                    const SizedBox(height: 6),
                    Container(height: 12, width: 80, color: Colors.white),
                    const SizedBox(height: 10),
                    Container(height: 14, width: 60, color: Colors.white),
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