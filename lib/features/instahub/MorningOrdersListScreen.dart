import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class MorningOrdersListScreen extends StatelessWidget {
  const MorningOrdersListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text("My Morning Orders", 
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: user == null
          ? const Center(child: Text("Please sign in to view orders"))
          : StreamBuilder<QuerySnapshot>(
              // ✅ Correct Query based on your screenshot fields
              stream: FirebaseFirestore.instance
                  .collection('morningbooking')
                  .where('userId', isEqualTo: user.uid)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.deepOrange));
                }

                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text("No morning orders yet", 
                          style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey)),
                      ],
                    ),
                  );
                }

                final orders = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index].data() as Map<String, dynamic>;
                    return _buildOrderCard(order, orders[index].id);
                  },
                );
              },
            ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order, String docId) {
    // Mapping data from your Firestore Screenshot
    final String deliveryTime = order['deliveryTime'] ?? 'Slot not set'; 
    final double totalAmount = (order['total'] ?? 0).toDouble();
    final List items = order['items'] as List? ?? [];
    final String address = order['address'] ?? 'No address found';
    final String status = order['status'] ?? 'booked';
    
    // Formatting Timestamp
    String dateStr = "Recently";
    if (order['timestamp'] != null) {
      DateTime dt = (order['timestamp'] as Timestamp).toDate();
      dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Order ID & Status Badge
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Order #${docId.substring(0, 8).toUpperCase()}", 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(dateStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                _buildStatusChip(status),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Items List with Base64 Image support
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i] as Map<String, dynamic>;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                leading: _buildItemImage(item['image']), // Base64 decode logic
                title: Text(item['name'] ?? 'Item', 
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text("Qty: ${item['quantity']} | Price: ₹${item['price']}"),
              );
            },
          ),
          
          const Divider(height: 1),
          
          // Delivery Details
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.alarm, size: 16, color: Colors.deepOrange),
                    const SizedBox(width: 8),
                    Text("Slot: $deliveryTime", style: const TextStyle(fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(child: Text(address, 
                      style: const TextStyle(fontSize: 12, color: Colors.grey), 
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Total Summary
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total Paid", style: TextStyle(fontWeight: FontWeight.w500)),
                Text("₹${totalAmount.toStringAsFixed(2)}", 
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ 100% READY: Helper to handle Base64 Image from screenshot
  Widget _buildItemImage(String? imageStr) {
    if (imageStr == null || imageStr.isEmpty) return const Icon(Icons.image, size: 40);
    
    try {
      if (imageStr.startsWith('data:image')) {
        final base64Str = imageStr.split(',')[1];
        return Container(
          width: 45, height: 45,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.zero, // Sharp square
          ),
          child: Image.memory(base64Decode(base64Str), fit: BoxFit.cover),
        );
      }
      return Image.network(imageStr, width: 45, height: 45, fit: BoxFit.cover);
    } catch (e) {
      return const Icon(Icons.broken_image, size: 40);
    }
  }

  Widget _buildStatusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
      child: Text(status.toUpperCase(), 
        style: TextStyle(color: Colors.green.shade700, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}