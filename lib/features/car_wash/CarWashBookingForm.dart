import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Ensure this path matches your project structure for address retrieval
import '../food/cart/ManageAddressScreen.dart';

class CarWashBookingForm extends StatefulWidget {
  final String centreId;
  final String centreName;
  final List<String> availableServices;

  const CarWashBookingForm({
    required this.centreId,
    required this.centreName,
    required this.availableServices,
    super.key,
  });

  @override
  State<CarWashBookingForm> createState() => _CarWashBookingFormState();
}

class _CarWashBookingFormState extends State<CarWashBookingForm> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _vehicleNumberController = TextEditingController();
  final TextEditingController _customBrandController = TextEditingController();
  final TextEditingController _customModelController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  // Location configuration states
  String? _selectedAddress;
  double? _latitude;
  double? _longitude;
  bool _isSubmitting = false;
  bool _addressTouchedAndEmpty = false;

  // Pricing & Distance States
  double _calculatedDistance = 0.0;
  double _deliveryFee = 0.0;
  double _platformFee = 10.0;

  // Remote Config variables fetched from Firestore (deliveryfee/carwash_deliveryfee)
  double _officeLat = 9.226888;
  double _officeLng = 76.849616;
  double _baseFee = 30.0;
  double _baseKm = 2.0;
  double _perKmFee = 10.0;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  // Vehicle Brand & Model Selection State
  String? _selectedBrand;
  String? _selectedModel;

  // Kerala Popular Car Brands & Models Dataset Map
  final Map<String, List<String>> _keralaCarDataset = {
    'Maruti Suzuki': ['Swift', 'Baleno', 'Brezza', 'Dzire', 'Ertiga', 'Alto 800', 'WagonR', 'Fronx', 'Grand Vitara', 'Jimny', 'S-Presso', 'Ciaz', 'Ignis', 'XL6'],
    'Hyundai': ['Creta', 'i20', 'Venue', 'Verna', 'Grand i10 Nios', 'Exter', 'Aura', 'Alcazar', 'Tucson', 'Santro'],
    'Tata': ['Nexon', 'Punch', 'Harrier', 'Tiago', 'Safari', 'Altroz', 'Tigor', 'Curvv', 'Nexon EV', 'Tiago EV'],
    'Mahindra': ['Thar', 'Scorpio-N', 'XUV700', 'XUV300', 'Bolero', 'XUV400', 'Scorpio Classic', 'Marazzo', 'Thar Roxx'],
    'Toyota': ['Innova Crysta', 'Innova Hycross', 'Fortuner', 'Urban Cruiser Taisor', 'Urban Cruiser Hyryder', 'Glanza', 'Hilux', 'Camry'],
    'Kia': ['Seltos', 'Sonet', 'Carens', 'Carnival', 'EV6'],
    'Honda': ['City', 'Amaze', 'Elevate', 'WR-V', 'Jazz', 'Civic'],
    'Volkswagen': ['Virtus', 'Taigun', 'Polo', 'Vento', 'Tiguan'],
    'Skoda': ['Slavia', 'Kushaq', 'Kodiaq', 'Rapid', 'Octavia'],
    'MG': ['Hector', 'Astor', 'Comet EV', 'ZS EV', 'Gloster'],
    'Nissan': ['Magnite', 'Kicks'],
    'Renault': ['Kwid', 'Triber', 'Kiger', 'Duster'],
    'Other / Unlisted': ['Other Model'],
  };

  final Map<String, bool> _servicesSelectionMap = {};

  @override
  void initState() {
    super.initState();
    _fetchCarWashDeliveryConfigurations();
    for (var service in widget.availableServices) {
      _servicesSelectionMap[service] = false;
    }
  }

  Future<void> _fetchCarWashDeliveryConfigurations() async {
    try {
      DocumentSnapshot snapshot = await FirebaseFirestore.instance
          .collection('deliveryfee')
          .doc('carwash_deliveryfee')
          .get();

      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data() as Map<String, dynamic>;
        setState(() {
          _officeLat = double.tryParse(data['office_latitude']?.toString() ?? '') ?? 9.226888;
          _officeLng = double.tryParse(data['office_longitude']?.toString() ?? '') ?? 76.849616;

          _baseFee = (data['baseFee'] as num?)?.toDouble() ?? 30.0;
          _baseKm = (data['baseKm'] as num?)?.toDouble() ?? 2.0;
          _perKmFee = (data['perKmFee'] as num?)?.toDouble() ?? 10.0;
          _platformFee = (data['platformFee'] as num?)?.toDouble() ?? 10.0;
          _deliveryFee = _baseFee;
        });
      }
    } catch (e) {
      debugPrint("Error loading carwash delivery configuration: $e");
    }
  }

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

  void _updatePricingMetrics(double targetLat, double targetLng) {
    if (targetLat == 0.0 && targetLng == 0.0) {
      setState(() {
        _calculatedDistance = 0.0;
        _deliveryFee = _baseFee;
      });
      return;
    }

    double distance = _calculateDistanceInKm(_officeLat, _officeLng, targetLat, targetLng);
    double calculatedFee = _baseFee;

    if (distance > _baseKm) {
      double extraDistance = distance - _baseKm;
      calculatedFee += (extraDistance.ceil() * _perKmFee);
    }

    setState(() {
      _calculatedDistance = distance;
      _deliveryFee = double.parse(calculatedFee.toStringAsFixed(2));
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _vehicleNumberController.dispose();
    _customBrandController.dispose();
    _customModelController.dispose();
    _landmarkController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Color _getThemeColor() {
    return const Color(0xFFFF2A55);
  }

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

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 14)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _getThemeColor(),
              onPrimary: Colors.white,
              onSurface: const Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _getThemeColor(),
              onPrimary: Colors.white,
              onSurface: const Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final int pickedMinutes = picked.hour * 60 + picked.minute;
      const int startMinutes = 9 * 60;
      const int endMinutes = 17 * 60;

      if (pickedMinutes < startMinutes || pickedMinutes > endMinutes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Row(
              children: [
                Icon(Icons.access_time_filled_rounded, color: Colors.white),
                SizedBox(width: 10),
                Expanded(child: Text("Please select a pickup time between 9:00 AM and 5:00 PM.")),
              ],
            ),
            backgroundColor: const Color(0xFFE11D48),
          ),
        );
        return;
      }

      if (picked != _selectedTime) {
        setState(() {
          _selectedTime = picked;
          if (!mounted) return;
          _timeController.text = picked.format(context);
        });
      }
    }
  }

  Future<void> _submitBooking() async {
    List<String> chosenServices = [];
    _servicesSelectionMap.forEach((service, isSelected) {
      if (isSelected) chosenServices.add(service);
    });

    if (chosenServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Text("Please select at least one car wash service."),
          backgroundColor: const Color(0xFFE11D48),
        ),
      );
      return;
    }

    final bool formValid = _formKey.currentState!.validate();

    if (_selectedAddress == null || _selectedAddress!.isEmpty) {
      setState(() => _addressTouchedAndEmpty = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Text("Please select your pickup address location."),
          backgroundColor: const Color(0xFFE11D48),
        ),
      );
      return;
    }

    if (!formValid) return;

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final FirebaseFirestore firestore = FirebaseFirestore.instance;

      final DocumentReference globalBookingRef = firestore.collection('booking_washing_service').doc();
      final String orderId = globalBookingRef.id;

      final DocumentReference centreSubcollectionRef = firestore
          .collection('washing_centre')
          .doc(widget.centreId)
          .collection('centre_orders')
          .doc(orderId);

      final String finalBrand = _selectedBrand == 'Other / Unlisted'
          ? _customBrandController.text.trim()
          : (_selectedBrand ?? 'Unknown');

      final String finalModel = _selectedBrand == 'Other / Unlisted'
          ? _customModelController.text.trim()
          : (_selectedModel ?? 'Unknown');

      final Map<String, dynamic> bookingPayload = {
        'order_id': orderId,
        'washing_centre_id': widget.centreId,
        'washing_centre_name': widget.centreName,
        'name': _nameController.text.trim(),
        'contact': _contactController.text.trim(),
        'vehicle_number': _vehicleNumberController.text.trim().toUpperCase(),
        'vehicle_brand': finalBrand,
        'vehicle_model': finalModel,
        'address': _selectedAddress,
        'latitude': _latitude ?? 0.0,
        'longitude': _longitude ?? 0.0,
        'landmark': _landmarkController.text.trim(),
        'pickup_date': _dateController.text,
        'pickup_time': _timeController.text,
        'selected_services': chosenServices,
        'delivery_fee': _deliveryFee,
        'platform_fee': _platformFee,
        'distance_km': double.parse(_calculatedDistance.toStringAsFixed(2)),
        'comments': _commentController.text.trim(),
        'userId': user?.uid ?? 'anonymous',
        'status': 'Pending',
        'payment_of_centre': 'pending',
        'payment_of_customer': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      };

      WriteBatch batch = firestore.batch();
      batch.set(globalBookingRef, bookingPayload);
      batch.set(centreSubcollectionRef, bookingPayload);
      await batch.commit();

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          contentPadding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 80,
                width: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_getThemeColor().withOpacity(0.15), _getThemeColor().withOpacity(0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getThemeColor(),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _getThemeColor().withOpacity(0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        )
                      ],
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 32),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Booking Confirmed!",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Color(0xFF0F172A), letterSpacing: -0.3),
              ),
              const SizedBox(height: 12),
              Text(
                "Our pickup partner will call you shortly and arrive at your scheduled time for a smooth pickup experience.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  "സൗകര്യപ്രദമായ പിക്കപ്പിനായി ഞങ്ങളുടെ പങ്കാളി ഉടൻ നിങ്ങളെ ബന്ധപ്പെടുന്നതാണ്.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12, height: 1.4, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  child: const Text("Done", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Booking failed: $e")));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _getThemeColor();
    final totalAmount = _deliveryFee + _platformFee;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              widget.centreName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.2),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                const Text(
                  "Doorstep Pickup & Wash",
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            )
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(18, 12, 18, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, -6),
            )
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Row(
          children: [
            if (_selectedAddress != null) ...[
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Estimated Total", style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                  Text(
                    "₹${totalAmount.toStringAsFixed(2)}",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: themeColor),
                  ),
                ],
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    elevation: 4,
                    shadowColor: themeColor.withOpacity(0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isSubmitting ? null : _submitBooking,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Confirm Appointment",
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // CARD SECTION 1: SELECT SERVICES
              _buildSectionHeader("Selected Packages", Icons.auto_awesome_rounded),
              _buildSectionContainer(
                child: Column(
                  children: widget.availableServices.map<Widget>((service) {
                    bool isChecked = _servicesSelectionMap[service] ?? false;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isChecked ? themeColor.withOpacity(0.04) : const Color(0xFFFAFAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isChecked ? themeColor.withOpacity(0.4) : const Color(0xFFE2E8F0),
                          width: isChecked ? 1.5 : 1,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          setState(() => _servicesSelectionMap[service] = !isChecked);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: isChecked ? themeColor : Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isChecked ? themeColor : const Color(0xFFCBD5E1),
                                    width: 1.5,
                                  ),
                                ),
                                child: isChecked
                                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                                    : null,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  service,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isChecked ? FontWeight.w700 : FontWeight.w500,
                                    color: isChecked ? const Color(0xFF0F172A) : const Color(0xFF334155),
                                  ),
                                ),
                              ),
                              Icon(Icons.local_car_wash_rounded, size: 18, color: isChecked ? themeColor : const Color(0xFF94A3B8)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // CARD SECTION 2: VEHICLE DETAILS
              _buildSectionHeader("Vehicle Information", Icons.directions_car_filled_rounded),
              _buildSectionContainer(
                child: Column(
                  children: [
                    _buildField(
                      _vehicleNumberController,
                      "License Plate Number *",
                      Icons.pin_outlined,
                      themeColor,
                      hintText: "e.g. KL 03 AA 0000",
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedBrand,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                      dropdownColor: Colors.white,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
                      decoration: _inputDecoration("Car Brand *", Icons.car_repair_rounded, themeColor),
                      items: _keralaCarDataset.keys.map((String brand) {
                        return DropdownMenuItem<String>(
                          value: brand,
                          child: Text(brand),
                        );
                      }).toList(),
                      onChanged: (String? newBrand) {
                        setState(() {
                          _selectedBrand = newBrand;
                          _selectedModel = null;
                        });
                      },
                      validator: (val) => val == null ? "Please select vehicle brand" : null,
                    ),
                    const SizedBox(height: 12),
                    if (_selectedBrand != null && _selectedBrand != 'Other / Unlisted') ...[
                      DropdownButtonFormField<String>(
                        value: _selectedModel,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                        dropdownColor: Colors.white,
                        style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
                        decoration: _inputDecoration("Car Model *", Icons.commute_rounded, themeColor),
                        items: (_keralaCarDataset[_selectedBrand] ?? []).map((String model) {
                          return DropdownMenuItem<String>(
                            value: model,
                            child: Text(model),
                          );
                        }).toList(),
                        onChanged: (String? newModel) {
                          setState(() => _selectedModel = newModel);
                        },
                        validator: (val) => val == null ? "Please select vehicle model" : null,
                      ),
                    ] else if (_selectedBrand == 'Other / Unlisted') ...[
                      _buildField(_customBrandController, "Brand Name *", Icons.branding_watermark_rounded, themeColor, hintText: "E.g. Isuzu, MG"),
                      const SizedBox(height: 8),
                      _buildField(_customModelController, "Model Name *", Icons.model_training_rounded, themeColor, hintText: "E.g. D-Max"),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // CARD SECTION 3: CUSTOMER CONTACT
              _buildSectionHeader("Contact Info", Icons.badge_outlined),
              _buildSectionContainer(
                child: Column(
                  children: [
                    _buildField(_nameController, "Customer Full Name *", Icons.person_outline_rounded, themeColor),
                    const SizedBox(height: 12),
                    _buildField(_contactController, "Phone Number *", Icons.phone_android_rounded, themeColor, keyboardType: TextInputType.phone),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // CARD SECTION 4: PICKUP SCHEDULE
              _buildSectionHeader("Preferred Slot", Icons.calendar_today_rounded),
              _buildSectionContainer(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _selectDate,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.calendar_month_rounded, size: 16, color: themeColor),
                                  const SizedBox(width: 6),
                                  const Text("Date *", style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _dateController.text.isNotEmpty ? _dateController.text : "Select date",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _dateController.text.isNotEmpty ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: _selectTime,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.access_time_rounded, size: 16, color: themeColor),
                                  const SizedBox(width: 6),
                                  const Text("Time *", style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _timeController.text.isNotEmpty ? _timeController.text : "Select time",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _timeController.text.isNotEmpty ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // CARD SECTION 5: PICKUP LOCATION
              _buildSectionHeader("Pickup Address", Icons.near_me_rounded),
              _buildSectionContainer(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    InkWell(
                      onTap: _pickAddress,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              height: 48,
                              width: 48,
                              decoration: BoxDecoration(
                                color: _addressTouchedAndEmpty ? Colors.red.shade50 : themeColor.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.location_on_rounded,
                                color: _addressTouchedAndEmpty ? Colors.red : themeColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedAddress != null ? "Selected Address" : "Choose address from profile *",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _addressTouchedAndEmpty ? Colors.red : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedAddress ?? "Tap to choose pickup location from saved places",
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: _selectedAddress != null ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                                      height: 1.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                          ],
                        ),
                      ),
                    ),
                    if (_addressTouchedAndEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(left: 16, bottom: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text("Pickup address is required *", style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _buildField(_landmarkController, "Building / Landmark / Notes (Optional)", Icons.apartment_rounded, themeColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // CARD SECTION 6: BILL SUMMARY
              if (_selectedAddress != null) ...[
                _buildSectionHeader("Fare Breakdown", Icons.receipt_long_rounded),
                _buildSectionContainer(
                  child: Column(
                    children: [
                      _buildPriceRow("Calculated Distance", "${_calculatedDistance.toStringAsFixed(2)} km", isMuted: true),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(color: Color(0xFFF1F5F9), thickness: 1),
                      ),
                      _buildPriceRow("Pickup & Delivery Fee", "₹${_deliveryFee.toStringAsFixed(2)}"),
                      const SizedBox(height: 8),
                      _buildPriceRow("Platform Fee", "₹${_platformFee.toStringAsFixed(2)}"),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(color: Color(0xFFE2E8F0), thickness: 1),
                      ),
                      _buildPriceRow(
                        "Total Service Charge",
                        "₹${totalAmount.toStringAsFixed(2)}",
                        isTotal: true,
                        color: themeColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // CARD SECTION 7: NOTES
              _buildSectionHeader("Instructions", Icons.sticky_note_2_outlined),
              _buildSectionContainer(
                child: _buildField(
                  _commentController,
                  "Special Instructions or Notes (Optional)",
                  Icons.edit_note_rounded,
                  themeColor,
                  maxLines: 3,
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, Color focusColor, {String? hintText}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13.5, fontWeight: FontWeight.w500),
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF64748B)),
      filled: true,
      fillColor: const Color(0xFFFAFAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: focusColor, width: 1.6),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFF43F5E), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFF43F5E), width: 1.6),
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
            fontSize: isTotal ? 15 : 13.5,
            fontWeight: isTotal ? FontWeight.w800 : (isMuted ? FontWeight.w500 : FontWeight.w600),
            color: isMuted ? const Color(0xFF94A3B8) : const Color(0xFF334155),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 17 : 14,
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.w700,
            color: color ?? const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _getThemeColor()),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF334155), letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionContainer({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: child,
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon,
    Color focusColor, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? hintText,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
      decoration: _inputDecoration(label, icon, focusColor, hintText: hintText),
      validator: (val) {
        if (label.contains("Optional")) return null;
        if (val == null || val.isEmpty) return "Required";

        if (label.contains("Time") && _selectedTime != null) {
          final int totalMins = _selectedTime!.hour * 60 + _selectedTime!.minute;
          if (totalMins < (9 * 60) || totalMins > (17 * 60)) {
            return "Between 9:00 AM and 5:00 PM";
          }
        }
        return null;
      },
    );
  }
}