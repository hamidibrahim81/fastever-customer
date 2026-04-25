import 'package:flutter/material.dart';

import 'add_request_item_sheet.dart';
import 'request_cart_screen.dart';

class RequestItemListScreen extends StatefulWidget {
  const RequestItemListScreen({super.key});

  @override
  State<RequestItemListScreen> createState() =>
      _RequestItemListScreenState();
}

class _RequestItemListScreenState extends State<RequestItemListScreen> {
  final List<Map<String, dynamic>> items = [];

  void _addItem(Map<String, dynamic> item) {
    setState(() {
      items.add(item);
    });
  }

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddRequestItemSheet(onAdd: _addItem),
    );
  }

  void _goToCart() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RequestCartScreen(items: items),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Request Items"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text("No items added yet"))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        return Card(
                          child: ListTile(
                            title: Text(item['name']),
                            subtitle: Text(
                                "${item['qty']} | ${item['phone']}"),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _openAddSheet,
                child: const Text("Add Item"),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: items.isEmpty ? null : _goToCart,
                child: const Text("View Cart"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}