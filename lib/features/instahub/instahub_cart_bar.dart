import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Providers & Screens
import 'instahub_cart_provider.dart';
import 'InstahubCartScreen.dart';

/// 🔹 Bottom Cart Bar for Instahub
class InstahubCartBar extends StatelessWidget {
  const InstahubCartBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<InstahubCartProvider>(
      builder: (context, cart, child) {
        // Hide the cart bar if empty
        if (cart.isEmpty) return const SizedBox.shrink();

        // Dynamic item count text
        final itemText = cart.totalItems == 1 ? '1 item' : '${cart.totalItems} items';
        final totalText = '₹${cart.totalAmount.toStringAsFixed(2)}';

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(14),
              color: Colors.orange,
              child: InkWell(
                onTap: () {
                  // Tap anywhere on the bar to view cart
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const InstahubCartScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      // Items and total amount
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$itemText • $totalText',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Tap to view cart',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // View Cart Button
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            foregroundColor: Colors.orange,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const InstahubCartScreen()),
                            );
                          },
                          child: const Text(
                            'View Cart',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}