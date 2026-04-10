import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddressWidget extends StatelessWidget {
  final String userId;
  const AddressWidget({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final address = data?['address'];

        if (address == null) {
          return const Text("No address saved. Please add one.");
        }

        return Card(
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Delivery Address:",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text(address['line1']),
                if (address['line2'] != null && address['line2'].toString().isNotEmpty)
                  Text(address['line2']),
                Text("${address['city']} - ${address['pincode']}"),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    // 👉 Navigate to Address Edit Screen
                  },
                  child: const Text("Change Address"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
