import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CleaningServiceForm extends StatefulWidget {
  const CleaningServiceForm({super.key});

  @override
  State<CleaningServiceForm> createState() => _CleaningServiceFormState();
}

class _CleaningServiceFormState extends State<CleaningServiceForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
  final TextEditingController _otherController = TextEditingController();

  String _selectedType = 'House';
  bool _isSubmitting = false;

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('cleaning_service').add({
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'contact': _contactController.text.trim(),
        'landmark': _landmarkController.text.trim(),
        'type': _selectedType,
        'other_details': _selectedType == 'Other' ? _otherController.text.trim() : '',
        'userId': user?.uid ?? 'anonymous',
        'status': 'Pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 60),
              const SizedBox(height: 15),
              const Text("Details Successful!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 10),
              const Text("We will call you back in 24 hrs.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF333333)),
                  onPressed: () {
                    Navigator.pop(context); 
                    Navigator.pop(context); 
                  },
                  child: const Text("OK"),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Submission failed: $e")));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Book Cleaning Service")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildField(_nameController, "Name", Icons.person),
              _buildField(_addressController, "Address", Icons.home, maxLines: 2),
              _buildField(_contactController, "Contact", Icons.phone, keyboardType: TextInputType.phone),
              _buildField(_landmarkController, "Landmark", Icons.map),
              
              const SizedBox(height: 10),
              const Text("Property Type", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: ['House', 'Flat', 'Office', 'Other'].map((type) {
                  bool isSel = _selectedType == type;
                  return ChoiceChip(
                    label: Text(type),
                    selected: isSel,
                    onSelected: (val) => setState(() => _selectedType = type),
                    selectedColor: const Color(0xFFFD3C68).withOpacity(0.2),
                    labelStyle: TextStyle(color: isSel ? const Color(0xFFFD3C68) : Colors.black),
                  );
                }).toList(),
              ),

              if (_selectedType == 'Other') ...[
                const SizedBox(height: 15),
                _buildField(_otherController, "Enter what is others", Icons.edit_note),
              ],

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFD3C68), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: _isSubmitting ? null : _submitForm,
                  child: _isSubmitting 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text("PLACE THE SERVICE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        validator: (val) => (val == null || val.isEmpty) ? "Required" : null,
      ),
    );
  }
}