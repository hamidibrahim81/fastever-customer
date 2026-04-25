import 'package:flutter/material.dart';

class AddRequestItemSheet extends StatefulWidget {
  final Function(Map<String, dynamic>) onAdd;

  const AddRequestItemSheet({super.key, required this.onAdd});

  @override
  State<AddRequestItemSheet> createState() =>
      _AddRequestItemSheetState();
}

class _AddRequestItemSheetState extends State<AddRequestItemSheet> {
  final nameController = TextEditingController();
  final brandController = TextEditingController();
  final qtyController = TextEditingController();
  final phoneController = TextEditingController();

  void _submit() {
    if (nameController.text.isEmpty ||
        qtyController.text.isEmpty ||
        phoneController.text.isEmpty) {
      return;
    }

    widget.onAdd({
      "name": nameController.text,
      "brand": brandController.text,
      "qty": qtyController.text,
      "phone": phoneController.text,
    });

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Add Request Item",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 15),

          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: "Item Name"),
          ),

          TextField(
            controller: brandController,
            decoration:
                const InputDecoration(labelText: "Brand (optional)"),
          ),

          TextField(
            controller: qtyController,
            decoration:
                const InputDecoration(labelText: "Weight / Quantity"),
          ),

          TextField(
            controller: phoneController,
            decoration:
                const InputDecoration(labelText: "Contact Number"),
            keyboardType: TextInputType.phone,
          ),

          const SizedBox(height: 15),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submit,
              child: const Text("Add Item"),
            ),
          ),
        ],
      ),
    );
  }
}