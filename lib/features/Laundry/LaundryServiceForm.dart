import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; 

// Ensure this path matches your project structure
import '../food/cart/ManageAddressScreen.dart'; 

class LaundryServiceForm extends StatefulWidget {
  const LaundryServiceForm({super.key});

  @override
  State<LaundryServiceForm> createState() => _LaundryServiceFormState();
}

class _LaundryServiceFormState extends State<LaundryServiceForm> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();

  // Dynamic Garment Configuration State
  final List<TextEditingController> _garmentNameControllers = [];
  final List<int> _garmentQuantities = [];

  // Location & Meta data states
  String? _selectedAddress; 
  double? _latitude;
  double? _longitude;
  bool _isSubmitting = false;
  bool _addressTouchedAndEmpty = false;

  // Pricing & Distance States
  double _calculatedDistance = 0.0;
  double _deliveryFee = 0.0;
  double _platformFee = 0.0;

  // Remote Config variables (Loaded dynamically from Firestore with absolute fallbacks)
  double _officeLat = 9.226888; 
  double _officeLng = 76.849616;
  double _baseDeliveryFee = 20.0;
  double _perKmCharge = 10.0;

  // Stored DateTime values for database submission
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  // Multi-Select Options State Map
  final Map<String, bool> _selectedServices = {
    "Wash & Iron": false,
    "Iron Only": false,
    "Dry Cleaning": false,
  };

  @override
  void initState() {
    super.initState();
    _fetchDeliveryFeeConfigurations();
    for (int i = 0; i < 3; i++) {
      _addGarmentRow();
    }
  }

  // Fetch standard office location and pricing configurations from Firestore safely
  Future<void> _fetchDeliveryFeeConfigurations() async {
    try {
      DocumentSnapshot snapshot = await FirebaseFirestore.instance
          .collection('laundry_deliveryfee')
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
      debugPrint("Error loading delivery configuration settings: $e");
    }
  }

  // Haversine Formula: Calculates absolute distance in Kilometers
  double _calculateDistanceInKm(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusKm = 6371.0;
    
    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);
    
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
               math.cos(_degreesToRadians(lat1)) * math.cos(_degreesToRadians(lat2)) * 
               math.sin(dLon / 2) * math.sin(dLon / 2);
               
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  // Orchestrates mathematical fee adjustments post address selection
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

    // Custom Threshold Logic: 
    // Anything within 2 km is covered under the base delivery fee.
    // Anything over 2 km applies the per-km charge for each extra kilometer (rounded up using ceil).
    if (distance > 2.0) {
      double extraDistance = distance - 2.0;
      calculatedFee += (extraDistance.ceil() * _perKmCharge);
    }

    setState(() {
      _calculatedDistance = distance;
      _deliveryFee = double.parse(calculatedFee.toStringAsFixed(2));
    });
  }

  void _addGarmentRow() {
    setState(() {
      _garmentNameControllers.add(TextEditingController());
      _garmentQuantities.add(1);
    });
  }

  void _removeGarmentRow(int index) {
    setState(() {
      _garmentNameControllers[index].dispose();
      _garmentNameControllers.removeAt(index);
      _garmentQuantities.removeAt(index);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _landmarkController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    for (var controller in _garmentNameControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Color _getThemeColor() {
    return const Color(0xFF0072FF); 
  }

  Future<void> _pickAddress() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ManageAddressScreen(), 
      ),
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
              onSurface: const Color(0xFF222222),
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
              onSurface: const Color(0xFF222222),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
        if (!mounted) return;
        _timeController.text = picked.format(context);
      });
    }
  }

  Future<void> _submitForm() async {
    List<String> activeServiceSelections = [];
    _selectedServices.forEach((serviceName, isChecked) {
      if (isChecked) activeServiceSelections.add(serviceName);
    });

    if (activeServiceSelections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one laundry service option.")),
      );
      return;
    }

    final bool isFormValid = _formKey.currentState!.validate();
    
    if (_selectedAddress == null || _selectedAddress!.isEmpty) {
      setState(() {
        _addressTouchedAndEmpty = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select your pickup address.")),
      );
      return;
    }

    List<Map<String, dynamic>> structuredGarmentsList = [];
    for (int i = 0; i < _garmentNameControllers.length; i++) {
      String itemName = _garmentNameControllers[i].text.trim();
      if (itemName.isNotEmpty) {
        structuredGarmentsList.add({
          'item_name': itemName,
          'quantity': _garmentQuantities[i],
        });
      }
    }

    if (structuredGarmentsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please add at least one garment name item.")),
      );
      return;
    }

    if (!isFormValid) return;

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      
      String combinedDateTimeString = "";
      if (_selectedDate != null && _selectedTime != null) {
        final combinedDateTime = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute,
        );
        combinedDateTimeString = combinedDateTime.toIso8601String();
      }

      await FirebaseFirestore.instance.collection('laundry').add({
        'service_categories': activeServiceSelections, 
        'name': _nameController.text.trim(),
        'contact': _contactController.text.trim(),
        'address': _selectedAddress,
        'latitude': _latitude ?? 0.0,
        'longitude': _longitude ?? 0.0,
        'garments_list': structuredGarmentsList, 
        'landmark': _landmarkController.text.trim(), 
        'userId': user?.uid ?? 'anonymous',
        'status': 'Pending',
        'pickup_date': _dateController.text, 
        'pickup_time': _timeController.text, 
        'scheduled_timestamp': combinedDateTimeString, 
        'delivery_fee': _deliveryFee,         
        'platform_fee': _platformFee,         
        'distance_km': double.parse(_calculatedDistance.toStringAsFixed(2)),
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.local_laundry_service_rounded, color: _getThemeColor(), size: 55),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Booking Confirmed!", 
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Color(0xFF222222)),
                ),
                const SizedBox(height: 14),
                Text(
                  "Our pickup partner will call you shortly and arrive at your preferred time for a smooth and hassle-free pickup.", 
                  textAlign: TextAlign.center, 
                  style: TextStyle(color: Colors.grey.shade800, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF222222),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context); 
                      Navigator.pop(context); 
                    },
                    child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Booking failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _getThemeColor();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF222222),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Laundry", 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // CARD SECTION: SERVICE SELECTION
              _buildSectionHeader("Select Services Needed"),
              _buildSectionContainer(
                child: Column(
                  children: _selectedServices.keys.map<Widget>((String serviceName) { 
                    bool isChecked = _selectedServices[serviceName]!;
                    return CheckboxListTile(
                      title: Text(
                        serviceName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isChecked ? FontWeight.bold : FontWeight.w500,
                          color: isChecked ? themeColor : const Color(0xFF222222),
                        ),
                      ),
                      value: isChecked,
                      activeColor: themeColor,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading, 
                      onChanged: (bool? value) {
                        setState(() {
                          _selectedServices[serviceName] = value ?? false;
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 22),

              // CARD SECTION 1: CUSTOMER INFO
              _buildSectionHeader("Customer Details"),
              _buildSectionContainer(
                child: Column(
                  children: [
                    _buildField(_nameController, "Your Name *", Icons.person_outline_rounded, themeColor),
                    const SizedBox(height: 4),
                    _buildField(_contactController, "Contact Number *", Icons.phone_android_rounded, themeColor, keyboardType: TextInputType.phone),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // CARD SECTION 2: PICKUP DATE & TIME SETUP
              _buildSectionHeader("Select Pickup Schedule"),
              _buildSectionContainer(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _selectDate,
                        child: IgnorePointer(
                          child: _buildField(_dateController, "Pickup Date *", Icons.calendar_month_rounded, themeColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: _selectTime,
                        child: IgnorePointer(
                          child: _buildField(_timeController, "Pickup Time *", Icons.access_time_rounded, themeColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // CARD SECTION 3: LOCATION DETAILS
              _buildSectionHeader("Pickup Location"),
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
                                color: _addressTouchedAndEmpty ? Colors.red.withOpacity(0.1) : themeColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(12), 
                              child: Icon(
                                Icons.location_on_rounded, 
                                color: _addressTouchedAndEmpty ? Colors.red.shade700 : themeColor, 
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedAddress != null ? "Selected Pickup Address" : "Select saved address *",
                                    style: TextStyle(
                                      fontSize: 14, 
                                      fontWeight: FontWeight.bold,
                                      color: _addressTouchedAndEmpty ? Colors.red.shade700 : (_selectedAddress != null ? themeColor : Colors.grey.shade800),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedAddress ?? "Tap to import your address details",
                                    style: TextStyle(fontSize: 13, color: _selectedAddress != null ? Colors.black87 : Colors.grey.shade500, height: 1.3),
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
                        child: Text("Pickup address is mandatory *", style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSectionContainer(
                child: _buildField(_landmarkController, "Landmark / Flat / Building Floor (Optional)", Icons.domain_rounded, themeColor),
              ),
              const SizedBox(height: 22),

              // CARD SECTION 4: GARMENT CONFIGURATIONS
              _buildSectionHeader("Garment Configurations"),
              _buildSectionContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _garmentNameControllers.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _garmentNameControllers[index],
                                style: const TextStyle(fontSize: 14, color: Color(0xFF222222)),
                                decoration: InputDecoration(
                                  labelText: "Item Name",
                                  labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                                  filled: true,
                                  fillColor: const Color(0xFFFAFAFC),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: themeColor, width: 1.5)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            InkWell(
                              onTap: () {
                                if (_garmentQuantities[index] > 1) {
                                  setState(() => _garmentQuantities[index]--);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                                child: const Icon(Icons.remove, size: 18),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text("${_garmentQuantities[index]}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                            InkWell(
                              onTap: () => setState(() => _garmentQuantities[index]++),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                                child: const Icon(Icons.add, size: 18),
                              ),
                            ),
                            if (_garmentNameControllers.length > 3) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                                onPressed: () => _removeGarmentRow(index),
                              )
                            ]
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: _addGarmentRow,
                      icon: Icon(Icons.add_circle_outline_rounded, size: 18, color: themeColor),
                      label: Text("Add More Items", style: TextStyle(color: themeColor, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // CARD SECTION 5: BILL SUMMARY
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
                        color: themeColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 35),
              ],
              
              // ACTION BUTTON
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: themeColor.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6))]
                ),
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: themeColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _isSubmitting ? null : _submitForm,
                  child: _isSubmitting 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text("CONFIRM LAUNDRY PICKUP", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white, letterSpacing: 0.8)),
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
            color: isMuted ? Colors.grey : const Color(0xFF222222),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 17 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
            color: color ?? const Color(0xFF222222),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF222222), letterSpacing: 0.3)),
    );
  }

  Widget _buildSectionContainer({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, Color focusColor, {int maxLines = 1, TextInputType keyboardType = TextInputType.text, String? hintText}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 15, color: Color(0xFF222222)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
          hintText: hintText,
          prefixIcon: Icon(icon, size: 22, color: Colors.grey.shade500),
          filled: true,
          fillColor: const Color(0xFFFAFAFC),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: focusColor, width: 1.8)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200, width: 1)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade400, width: 1)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red, width: 1.8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        validator: (val) {
          if (label.contains("Optional")) return null;
          return (val == null || val.isEmpty) ? "Field cannot be empty" : null;
        },
      ),
    );
  }
}