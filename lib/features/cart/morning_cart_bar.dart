import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'morning_cart_provider.dart';
import 'morning_cart_screen.dart';

class MorningCartBar extends StatelessWidget {
  const MorningCartBar({super.key});

  // ✅ 100% READY: Accurate Total Quantity Calculation
  int _getTotalQuantity(Map<String, Map<String, dynamic>> items) {
    int total = 0;
    items.values.forEach((item) {
      // Safely accessing quantity from the map
      total += (item['quantity'] as num? ?? 0).toInt();
    });
    return total;
  }

  @override
  Widget build(BuildContext context) {
    // Listen to changes in the cart state
    final cart = Provider.of<MorningCartProvider>(context);

    // Hide bar if the items map is empty
    if (cart.items.isEmpty) return const SizedBox.shrink();

    // ✅ Total item count (Sum of all quantities)
    final int totalItems = _getTotalQuantity(cart.items);
    
    // Total Amount formatted
    final String totalAmount = cart.totalAmount.toStringAsFixed(0);

    // ✅ FIXED: Using SafeArea instead of Positioned for universal compatibility
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), // Floating effect
        child: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MorningCartScreen()),
            );
          },
          child: Container(
            height: 58, 
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.deepOrange.shade700, 
              // ✅ Professional design with slightly sharper corners
              borderRadius: BorderRadius.circular(8), 
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 1. Item Count Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "$totalItems item${totalItems > 1 ? 's' : ''}",
                    style: TextStyle(
                      color: Colors.deepOrange.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                
                // 2. Price and View Cart CTA
                Row(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "₹$totalAmount",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const Text(
                          "plus taxes",
                          style: TextStyle(color: Colors.white70, fontSize: 9),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Container(
                      height: 24,
                      width: 1,
                      color: Colors.white24,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "VIEW CART",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 18),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}