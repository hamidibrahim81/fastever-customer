import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth/login_screen.dart';
import 'order_history_screen.dart';
// ✅ ADDED: Import for Morning Orders Screen
import 'package:fastevergo_v1/features/instahub/MorningOrdersListScreen.dart';

class ProfileScreen2 extends StatelessWidget {
  const ProfileScreen2({super.key});

  // Helper to open External Links (Privacy Policy / Terms / Shopping / Refund)
  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }

  // --- 🗑️ BACKGROUND DELETE LOGIC (Synced with Home Screen) ---
  Future<void> _deleteAccountBackground(String uid) async {
    try {
      // 1. Get current user reference
      User? user = FirebaseAuth.instance.currentUser;

      // 2. Delete user data from Firestore
      await FirebaseFirestore.instance.collection("users").doc(uid).delete();

      // 3. Delete user from Firebase Auth
      await user?.delete();
      
      debugPrint("Account $uid deleted successfully in background.");
    } catch (e) {
      debugPrint("Background Deletion Error: $e");
      // Note: If 'requires-recent-login' occurs, the user is already 
      // at the Login screen, which satisfies security requirements.
    }
  }

  void _showDeleteConfirmation(BuildContext context, String uid) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete Account?", 
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text(
            "This action is permanent. All your profile data and order history will be deleted forever."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              // 1. Close dialog
              Navigator.pop(dialogContext);

              // 2. INSTANT REDIRECT: Move user to Login screen immediately 
              // so they don't see "Profile not found" errors.
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );

              // 3. PROCESS DELETION: Start the background cleanup without awaiting it here
              _deleteAccountBackground(uid);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("My Profile",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // If document is missing (due to deletion), show loader while redirecting
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final String name = data['name'] ?? 'Unknown User';
          final String phone = data['phone'] ?? user.phoneNumber ?? 'No Phone';

          return SingleChildScrollView(
            child: Column(
              children: [
                // --- 👤 HEADER SECTION ---
                Container(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 35,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: (data['profilePic'] != null &&
                                data['profilePic'].toString().isNotEmpty)
                            ? NetworkImage(data['profilePic'])
                            : null,
                        child: (data['profilePic'] == null ||
                                data['profilePic'].toString().isEmpty)
                            ? const Icon(Icons.person,
                                size: 40, color: Colors.grey)
                            : null,
                      ),
                      const SizedBox(width: 15),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          Text(phone,
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey[600])),
                        ],
                      )
                    ],
                  ),
                ),
                const Divider(thickness: 1, height: 1),

                // --- ✏️ MENU OPTIONS ---
                _buildMenuTile(
                  context,
                  icon: Icons.edit_note_rounded,
                  title: "Edit Profile",
                  subtitle: "Change name and address",
                  onTap: () => _showEditProfileDialog(context, user.uid, data),
                ),

                _buildMenuTile(
                  context,
                  icon: Icons.local_shipping_outlined,
                  title: "Track Order",
                  subtitle: "See where your food is",
                  onTap: () =>
                      Navigator.pushNamed(context, 'track_order_screen'),
                ),

                _buildMenuTile(
                  context,
                  icon: Icons.history_rounded,
                  title: "Order History",
                  subtitle: "View your past orders",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            OrderHistoryScreen(userId: user.uid),
                      ),
                    );
                  },
                ),

                // ✅ NEW: Morning Orders Option
                _buildMenuTile(
                  context,
                  icon: Icons.wb_sunny_outlined,
                  title: "Morning Orders",
                  subtitle: "View morning service history",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MorningOrdersListScreen(),
                      ),
                    );
                  },
                ),

                _buildMenuTile(
                  context,
                  icon: Icons.settings_outlined,
                  title: "Settings",
                  subtitle: "App preferences",
                  onTap: () {},
                ),

                const Divider(),

                _buildMenuTile(
                  context,
                  icon: Icons.privacy_tip_outlined,
                  title: "Privacy Policy",
                  onTap: () => _launchURL(
                      "https://sites.google.com/view/fastever-privacy"),
                ),

                _buildMenuTile(
                  context,
                  icon: Icons.description_outlined,
                  title: "Terms and Conditions",
                  onTap: () => _launchURL(
                      "https://sites.google.com/view/fastever-termsconditions"),
                ),

                // ✅ NEW: Shopping Policy Link
                _buildMenuTile(
                  context,
                  icon: Icons.shopping_bag_outlined,
                  title: "Shopping Policy",
                  onTap: () => _launchURL(
                      "https://sites.google.com/view/fastever-shopping-policy"),
                ),

                // ✅ NEW: Refund & Cancellation Link
                _buildMenuTile(
                  context,
                  icon: Icons.assignment_return_outlined,
                  title: "Refund & Cancellation",
                  onTap: () => _launchURL(
                      "https://sites.google.com/view/fastever-refund-policy"),
                ),

                const Divider(),

                // --- 🗑️ DELETE ACCOUNT OPTION ---
                _buildMenuTile(
                  context,
                  icon: Icons.delete_forever_outlined,
                  title: "Delete Account",
                  isDestructive: true,
                  onTap: () => _showDeleteConfirmation(context, user.uid),
                ),

                const SizedBox(height: 20),

                // --- 🚪 LOGOUT BUTTON ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    },
                    icon: const Icon(Icons.logout, color: Colors.white),
                    label: const Text("Logout",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  // REUSABLE MENU TILE
  Widget _buildMenuTile(BuildContext context,
      {required IconData icon,
      required String title,
      String? subtitle,
      bool isDestructive = false,
      required VoidCallback onTap}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: isDestructive ? Colors.red.shade50 : Colors.grey[100],
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: isDestructive ? Colors.red : Colors.black87),
      ),
      title: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDestructive ? Colors.red : Colors.black87)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 12))
          : null,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  // --- ✏️ EDIT PROFILE DIALOG ---
  void _showEditProfileDialog(
      BuildContext context, String uid, Map<String, dynamic> currentData) {
    final nameController = TextEditingController(text: currentData['name']);
    final addressController =
        TextEditingController(text: currentData['address']);
    final locationController =
        TextEditingController(text: currentData['location']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Edit Profile",
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: "Full Name")),
              const SizedBox(height: 10),
              TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: "Address")),
              const SizedBox(height: 10),
              TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                      labelText: "Location Link (Google Maps)")),
              const SizedBox(height: 15),
              const Text("Phone number cannot be changed.",
                  style: TextStyle(fontSize: 12, color: Colors.redAccent)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection("users")
                  .doc(uid)
                  .update({
                'name': nameController.text.trim(),
                'address': addressController.text.trim(),
                'location': locationController.text.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}