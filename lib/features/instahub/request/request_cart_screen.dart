import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ✅ Correct import path matching your directory structure
import 'package:fastevergo_v1/features/food/cart/ManageAddressScreen.dart';

class RequestCartScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;

  const RequestCartScreen({super.key, required this.items});

  @override
  State<RequestCartScreen> createState() => _RequestCartScreenState();
}

class _RequestCartScreenState extends State<RequestCartScreen> {
  Map<String, dynamic>? selectedAddress;
  bool isPlacingOrder = false;

  // ================= SELECT ADDRESS =================
  Future<void> _selectAddress() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ManageAddressScreen(),
      ),
    );

    if (result != null) {
      setState(() {
        selectedAddress = result;
      });
    }
  }

  // ================= PLACE ORDER =================
  Future<void> _placeOrder() async {
    if (selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Please select a delivery address", style: GoogleFonts.inter()),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => isPlacingOrder = true);

    try {
      await FirebaseFirestore.instance.collection("request_item_orders").add({
        "items": widget.items,
        "address": selectedAddress,
        "lat": selectedAddress!['lat'],
        "lng": selectedAddress!['lng'],
        "status": "pending",
        "createdAt": FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      // Premium Announcement Dialog instead of standard snackbar
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            elevation: 10,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 70,
                    width: 70,
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.rocket_launch_rounded, color: Colors.orange, size: 38),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Something Exciting is Cooking!",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 20, color: const Color(0xFF121212)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    "We are currently putting the finishing touches on our custom item requests to ensure you get the fastest delivery possible.\n\nWe apologize for the short wait—this feature will be live very soon! Stay tuned.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14, color: Colors.grey.shade600, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // Dismiss dialog
                        Navigator.popUntil(context, (route) => route.isFirst); // Route to Root Home Screen
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: Text("Got it, thanks!", style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      setState(() => isPlacingOrder = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to place order: $e", style: GoogleFonts.inter()),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ================= UI BUILDER =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text(
          "Request Cart",
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w800, fontSize: 18, color: const Color(0xFF121212)),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF121212),
        elevation: 0.5,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                // SECTION 1: ITEMS HEADER
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Requested Items",
                      style: GoogleFonts.montserrat(fontWeight: FontWeight.w800, fontSize: 16, color: const Color(0xFF121212)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "${widget.items.length} ${widget.items.length == 1 ? 'Item' : 'Items'}",
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ITEMS LIST LAYER
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.items.length,
                  itemBuilder: (_, i) {
                    final item = widget.items[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.shopping_bag_outlined, color: Colors.grey),
                        ),
                        title: Text(
                          item['name'] ?? 'Unknown Item',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: const Color(0xFF121212)),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            "Quantity: ${item['qty'] ?? 1}",
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 28),

                // SECTION 2: ADDRESS HEADER
                Text(
                  "Delivery Location",
                  style: GoogleFonts.montserrat(fontWeight: FontWeight.w800, fontSize: 16, color: const Color(0xFF121212)),
                ),
                const SizedBox(height: 12),

                // ADDRESS CARD
                GestureDetector(
                  onTap: _selectAddress,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selectedAddress == null ? Colors.orange.withOpacity(0.3) : Colors.transparent,
                        width: selectedAddress == null ? 1.5 : 0,
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
                      ],
                    ),
                    child: selectedAddress == null
                        ? Row(
                            children: [
                              Container(
                                height: 40,
                                width: 44,
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.location_on_rounded, color: Colors.orange, size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  "Select delivery address",
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.grey.shade700),
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 44,
                                width: 44,
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.location_on_rounded, color: Colors.orange, size: 24),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selectedAddress!['category']?.toString().toUpperCase() ?? "DELIVERY ADDRESS",
                                      style: GoogleFonts.montserrat(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.orange, letterSpacing: 0.5),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      selectedAddress!['full_display_address'] ?? "No address format configured",
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF121212), height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "CHANGE",
                                style: GoogleFonts.montserrat(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.orange),
                              )
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),

          // ================= PLACE ORDER FOOTER BAR =================
          Container(
            padding: EdgeInsets.only(
              left: 20, 
              right: 20, 
              top: 16, 
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, -4))
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: isPlacingOrder ? null : _placeOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF121212), // High-End solid aesthetic
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade400,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: isPlacingOrder
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        "Place Request Order",
                        style: GoogleFonts.montserrat(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
                      ),
              ),
            ),
          )
        ],
      ),
    );
  }
}