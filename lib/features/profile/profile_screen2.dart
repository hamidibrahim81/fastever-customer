import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth/login_screen.dart';
import 'order_history_screen.dart';
import 'package:fastevergo_v1/features/instahub/MorningOrdersListScreen.dart';

class ProfileScreen2 extends StatelessWidget {
  const ProfileScreen2({super.key});

  static const Color _primaryDark = Color(0xFF111827);
  static const Color _accentOrange = Color(0xFFFF6B00);
  static const Color _bgColor = Color(0xFFF8FAFC);
  static const Color _cardBorder = Color(0xFFE2E8F0);

  // Helper to open External Links (Privacy Policy / Terms / Shopping / Refund)
  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }

  // --- 🗑️ BACKGROUND DELETE LOGIC ---
  Future<void> _deleteAccountBackground(String uid) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection("users").doc(uid).delete();
      await user?.delete();
      debugPrint("Account $uid deleted successfully in background.");
    } catch (e) {
      debugPrint("Background Deletion Error: $e");
    }
  }

  void _showDeleteConfirmation(BuildContext context, String uid) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Delete Account?", 
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: const Text(
            "This action is permanent. All your profile data and order history will be deleted forever."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
              _deleteAccountBackground(uid);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text("Delete", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
        backgroundColor: _bgColor,
        body: Center(child: CircularProgressIndicator(color: _accentOrange)),
      );
    }

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text("My Profile",
            style: TextStyle(fontWeight: FontWeight.bold, color: _primaryDark, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _primaryDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _accentOrange));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator(color: _accentOrange));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final String name = data['name'] ?? 'Unknown User';
          final String phone = data['phone'] ?? user.phoneNumber ?? 'No Phone';
          final String? profilePic = data['profilePic'];

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- 👤 MODERN HEADER CARD ---
                Container(
                  padding: const EdgeInsets.all(20),
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
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _accentOrange.withOpacity(0.3), width: 2),
                        ),
                        child: CircleAvatar(
                          radius: 35,
                          backgroundColor: Colors.grey.shade100,
                          backgroundImage: (profilePic != null && profilePic.isNotEmpty)
                              ? NetworkImage(profilePic)
                              : null,
                          child: (profilePic == null || profilePic.isEmpty)
                              ? const Icon(Icons.person_rounded, size: 40, color: _primaryDark)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 18, 
                                fontWeight: FontWeight.bold, 
                                color: _primaryDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              phone,
                              style: const TextStyle(
                                fontSize: 13, 
                                color: Color(0xFF64748B), 
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                const Text("Orders & Activity", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 0.5)),
                const SizedBox(height: 12),

                // --- 📦 ORDERS & BOOKINGS SECTION ---
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 4)),
                    ],
                    border: Border.all(color: _cardBorder.withOpacity(0.6)),
                  ),
                  child: Column(
                    children: [
                      _buildMenuTile(
                        context,
                        icon: Icons.edit_note_rounded,
                        iconBg: const Color(0xFFFEF3C7),
                        iconColor: const Color(0xFFD97706),
                        title: "Edit Profile",
                        subtitle: "Change name and address",
                        onTap: () => _showEditProfileDialog(context, user.uid, data),
                      ),
                      _buildDivider(),
                      _buildMenuTile(
                        context,
                        icon: Icons.local_shipping_outlined,
                        iconBg: const Color(0xFFE0F2FE),
                        iconColor: const Color(0xFF0284C7),
                        title: "Track Order",
                        subtitle: "See active order statuses",
                        onTap: () => Navigator.pushNamed(context, 'track_order_screen'),
                      ),
                      _buildDivider(),
                      _buildMenuTile(
                        context,
                        icon: Icons.history_rounded,
                        iconBg: const Color(0xFFDCFCE7),
                        iconColor: const Color(0xFF15803D),
                        title: "Order History",
                        subtitle: "View your past orders",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => OrderHistoryScreen(userId: user.uid),
                            ),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildMenuTile(
                        context,
                        icon: Icons.wb_sunny_rounded,
                        iconBg: const Color(0xFFFFEDD5),
                        iconColor: const Color(0xFFC2410C),
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
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                const Text("Legal & Policies", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 0.5)),
                const SizedBox(height: 12),

                // --- 📜 LEGAL & POLICIES SECTION ---
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 4)),
                    ],
                    border: Border.all(color: _cardBorder.withOpacity(0.6)),
                  ),
                  child: Column(
                    children: [
                      _buildMenuTile(
                        context,
                        icon: Icons.privacy_tip_outlined,
                        iconBg: const Color(0xFFF3E8FF),
                        iconColor: const Color(0xFF7E22CE),
                        title: "Privacy Policy",
                        onTap: () => _launchURL("https://sites.google.com/view/fastever-privacy"),
                      ),
                      _buildDivider(),
                      _buildMenuTile(
                        context,
                        icon: Icons.description_outlined,
                        iconBg: const Color(0xFFF3E8FF),
                        iconColor: const Color(0xFF7E22CE),
                        title: "Terms and Conditions",
                        onTap: () => _launchURL("https://sites.google.com/view/fastever-termsconditions"),
                      ),
                      _buildDivider(),
                      _buildMenuTile(
                        context,
                        icon: Icons.shopping_bag_outlined,
                        iconBg: const Color(0xFFF3E8FF),
                        iconColor: const Color(0xFF7E22CE),
                        title: "Shopping Policy",
                        onTap: () => _launchURL("https://sites.google.com/view/fastever-shopping-policy"),
                      ),
                      _buildDivider(),
                      _buildMenuTile(
                        context,
                        icon: Icons.assignment_return_outlined,
                        iconBg: const Color(0xFFF3E8FF),
                        iconColor: const Color(0xFF7E22CE),
                        title: "Refund & Cancellation",
                        onTap: () => _launchURL("https://sites.google.com/view/fastever-refund-policy"),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // --- 🗑️ ACCOUNT ACTIONS (Delete & Logout) ---
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 4)),
                    ],
                    border: Border.all(color: _cardBorder.withOpacity(0.6)),
                  ),
                  child: Column(
                    children: [
                      _buildMenuTile(
                        context,
                        icon: Icons.delete_forever_outlined,
                        iconBg: const Color(0xFFFEE2E2),
                        iconColor: Colors.redAccent,
                        title: "Delete Account",
                        subtitle: "Permanently delete your data",
                        isDestructive: true,
                        onTap: () => _showDeleteConfirmation(context, user.uid),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // --- 🚪 LOGOUT BUTTON ---
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    },
                    icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                    label: const Text(
                      "Logout",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryDark,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, thickness: 0.5, color: Color(0xFFF1F5F9)),
    );
  }

  // REUSABLE MENU TILE
  Widget _buildMenuTile(
    BuildContext context, {
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    String? subtitle,
    bool isDestructive = false,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: isDestructive ? Colors.redAccent : _primaryDark,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))
          : null,
      trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF94A3B8)),
      onTap: onTap,
    );
  }

  // --- ✏️ EDIT PROFILE DIALOG ---
  void _showEditProfileDialog(
      BuildContext context, String uid, Map<String, dynamic> currentData) {
    final nameController = TextEditingController(text: currentData['name']);
    final addressController = TextEditingController(text: currentData['address']);
    final locationController = TextEditingController(text: currentData['location']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Edit Profile", style: TextStyle(fontWeight: FontWeight.bold, color: _primaryDark)),
        content: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "Full Name",
                  filled: true,
                  fillColor: _bgColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: "Address",
                  filled: true,
                  fillColor: _bgColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationController,
                decoration: InputDecoration(
                  labelText: "Location Link (Google Maps)",
                  filled: true,
                  fillColor: _bgColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              const Text("Phone number cannot be changed.",
                  style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          FilledButton(
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
            style: FilledButton.styleFrom(backgroundColor: _primaryDark, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text("Save", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}