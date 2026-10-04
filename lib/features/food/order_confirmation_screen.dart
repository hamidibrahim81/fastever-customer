import 'package:flutter/material.dart';
import 'OrderPlacedScreen.dart';

// --------------------------------------------------------------------------
// PREMIUM COLOR PALETTE TOKENS
// --------------------------------------------------------------------------
class _AppTheme {
  static const Color primaryDark = Color(0xFF111827);
  static const Color accentOrange = Color(0xFFFF6B00);
  static const Color successGreen = Color(0xFF16A34A);
  static const Color bgColor = Color(0xFFF8FAFC);
  static const Color cardBorder = Color(0xFFE2E8F0);
  static const Color textMuted = Color(0xFF64748B);
}

// --------------------------------------------------------------------------
// CONFIRMATION DIALOG (MODERN STYLED)
// --------------------------------------------------------------------------
class OrderConfirmDialog extends StatelessWidget {
  final double subtotal;
  final double discount;
  final double total;
  final double deliveryFee;
  final double platformFee;
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
    required this.platformFee,
    required this.address,
    required this.payment,
    required this.isPlacingOrder,
    required this.onConfirm,
    this.instructions,
  });

  Widget _buildBillRow(String label, double value,
      {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: isBold ? 15 : 14,
              color: isBold ? _AppTheme.primaryDark : _AppTheme.textMuted,
            ),
          ),
          Text(
            "₹${value.abs().toStringAsFixed(2)}",
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
              fontSize: isBold ? 16 : 14,
              color: color ?? (isBold ? _AppTheme.accentOrange : _AppTheme.primaryDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(IconData icon, String title, String content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _AppTheme.accentOrange),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                content,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _AppTheme.primaryDark,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          Icon(Icons.verified_rounded, color: _AppTheme.accentOrange, size: 24),
          SizedBox(width: 10),
          Text(
            'Confirm Order',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: _AppTheme.primaryDark,
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bill Summary',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: _AppTheme.primaryDark,
              ),
            ),
            const SizedBox(height: 8),
            _buildBillRow('Subtotal', subtotal),
            _buildBillRow('Delivery Fee', deliveryFee),
            _buildBillRow('Platform Fee', platformFee),
            if (discount > 0)
              _buildBillRow('Discount', -discount, color: _AppTheme.successGreen),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Divider(height: 1, color: Color(0xFFF1F5F9)),
            ),
            _buildBillRow('Total', total, isBold: true),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 16),
            _buildInfoSection(Icons.location_on_rounded, "DELIVERY ADDRESS", address),
            if (instructions != null && instructions!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildInfoSection(Icons.note_alt_rounded, "INSTRUCTIONS", instructions!),
            ],
            const SizedBox(height: 12),
            _buildInfoSection(Icons.payments_rounded, "PAYMENT METHOD", payment),
            const SizedBox(height: 16),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.all(20),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: _AppTheme.textMuted, fontWeight: FontWeight.bold),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _AppTheme.primaryDark,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
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
              : const Text(
                  'Place Order',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------
// MAIN SCREEN: ORDER CONFIRMATION
// --------------------------------------------------------------------------

class OrderConfirmationScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final double subtotal;
  final double discount;
  final double total;
  final String address;
  final String payment;
  final double deliveryFee;
  final double platformFee;
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
    required this.platformFee,
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
      "platformFee": widget.platformFee,
      "appliedCouponCode": widget.appliedCouponCode,
      "deliveryInstructions": widget.deliveryInstructions ?? "",
      "deliveryLatitude": widget.deliveryLatitude,
      "deliveryLongitude": widget.deliveryLongitude,
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
        platformFee: widget.platformFee,
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
    String valueText = '₹${value.abs().toStringAsFixed(2)}';
    if (value < 0) {
      valueText = '- $valueText';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: isBold ? 16 : 14,
              color: isBold ? _AppTheme.primaryDark : _AppTheme.textMuted,
            ),
          ),
          Text(
            valueText,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
              fontSize: isBold ? 18 : 14,
              color: color ?? (isBold ? _AppTheme.accentOrange : _AppTheme.primaryDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
        border: Border.all(color: _AppTheme.cardBorder.withOpacity(0.6)),
      ),
      child: child,
    );
  }

  Widget _buildInfoSection(IconData icon, String title, String content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _AppTheme.primaryDark.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _AppTheme.primaryDark, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content.isNotEmpty ? content : 'N/A',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _AppTheme.primaryDark,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppTheme.bgColor,
      appBar: AppBar(
        title: const Text(
          "Confirm Order",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _AppTheme.primaryDark),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _AppTheme.primaryDark, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ORDER ITEMS CARD
            _buildCardContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.restaurant_menu_rounded, color: _AppTheme.accentOrange, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Order Items",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _AppTheme.primaryDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const ScrollPhysics(),
                    itemCount: widget.items.length,
                    separatorBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                    ),
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      final name = item["name"] as String? ?? 'Unnamed';
                      final price = double.tryParse(item["price"].toString()) ?? 0.0;
                      final quantity = int.tryParse(item["quantity"].toString()) ?? 0;

                      return Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _AppTheme.primaryDark.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "${quantity}x",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _AppTheme.primaryDark),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _AppTheme.primaryDark),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            "₹${(price * quantity).toStringAsFixed(2)}",
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _AppTheme.primaryDark),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            // BILL DETAILS CARD
            _buildCardContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.receipt_long_rounded, color: _AppTheme.accentOrange, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Bill Details",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _AppTheme.primaryDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildBillRow("Subtotal", widget.subtotal),
                  _buildBillRow("Delivery Fee", widget.deliveryFee),
                  _buildBillRow("Platform Fee", widget.platformFee),
                  if (widget.discount > 0)
                    _buildBillRow("Discount", -widget.discount, color: _AppTheme.successGreen),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                  ),
                  _buildBillRow("To Pay", widget.total, isBold: true),
                ],
              ),
            ),

            // FULFILLMENT & PAYMENT DETAILS CARD
            _buildCardContainer(
              child: Column(
                children: [
                  _buildInfoSection(Icons.location_on_rounded, "DELIVERY ADDRESS", widget.address),
                  if (widget.deliveryInstructions != null && widget.deliveryInstructions!.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14.0),
                      child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                    ),
                    _buildInfoSection(Icons.note_alt_rounded, "DELIVERY INSTRUCTIONS", widget.deliveryInstructions!),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14.0),
                    child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                  ),
                  _buildInfoSection(Icons.payments_rounded, "PAYMENT METHOD", widget.payment),
                  if (widget.appliedCouponCode != null) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14.0),
                      child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                    ),
                    _buildInfoSection(Icons.local_offer_rounded, "APPLIED COUPON", widget.appliedCouponCode!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _AppTheme.primaryDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
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
                      style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}