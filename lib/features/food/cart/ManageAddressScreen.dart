import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Ensure this path matches your project structure
import 'AddressFlow.dart';

class ManageAddressScreen extends StatefulWidget {
  const ManageAddressScreen({super.key});

  @override
  State<ManageAddressScreen> createState() => _ManageAddressScreenState();
}

class _ManageAddressScreenState extends State<ManageAddressScreen> {
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  List<DocumentSnapshot> _addresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAddresses();
  }

  // ================= FETCH ADDRESSES FROM FIRESTORE =================
  Future<void> _fetchAddresses() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      var snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('addresses')
          .orderBy('updatedAt', descending: true)
          .limit(3) // FASTO Limit
          .get();

      if (!mounted) return;

      setState(() {
        _addresses = snapshot.docs;
        _loading = false;
      });
    } catch (e) {
      debugPrint("Error fetching addresses: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  // ================= DELETE ADDRESS LOGIC =================
  Future<void> _deleteAddress(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('addresses')
          .doc(docId)
          .delete();
      
      _fetchAddresses(); // Refresh list
    } catch (e) {
      debugPrint("Delete failed: $e");
    }
  }

  // ================= NAVIGATION: ADD NEW =================
  Future<void> _addNewAddress() async {
    if (_addresses.length >= 3) {
      _showLimitDialog();
      return;
    }

    // Opens your Map Screen
    final result = await Navigator.push(
      context,
      // FIXED: Removed 'const' to prevent compile error
      MaterialPageRoute(builder: (_) => AddressScreen()),
    );

    if (!mounted) return;

    if (result != null) {
      // If user finished the Map -> Details flow, result contains the new address.
      // We return this data directly to the Cart/Checkout.
      Navigator.pop(context, result);
    } else {
      // Refresh list if they came back without selecting/saving
      _fetchAddresses();
    }
  }

  // ================= DIALOGS =================
  void _showLimitDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Address Limit Reached", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("FASTO allows up to 3 saved addresses. Please delete one to add a new location."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(color: Colors.orange)),
          )
        ],
      ),
    );
  }

  void _confirmDelete(String docId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Address"),
        content: const Text("Are you sure you want to remove this address?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAddress(docId);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ================= SELECTION LOGIC =================
  void _selectAddress(Map<String, dynamic> data, String docId) {
    // Return the selected address map to the previous screen (Cart)
    Navigator.pop(context, {
      'addressId': docId,
      ...data, // Spreads all fields like house_no, lat, lng, etc.
    });
  }

  // ================= UI BUILDER =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("My Addresses", style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0.5,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.orange))
                : _addresses.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        itemCount: _addresses.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          var doc = _addresses[index];
                          var data = doc.data() as Map<String, dynamic>;
                          
                          IconData icon = Icons.location_on;
                          if (data['category'] == "Home") icon = Icons.home;
                          if (data['category'] == "Office") icon = Icons.work;

                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor: Colors.orange.withOpacity(0.1),
                                child: Icon(icon, color: Colors.orange, size: 22),
                              ),
                              title: Text(
                                data['category'] ?? "Saved Address",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  data['full_display_address'] ?? "No address details",
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4),
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                                onPressed: () => _confirmDelete(doc.id),
                              ),
                              onTap: () => _selectAddress(data, doc.id),
                            ),
                          );
                        },
                      ),
          ),
          
          // BOTTOM BUTTON
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
            ),
            child: SafeArea(
              child: ElevatedButton(
                onPressed: _addNewAddress,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 54),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("ADD NEW ADDRESS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 70, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text("No saved addresses", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 8),
          Text("Add your home or office address for\nfaster checkout experience.", 
               textAlign: TextAlign.center, 
               style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }
}