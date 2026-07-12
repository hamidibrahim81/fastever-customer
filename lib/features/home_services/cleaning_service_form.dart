import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Ensure you have intl added to your pubspec.yaml for formatting

// Ensure this path matches your project structure
import '../food/cart/ManageAddressScreen.dart'; 

class CleaningServiceForm extends StatefulWidget {
  final String serviceType; 

  const CleaningServiceForm({super.key, required this.serviceType});

  @override
  State<CleaningServiceForm> createState() => _CleaningServiceFormState();
}

class _CleaningServiceFormState extends State<CleaningServiceForm> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _issueDescriptionController = TextEditingController(); 
  final TextEditingController _landmarkController = TextEditingController();
  final TextEditingController _otherController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();

  // Location & Meta data states
  String? _selectedAddress; 
  double? _latitude;
  double? _longitude;
  String _selectedType = 'House';
  bool _isSubmitting = false;
  bool _addressTouchedAndEmpty = false;

  // Stored DateTime values for database submission
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _issueDescriptionController.dispose();
    _landmarkController.dispose();
    _otherController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  // UI Theme color assignment
  Color _getServiceColor() {
    switch (widget.serviceType) {
      case "Electrician": return const Color(0xFFFFB300);
      case "Plumber": return const Color(0xFF2196F3);
      case "House Cleaning": return const Color(0xFFFD3C68);
      case "AC Service": return const Color(0xFF00BCD4);
      case "Appliance Repair": return const Color(0xFF4CAF50);
      case "Home Shifting": return const Color(0xFF9C27B0);
      default: return const Color(0xFFFD3C68);
    }
  }

  // Dynamic context hints depending on the selected service type
  Map<String, String> _getDynamicFieldContent() {
    switch (widget.serviceType) {
      case "Electrician":
        return {
          "label": "Electrical issue or requirements *",
          "hint": "E.g., short circuit in kitchen, ceiling fan installation, full house wiring check up..."
        };
      case "Plumber":
        return {
          "label": "Plumbing issue or requirements *",
          "hint": "E.g., bathroom pipe leakage, new basin tap installation, low water pressure..."
        };
      case "House Cleaning":
        return {
          "label": "Cleaning requirements & time needed *",
          "hint": "E.g., deep kitchen cleaning, 3 BHK flat full wash, looking for 4 hours service package..."
        };
      case "AC Service":
        return {
          "label": "AC problems or service details *",
          "hint": "E.g., AC not cooling, gas refill needed, deep master filter cleaning service..."
        };
      case "Appliance Repair":
        return {
          "label": "Appliance issue details *",
          "hint": "E.g., Refrigerator not cooling, Washing machine error code, Microwave breakdown..."
        };
      case "Home Shifting":
        return {
          "label": "Shifting details & inventory volume *",
          "hint": "E.g., Shifting 2 BHK household furniture to sector 4, packing support needed..."
        };
      default:
        return {
          "label": "Job description & details *",
          "hint": "Provide details about the professional task requested..."
        };
    }
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
    } else if (result != null && result is String) {
      setState(() {
        _selectedAddress = result;
        _latitude = 0.0; 
        _longitude = 0.0;
        _addressTouchedAndEmpty = false;
      });
    }
  }

  // Date Picker Logic
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(), // Prevents picking past dates
      lastDate: DateTime.now().add(const Duration(days: 30)), // Restricts to 30 days ahead
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _getServiceColor(),
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

  // Time Picker Logic
  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _getServiceColor(),
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
    final bool isFormValid = _formKey.currentState!.validate();
    
    if (_selectedAddress == null || _selectedAddress!.isEmpty) {
      setState(() {
        _addressTouchedAndEmpty = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a service delivery address.")),
      );
      return;
    }

    if (!isFormValid) return;

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      
      // Combine date and time if both are selected for uniform DB handling
      String scheduledDateTimeString = "";
      if (_selectedDate != null && _selectedTime != null) {
        final combinedDateTime = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute,
        );
        scheduledDateTimeString = combinedDateTime.toIso8601String();
      }

      await FirebaseFirestore.instance.collection('home_service').add({
        'service_category': widget.serviceType,
        'name': _nameController.text.trim(),
        'contact': _contactController.text.trim(),
        'address': _selectedAddress,
        'latitude': _latitude ?? 0.0,
        'longitude': _longitude ?? 0.0,
        'issue_description': _issueDescriptionController.text.trim(),
        'property_type': _selectedType,
        'landmark': _landmarkController.text.trim(), 
        'other_details': _selectedType == 'Other' ? _otherController.text.trim() : '', 
        'userId': user?.uid ?? 'anonymous',
        'status': 'Pending',
        'scheduled_date': _dateController.text, // Stores plain date string "YYYY-MM-DD"
        'scheduled_time': _timeController.text, // Stores local structured time string "HH:MM AM/PM"
        'scheduled_timestamp': scheduledDateTimeString, // Combined clear sorting track index
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          elevation: 5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 55),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Request Successful!", 
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Color(0xFF222222)),
                ),
                const SizedBox(height: 14),
                Text(
                  "We will contact you within 2 hours.", 
                  textAlign: TextAlign.center, 
                  style: TextStyle(color: Colors.grey.shade800, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                ),
                const SizedBox(height: 4),
                Text(
                  "ഞങ്ങൾ 2 മണിക്കൂറിനുള്ളിൽ നിങ്ങളെ ബന്ധപ്പെടും.", 
                  textAlign: TextAlign.center, 
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4, fontWeight: FontWeight.normal),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF222222),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
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
        SnackBar(content: Text("Submission failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _getServiceColor();
    final dynamicStrings = _getDynamicFieldContent();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF222222),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        centerTitle: true,
        title: Text(
          "Book ${widget.serviceType}",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
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

              // CARD SECTION 2: SCHEDULE DATE & TIME
              _buildSectionHeader("Schedule Appointment"),
              _buildSectionContainer(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _selectDate,
                        child: IgnorePointer(
                          child: _buildField(
                            _dateController, 
                            "Preferred Date *", 
                            Icons.calendar_month_rounded, 
                            themeColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: _selectTime,
                        child: IgnorePointer(
                          child: _buildField(
                            _timeController, 
                            "Preferred Time *", 
                            Icons.access_time_rounded, 
                            themeColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // CARD SECTION 3: LOCATION INFORMATION
              _buildSectionHeader("Service Location"),
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
                                    : themeColor.withOpacity(0.1),
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
                                    _selectedAddress != null ? "Selected Delivery Address" : "Select saved address *",
                                    style: TextStyle(
                                      fontSize: 14, 
                                      fontWeight: FontWeight.bold,
                                      color: _addressTouchedAndEmpty 
                                          ? Colors.red.shade700 
                                          : (_selectedAddress != null ? themeColor : Colors.grey.shade800),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedAddress ?? "Tap to import your address details",
                                    style: TextStyle(
                                      fontSize: 13, 
                                      color: _selectedAddress != null ? Colors.black87 : Colors.grey.shade500,
                                      height: 1.3
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
                          "Service delivery address is mandatory *",
                          style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSectionContainer(
                child: _buildField(_landmarkController, "Landmark / Building Floor (Optional)", Icons.domain_rounded, themeColor),
              ),
              const SizedBox(height: 22),

              // CARD SECTION 4: JOB SPECIFICATIONS
              _buildSectionHeader("Requirement Details"),
              _buildSectionContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildField(
                      _issueDescriptionController, 
                      dynamicStrings["label"] ?? "Specifications *", 
                      Icons.assignment_outlined, 
                      themeColor,
                      maxLines: 4,
                      hintText: dynamicStrings["hint"],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Property Type Setup", 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey.shade800),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: ['House', 'Flat', 'Office', 'Other'].map((type) {
                        bool isSel = _selectedType == type;
                        return ChoiceChip(
                          label: Text(type),
                          selected: isSel,
                          onSelected: (val) => setState(() => _selectedType = type),
                          selectedColor: themeColor.withOpacity(0.15),
                          checkmarkColor: themeColor,
                          elevation: 0,
                          pressElevation: 0,
                          side: BorderSide(color: isSel ? themeColor : Colors.grey.shade300),
                          labelStyle: TextStyle(
                            color: isSel ? themeColor : Colors.grey.shade800, 
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13
                          ),
                        );
                      }).toList(),
                    ),
                    if (_selectedType == 'Other') ...[
                      const SizedBox(height: 14),
                      _buildField(_otherController, "Describe specific workspace (Optional)", Icons.edit_note_rounded, themeColor),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 35),
              
              // PREMIUM ELEVATED ACTION DISPATCH BUTTON
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: themeColor.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    )
                  ]
                ),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: themeColor, 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isSubmitting ? null : _submitForm,
                  child: _isSubmitting 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : Text(
                        "DISPATCH ${widget.serviceType.toUpperCase()}", 
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white, letterSpacing: 0.8),
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

  // Premium UI Component: Section Header Titles
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title, 
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF222222), letterSpacing: 0.3),
      ),
    );
  }

  // Premium UI Component: Card Wrapper Layout
  Widget _buildSectionContainer({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: child,
    );
  }

  // Premium UI Component: Styled Text Fields
  Widget _buildField(
    TextEditingController controller, 
    String label, 
    IconData icon, 
    Color focusColor, {
    int maxLines = 1, 
    TextInputType keyboardType = TextInputType.text,
    String? hintText,
  }) {
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
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(icon, size: 22, color: Colors.grey.shade500),
          filled: true,
          fillColor: const Color(0xFFFAFAFC),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: focusColor, width: 1.8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.red.shade400, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 1.8),
          ),
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