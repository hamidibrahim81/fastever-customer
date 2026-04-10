import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Required for formatting the date

class OrderHistoryScreen extends StatelessWidget {
  final String userId;

  const OrderHistoryScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "My Order History",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Specifically targets: users -> {userId} -> order_history
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(userId)
            .collection("order_history")
            .orderBy('createdAt', descending: true) // Newest orders first
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    "No orders found in your history.",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final order = doc.data() as Map<String, dynamic>;
              
              // Extract data matching your Firestore fields
              final String orderId = doc.id;
              final List items = order['items'] ?? [];
              final double total = double.tryParse(order['total'].toString()) ?? 0.0;
              final String address = order['address'] ?? "N/A";
              final String createdAtStr = order['createdAt'] ?? "";
              
              // Formatting the Date for the UI
              String formattedDate = "Recent Order";
              try {
                if (createdAtStr.isNotEmpty) {
                  DateTime dt = DateTime.parse(createdAtStr);
                  formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(dt);
                }
              } catch (e) {
                formattedDate = createdAtStr;
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(
                    "Order #...${orderId.substring(orderId.length - 6).toUpperCase()}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formattedDate, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        "Total: ₹${total.toStringAsFixed(2)}",
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  children: [
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Items Ordered:", style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          // List all items in this specific order
                          ...items.map((item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("${item['name']} x${item['quantity']}"),
                                Text("₹${(double.parse(item['price'].toString()) * item['quantity']).toStringAsFixed(2)}"),
                              ],
                            ),
                          )).toList(),
                          const Divider(),
                          _buildDetailRow("Delivery Fee", "₹${order['deliveryFee'] ?? '0'}"),
                          _buildDetailRow("Discount", "₹${order['discount'] ?? '0'}"),
                          const SizedBox(height: 8),
                          const Text("Delivery Address:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(address, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ),
    );
  }
}