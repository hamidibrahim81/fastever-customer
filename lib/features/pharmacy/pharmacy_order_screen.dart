import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

// Address selector import matching your project structure
import '../food/cart/ManageAddressScreen.dart';

// ✅ IMPORT NOTIFICATION SCREEN FOR NAVIGATION
import 'package:fastevergo_v1/features/notification/NotificationScreen.dart';

class PharmacyOrderScreen extends StatefulWidget {
  const PharmacyOrderScreen({super.key});

  @override
  State<PharmacyOrderScreen> createState() => _PharmacyOrderScreenState();
}

class _PharmacyOrderScreenState extends State<PharmacyOrderScreen> {
  final _formKey = GlobalKey<FormState>();

  // Input Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
  final TextEditingController _commentsController = TextEditingController();

  // Address Selection States
  String? _selectedAddress;
  double? _latitude;
  double? _longitude;
  bool _addressTouchedAndEmpty = false;

  // 💰 Pricing & Distance States
  double _calculatedDistance = 0.0;
  double _deliveryFee = 0.0;
  double _platformFee = 0.0;

  // ⚙️ Remote Config variables (Loaded dynamically from Firestore with absolute fallbacks)
  double _officeLat = 9.226888;
  double _officeLng = 76.849616;
  double _baseDeliveryFee = 20.0;
  double _perKmCharge = 10.0;

  // Image Upload States
  File? _selectedPrescriptionImage;
  final ImagePicker _picker = ImagePicker();

  bool _isSubmitting = false;

  // Colors
  static const Color primaryColor = Color(0xFF111827);
  static const Color accentColor = Color(0xFFFF4D6D);
  static const Color tealColor = Color(0xFF0D9488);
  static const Color backgroundColor = Color(0xFFF6F6F9);

  @override
  void initState() {
    super.initState();
    _prefillUserData();
    _fetchDeliveryFeeConfigurations();
  }

