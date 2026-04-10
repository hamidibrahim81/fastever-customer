import 'package:flutter/material.dart';
import 'OrderPlacedScreen.dart'; // Ensure this matches your file name

// --------------------------------------------------------------------------
// CONFIRMATION DIALOG
// --------------------------------------------------------------------------
class OrderConfirmDialog extends StatelessWidget {
  final double subtotal;
  final double discount;
  final double total;
  final double deliveryFee;
  final double platformFee; // ✅ ADDED: Platform Fee
  final String address;
  final String payment;
  final bool isPlacingOrder;
  final VoidCallback onConfirm; 
  final String? instructions;

  const OrderConfirmDialog({
    super.key,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.deliveryFee,
    required this.platformFee, // ✅ Added to constructor
    required this.address,
    required this.payment,
    required this.isPlacingOrder,
    required this.onConfirm,
    this.instructions, 
  });

  Widget _buildBillRow(String label, double value,
      {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: 16,
                color: isBold ? Colors.black87 : Colors.grey[700],
              )),
          Text(
            "₹${value.abs().toStringAsFixed(2)}",
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
              color: color ?? (isBold ? Colors.black87 : Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 4),
        Text(content, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Confirm Order',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bill Summary',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
            const SizedBox(height: 8),
            _buildBillRow('Subtotal', subtotal),
            _buildBillRow('Delivery Fee', deliveryFee),
            _buildBillRow('Platform Fee', platformFee), // ✅ Separate Display
            if (discount > 0)
              _buildBillRow('Discount', discount, color: Colors.green),
            const Divider(height: 24),
            _buildBillRow('Total', total, isBold: true),
            const SizedBox(height: 16),
            _buildInfoSection("Delivery Address", address),
            if (instructions != null && instructions!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildInfoSection("Instructions", instructions!),
            ],
            const SizedBox(height: 16),
            _buildInfoSection("Payment Method", payment),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: isPlacingOrder
              ? null
              : () {
                  Navigator.of(context).pop();
                  onConfirm();
                },
          child: isPlacingOrder
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Place Order', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------
// MAIN SCREEN
// --------------------------------------------------------------------------

class OrderConfirmationScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final double subtotal;
  final double discount;
  final double total;
  final String address;
  final String payment;
  final double deliveryFee;
  final double platformFee; // ✅ ADDED: Field for platform fee
  final String? appliedCouponCode;
  final double deliveryLatitude;
  final double deliveryLongitude;
  final String? deliveryInstructions; 

  const OrderConfirmationScreen({
    super.key,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.address,
    required this.payment,
    required this.deliveryFee,
    required this.platformFee, // ✅ Added to constructor
    this.appliedCouponCode,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    this.deliveryInstructions, 
  });

  @override
  State<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen> {
  bool _isPlacingOrder = false;

  void _handlePlaceOrder() {
    setState(() => _isPlacingOrder = true);

    final orderData = {
      "items": widget.items,
      "subtotal": widget.subtotal,
      "discount": widget.discount,
      "total": widget.total,
      "address": widget.address,
      "payment": widget.payment,
      "deliveryFee": widget.deliveryFee,
      "platformFee": widget.platformFee, // ✅ Included in order data
      "appliedCouponCode": widget.appliedCouponCode,
      "deliveryInstructions": widget.deliveryInstructions ?? "", 
      "location": {
        "latitude": widget.deliveryLatitude,
        "longitude": widget.deliveryLongitude,
      },
    };

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => OrderPlacedScreen(orderData: orderData),
      ),
      (route) => route.isFirst,
    );
  }

  void _showOrderConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrderConfirmDialog(
        subtotal: widget.subtotal,
        discount: widget.discount,
        total: widget.total,
        deliveryFee: widget.deliveryFee,
        platformFee: widget.platformFee, // ✅ Pass platform fee to dialog
        address: widget.address,
        payment: widget.payment,
        isPlacingOrder: _isPlacingOrder,
        onConfirm: _handlePlaceOrder, 
        instructions: widget.deliveryInstructions, 
      ),
    );
  }

  Widget _buildBillRow(String label, double value,
      {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: 16,
                color: isBold ? Colors.black87 : Colors.grey[700],
              )),
          Text(
            "₹${value.abs().toStringAsFixed(2)}",
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
              color: color ?? (isBold ? Colors.black87 : Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 4),
        Text(content, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Confirm Order",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Order Items",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                      const Divider(height: 24),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: widget.items.length,
                        itemBuilder: (context, index) {
                          final item = widget.items[index];
                          final name = item["name"] as String? ?? 'Unnamed';
                          final price = double.tryParse(item["price"].toString()) ?? 0.0;
                          final quantity = int.tryParse(item["quantity"].toString()) ?? 0;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    "$name x$quantity",
                                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                                  ),
                                ),
                                Text(
                                  "₹${(price * quantity).toStringAsFixed(2)}",
                                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Bill Details",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                      const Divider(height: 24),
                      _buildBillRow("Subtotal", widget.subtotal),
                      _buildBillRow("Delivery Fee", widget.deliveryFee),
                      _buildBillRow("Platform Fee", widget.platformFee), // ✅ Added Row
                      if (widget.discount > 0)
                        _buildBillRow("Discount", -widget.discount, color: const Color.fromARGB(255, 43, 205, 48)),
                      const Divider(height: 24),
                      _buildBillRow("To Pay", widget.total, isBold: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoSection("Delivery Address", widget.address),
                      if (widget.deliveryInstructions != null && widget.deliveryInstructions!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildInfoSection("Delivery Instructions", widget.deliveryInstructions!),
                      ],
                      const SizedBox(height: 16),
                      _buildInfoSection("Payment Method", widget.payment),
                      if (widget.appliedCouponCode != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: _buildInfoSection(
                            "Applied Coupon",
                            widget.appliedCouponCode!,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
            onPressed: _isPlacingOrder ? null : () => _showOrderConfirmationDialog(context),
            child: _isPlacingOrder
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    "Place Order",
                    style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ),
    );
  }
}