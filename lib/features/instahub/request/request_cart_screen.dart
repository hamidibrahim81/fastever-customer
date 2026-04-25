import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ✅ Correct import (update path if needed)
import 'package:fastevergo_v1/features/food/cart/ManageAddressScreen.dart';

class RequestCartScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;

  const RequestCartScreen({super.key, required this.items});

  @override
  State<RequestCartScreen> createState() => _RequestCartScreenState();
}

class _RequestCartScreenState extends State<RequestCartScreen> {
  Map<String, dynamic>? selectedAddress;

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
        const SnackBar(content: Text("Please select address")),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection("request_item_orders").add({
        "items": widget.items,

        // ✅ FULL ADDRESS OBJECT
        "address": selectedAddress,

        // ✅ LAT LNG FOR DELIVERY TRACKING
        "lat": selectedAddress!['lat'],
        "lng": selectedAddress!['lng'],

        "status": "pending",
        "createdAt": FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Your order is placed. Our delivery support team will contact you shortly.",
          ),
        ),
      );

      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to place order: $e")),
      );
    }
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Request Cart"),
      ),
      body: Column(
        children: [
          // ================= ITEMS =================
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ITEMS LIST
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.items.length,
                  itemBuilder: (_, i) {
                    final item = widget.items[i];
                    return Card(
                      child: ListTile(
                        title: Text(item['name']),
                        subtitle: Text("Qty: ${item['qty']}"),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),

                // ================= ADDRESS SECTION =================
                const Text(
                  "Delivery Address",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),

                const SizedBox(height: 10),

                GestureDetector(
                  onTap: _selectAddress,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: selectedAddress == null
                        ? Row(
                            children: const [
                              Icon(Icons.location_on, color: Colors.orange),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text("Select delivery address"),
                              ),
                              Icon(Icons.arrow_forward_ios, size: 14),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.location_on,
                                  color: Colors.orange),

                              const SizedBox(width: 10),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selectedAddress!['category'] ?? "Address",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      selectedAddress![
                                              'full_display_address'] ??
                                          "",
                                      style: TextStyle(
                                          color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),

                              const Text(
                                "CHANGE",
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 100),
              ],
            ),
          ),

          // ================= PLACE ORDER BUTTON =================
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _placeOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text("Place Order"),
              ),
            ),
          )
        ],
      ),
    );
  }
}