  // 📡 Fetch standard pharmacy location and pricing configurations from Firestore safely
  Future<void> _fetchDeliveryFeeConfigurations() async {
    try {
      DocumentSnapshot snapshot = await FirebaseFirestore.instance
          .collection('pharmacy_deliveryfee')
          .doc('config')
          .get();

      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data() as Map<String, dynamic>;
        setState(() {
          _officeLat = double.tryParse(data['office_latitude']?.toString() ?? '') ?? 9.226888;
          _officeLng = double.tryParse(data['office_longitude']?.toString() ?? '') ?? 76.849616;

          _baseDeliveryFee = (data['base_delivery_fee'] as num?)?.toDouble() ?? 20.0;
          _perKmCharge = (data['per_km_charge'] as num?)?.toDouble() ?? 10.0;
          _platformFee = (data['platform_fee'] as num?)?.toDouble() ?? 5.0;
        });
      }
    } catch (e) {
      debugPrint("Error loading pharmacy delivery configuration settings: $e");
    }
  }

  // 📐 Haversine Formula: Calculates absolute distance in Kilometers
  double _calculateDistanceInKm(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusKm = 6371.0;

    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);

    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  // 🧮 Orchestrates mathematical fee adjustments post address selection
  void _updatePricingMetrics(double targetLat, double targetLng) {
    if (targetLat == 0.0 && targetLng == 0.0) {
      setState(() {
        _calculatedDistance = 0.0;
        _deliveryFee = _baseDeliveryFee;
      });
      return;
    }

    double distance = _calculateDistanceInKm(_officeLat, _officeLng, targetLat, targetLng);
    double calculatedFee = _baseDeliveryFee;

    if (distance > 2.0) {
      double extraDistance = distance - 2.0;
      calculatedFee += (extraDistance.ceil() * _perKmCharge);
    }

    setState(() {
      _calculatedDistance = distance;
      _deliveryFee = double.parse(calculatedFee.toStringAsFixed(2));
    });
  }

  Future<void> _prefillUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        _nameController.text = user.displayName!;
      }
      if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
        _contactController.text = user.phoneNumber!;
      }

      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data();
          if (data != null) {
            if (_nameController.text.isEmpty && data['name'] != null) {
              _nameController.text = data['name'];
            }
            if (_contactController.text.isEmpty && data['phone'] != null) {
              _contactController.text = data['phone'];
            }
          }
        }
      } catch (e) {
        debugPrint("Error prefilling profile: $e");
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _landmarkController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  // Pick Address from ManageAddressScreen
  Future<void> _pickAddress() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ManageAddressScreen()),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _selectedAddress = result['full_display_address'] as String?;
        _latitude = result['lat'] as double?;
        _longitude = result['lng'] as double?;
        _addressTouchedAndEmpty = false;
      });
      _updatePricingMetrics(_latitude ?? 0.0, _longitude ?? 0.0);
    } else if (result != null && result is String) {
      setState(() {
        _selectedAddress = result;
        _latitude = 0.0;
        _longitude = 0.0;
        _addressTouchedAndEmpty = false;
      });
      _updatePricingMetrics(0.0, 0.0);
    }
  }

  // Image Picker Logic (Camera or Gallery)
  Future<void> _pickPrescription(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (pickedFile != null) {
        setState(() {
          _selectedPrescriptionImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error picking image: $e")),
      );
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: tealColor),
              title: const Text('Take Photo with Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPrescription(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: tealColor),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPrescription(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ⚖️ Privacy Policy & Legal Information Dialog Popup
  void _showPrivacyPolicyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tealColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.privacy_tip_rounded, color: tealColor, size: 24),
            ),
            const SizedBox(width: 12),
            const Text(
              "Privacy & Legal Policy",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  "1. Prescription Regulations",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryColor),
                ),
                SizedBox(height: 4),
                Text(
                  "While general wellness products and OTC medicines do not require a prescription, Schedule H and X prescription medications legally mandate a valid doctor's prescription before dispensation.",
                  style: TextStyle(fontSize: 12, color: Color(0xFF4B5563), height: 1.4),
                ),
                SizedBox(height: 14),
                Text(
                  "2. Data Privacy & Health Records",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryColor),
                ),
                SizedBox(height: 4),
                Text(
                  "Your medical data, prescription uploads, and personal details are encrypted and handled with the highest level of confidentiality. We share prescription data solely with licensed partner pharmacies for order verification and fulfillment.",
                  style: TextStyle(fontSize: 12, color: Color(0xFF4B5563), height: 1.4),
                ),
                SizedBox(height: 14),
                Text(
                  "3. Limitation of Liability",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryColor),
                ),
                SizedBox(height: 4),
                Text(
                  "FASTever acts as a technology facilitator connecting users with licensed retail pharmacies. Dispensation, verification, and sale of medicines are executed exclusively by licensed pharmacist partners.",
                  style: TextStyle(fontSize: 12, color: Color(0xFF4B5563), height: 1.4),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Got It", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Submit Order Process
  Future<void> _submitPharmacyOrder() async {
    final bool formValid = _formKey.currentState!.validate();

    if (_selectedAddress == null || _selectedAddress!.isEmpty) {
      setState(() => _addressTouchedAndEmpty = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select your delivery address.")),
      );
      return;
    }

    if (!formValid) return;

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'guest';
      final firestore = FirebaseFirestore.instance;

      final DocumentReference globalRef = firestore.collection('pharmacy_orders').doc();
      final String orderId = globalRef.id;

      // Conditional Image Upload: only upload if the user picked a prescription
      String? prescriptionUrl;
      if (_selectedPrescriptionImage != null) {
        final Reference storageRef = FirebaseStorage.instance
            .ref()
            .child('medicine_images')
            .child('$orderId.jpg');

        final UploadTask uploadTask = storageRef.putFile(_selectedPrescriptionImage!);
        final TaskSnapshot snapshot = await uploadTask;
        prescriptionUrl = await snapshot.ref.getDownloadURL();
      }

      final Map<String, dynamic> orderPayload = {
        'order_id': orderId,
        'user_id': uid,
        'customer_name': _nameController.text.trim(),
        'contact_number': _contactController.text.trim(),
        'delivery_address': _selectedAddress,
        'latitude': _latitude ?? 0.0,
        'longitude': _longitude ?? 0.0,
        'landmark': _landmarkController.text.trim(),
        'prescription_url': prescriptionUrl,
        'comments': _commentsController.text.trim(),
        'status': 'Pending Approval',
        'payment_status': 'Pending Verification',
        'delivery_fee': _deliveryFee,
        'platform_fee': _platformFee,
        'distance_km': double.parse(_calculatedDistance.toStringAsFixed(2)),
        'created_at': FieldValue.serverTimestamp(),
      };

      final DocumentReference userSubcollectionRef = firestore
          .collection('users')
          .doc(uid)
          .collection('pharmacy_orders')
          .doc(orderId);

      WriteBatch batch = firestore.batch();
      batch.set(globalRef, orderPayload);
      batch.set(userSubcollectionRef, orderPayload);
      await batch.commit();

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFCCFBF1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: tealColor, size: 55),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Order Placed!",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: primaryColor),
                ),
                const SizedBox(height: 12),
                Text(
                  "Our licensed partner pharmacist will review your order details and contact you within 1 hour with the medicine availability and billing invoice.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade800, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                    },
                    child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error submitting order: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Pharmacy & Medicines 💊",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_rounded, color: Colors.white, size: 24),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🩺 Professional Pharmacist Advisory Banner with Privacy Policy Link
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF2563EB),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.medical_information_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Important Health Notice 🩺",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF1E40AF),
                                ),
                              ),
                              InkWell(
                                onTap: _showPrivacyPolicyDialog,
                                child: const Text(
                                  "Privacy Policy",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2563EB),
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Medicines should strictly be taken under medical supervision. Uploading a doctor's prescription helps pharmacists verify dosages and dispatch restricted drugs.",
                            style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A), height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // 📸 Prescription Upload Container (Optional)
              _buildSectionHeader("Upload Doctor's Prescription (Optional)"),

              // 💡 Explanatory note tag
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Some medications (Schedule H & X) legally require a valid doctor's prescription. If your requested medicines require one, our partner pharmacist will request a prescription copy before dispensing.",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              _buildSectionContainer(
                child: Column(
                  children: [
                    InkWell(
                      onTap: _showImageSourceActionSheet,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _selectedPrescriptionImage != null
                                ? tealColor
                                : Colors.grey.shade300,
                            width: 1.5,
                          ),
                        ),
                        child: _selectedPrescriptionImage != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: Image.file(_selectedPrescriptionImage!, fit: BoxFit.cover),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFCCFBF1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.add_a_photo_rounded, color: tealColor, size: 28),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    "Tap to take photo or select prescription",
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryColor),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    "PNG, JPG, or JPEG formats supported",
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    if (_selectedPrescriptionImage != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: _showImageSourceActionSheet,
                            icon: const Icon(Icons.refresh_rounded, color: tealColor, size: 18),
                            label: const Text(
                              "Change Photo",
                              style: TextStyle(color: tealColor, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedPrescriptionImage = null;
                              });
                            },
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                            label: const Text(
                              "Remove",
                              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // 👤 Patient / Customer Details
              _buildSectionHeader("Patient Details"),
              _buildSectionContainer(
                child: Column(
                  children: [
                    _buildField(_nameController, "Patient / Customer Name *", Icons.person_outline_rounded),
                    const SizedBox(height: 6),
                    _buildField(_contactController, "Contact Number *", Icons.phone_android_rounded, keyboardType: TextInputType.phone),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // 📍 Delivery Address Section
              _buildSectionHeader("Delivery Location"),
              _buildSectionContainer(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: _pickAddress,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: _addressTouchedAndEmpty
                                    ? Colors.red.withOpacity(0.1)
                                    : tealColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Icon(
                                Icons.location_on_rounded,
                                color: _addressTouchedAndEmpty ? Colors.red.shade700 : tealColor,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedAddress != null ? "Selected Delivery Address" : "Select saved address *",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _addressTouchedAndEmpty
                                          ? Colors.red.shade700
                                          : (_selectedAddress != null ? tealColor : Colors.grey.shade800),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedAddress ?? "Tap to import address details",
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _selectedAddress != null ? Colors.black87 : Colors.grey.shade500,
                                      height: 1.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    if (_addressTouchedAndEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(left: 16, bottom: 14),
                        child: Text(
                          "Delivery address is mandatory *",
                          style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 14),

              _buildSectionContainer(
                child: _buildField(_landmarkController, "Landmark / Flat / Building (Optional)", Icons.domain_rounded),
              ),

              const SizedBox(height: 22),

              // 📝 Notes / Comments Section
              _buildSectionHeader("Instructions for Pharmacist"),
              _buildSectionContainer(
                child: _buildField(
                  _commentsController,
                  "Specify medicine names, dosages, or quantities here",
                  Icons.chat_bubble_outline_rounded,
                  maxLines: 3,
                ),
              ),

              const SizedBox(height: 22),

              // 💳 CARD SECTION: BILL SUMMARY (Appears once address is picked)
              if (_selectedAddress != null) ...[
                _buildSectionHeader("Bill Summary"),
                _buildSectionContainer(
                  child: Column(
                    children: [
                      _buildPriceRow("Distance", "${_calculatedDistance.toStringAsFixed(2)} km", isMuted: true),
                      const Divider(height: 20, thickness: 0.5),
                      _buildPriceRow("Delivery Fee", "₹${_deliveryFee.toStringAsFixed(2)}"),
                      const SizedBox(height: 8),
                      _buildPriceRow("Platform Fee", "₹${_platformFee.toStringAsFixed(2)}"),
                      const Divider(height: 20, thickness: 1, color: Colors.black12),
                      _buildPriceRow(
                        "Total Service Charge",
                        "₹${(_deliveryFee + _platformFee).toStringAsFixed(2)}",
                        isTotal: true,
                        color: tealColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 35),
              ] else ...[
                const SizedBox(height: 15),
              ],

              // Confirm Order Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isSubmitting ? null : _submitPharmacyOrder,
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "CONFIRM & PLACE ORDER ➔",
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceRow(String label, String value, {bool isTotal = false, bool isMuted = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.bold : (isMuted ? FontWeight.normal : FontWeight.w500),
            color: isMuted ? Colors.grey : primaryColor,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 17 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
            color: color ?? primaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: primaryColor, letterSpacing: 0.3),
      ),
    );
  }

  Widget _buildSectionContainer({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 15, color: primaryColor),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
          prefixIcon: Icon(icon, size: 22, color: Colors.grey.shade500),
          filled: true,
          fillColor: const Color(0xFFFAFAFC),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: tealColor, width: 1.8)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200, width: 1)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade400, width: 1)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red, width: 1.8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        validator: (val) {
          if (label.contains("Optional") || label.contains("Specify medicine")) return null;
          return (val == null || val.trim().isEmpty) ? "Field cannot be empty" : null;
        },
      ),
    );
  }
}