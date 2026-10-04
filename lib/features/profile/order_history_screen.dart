import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class OrderHistoryScreen extends StatelessWidget {
  final String userId;

  const OrderHistoryScreen({super.key, required this.userId});

  static const Color _primaryDark = Color(0xFF111827);
  static const Color _accentOrange = Color(0xFFFF6B00);
  static const Color _successGreen = Color(0xFF16A34A);
  static const Color _bgColor = Color(0xFFF8FAFC);
  static const Color _cardBorder = Color(0xFFE2E8F0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: Text(
          "Order History",
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: _primaryDark,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _primaryDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Targets: users -> {userId} -> order_history
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(userId)
            .collection("order_history")
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _accentOrange));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _accentOrange.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.receipt_long_rounded, size: 50, color: _accentOrange),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No orders found in your history",
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _primaryDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Your completed orders will appear here.",
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
            );
          }

          final orders = snapshot.data!.docs;

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final order = doc.data() as Map<String, dynamic>;
              
              final String orderId = doc.id;
              final List items = order['items'] ?? [];
              final double total = double.tryParse(order['total'].toString()) ?? 0.0;
              final double deliveryFee = double.tryParse(order['deliveryFee']?.toString() ?? '0') ?? 0.0;
              final double discount = double.tryParse(order['discount']?.toString() ?? '0') ?? 0.0;
              final String address = order['address'] ?? "N/A";
              final String createdAtStr = order['createdAt'] ?? "";
              final String status = order['status']?.toString().toUpperCase() ?? 'PENDING';

              // Format Date
              String formattedDate = "Recent Order";
              try {
                if (createdAtStr.isNotEmpty) {
                  DateTime dt = DateTime.parse(createdAtStr);
                  formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(dt);
                }
              } catch (_) {
                formattedDate = createdAtStr;
              }

              // Status Styling Colors
              Color statusColor = Colors.orange;
              if (status == 'DELIVERED' || status == 'COMPLETED') {
                statusColor = _successGreen;
              } else if (status == 'CANCELLED') {
                statusColor = Colors.redAccent;
              }

              final int subIndex = math.min(6, orderId.length).toInt();

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: _cardBorder.withOpacity(0.6)),
                ),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Order #...${orderId.substring(orderId.length - subIndex).toUpperCase()}",
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: _primaryDark,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status,
                          style: GoogleFonts.montserrat(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formattedDate, 
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Total: ₹${total.toStringAsFixed(2)}",
                          style: GoogleFonts.montserrat(
                            color: _accentOrange, 
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  children: [
                    const Divider(height: 1, thickness: 0.5, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 14),
                    
                    // Items Section Title
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Items Ordered",
                        style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 13, color: _primaryDark),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // List Items
                    ...items.map((item) {
                      final itemMap = item as Map<String, dynamic>;
                      final name = itemMap['name'] ?? 'Item';
                      final qty = itemMap['quantity'] ?? 1;
                      final price = double.tryParse(itemMap['price'].toString()) ?? 0.0;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                "$qty x $name",
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF334155)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              "₹${(price * qty).toStringAsFixed(2)}",
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _primaryDark),
                            ),
                          ],
                        ),
                      );
                    }).toList(),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, thickness: 0.5, color: Color(0xFFF1F5F9)),
                    ),

                    // Fee Breakdowns
                    _buildDetailRow("Delivery Fee", "₹${deliveryFee.toStringAsFixed(2)}"),
                    const SizedBox(height: 4),
                    _buildDetailRow("Discount", "-₹${discount.toStringAsFixed(2)}", isGreen: discount > 0),
                    
                    const SizedBox(height: 12),
                    
                    // Delivery Address Block
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _bgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _cardBorder.withOpacity(0.6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, size: 14, color: _accentOrange),
                              const SizedBox(width: 6),
                              Text(
                                "Delivery Address",
                                style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 12, color: _primaryDark),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            address,
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), height: 1.3),
                          ),
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

  Widget _buildDetailRow(String label, String value, {bool isGreen = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
        Text(
          value, 
          style: GoogleFonts.inter(
            fontSize: 13, 
            fontWeight: FontWeight.w600, 
            color: isGreen ? _successGreen : const Color(0xFF334155),
          ),
        ),
      ],
    );
  }
}