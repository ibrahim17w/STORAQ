// lib/screens/see_all_screen.dart
import 'package:flutter/material.dart';
import '../widgets/product/product_card.dart';
import '../widgets/product/product_list_tile.dart';
import '../widgets/store/store_card.dart';
import '../widgets/store/store_list_tile.dart';

class SeeAllScreen extends StatefulWidget {
  final String title;
  final List<dynamic> items;
  final bool isStore;
  final void Function(dynamic) onProductTap;
  final void Function(dynamic) onStoreTap;

  const SeeAllScreen({
    super.key,
    required this.title,
    required this.items,
    required this.isStore,
    required this.onProductTap,
    required this.onStoreTap,
  });

  @override
  State<SeeAllScreen> createState() => _SeeAllScreenState();
}

class _SeeAllScreenState extends State<SeeAllScreen> {
  bool _isGrid = true;

  void _toggleView() => setState(() => _isGrid = !_isGrid);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_isGrid ? Icons.view_list : Icons.grid_view),
            onPressed: _toggleView,
          ),
        ],
      ),
      body: _isGrid ? _buildGrid() : _buildList(),
    );
  }

  Widget _buildGrid() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.start,
        children: widget.items.map((item) {
          if (widget.isStore) {
            return StoreCard(
              store: item,
              onTap: () => widget.onStoreTap(item),
              width: 160,
            );
          }
          return ProductCard(
            product: item,
            onTap: () => widget.onProductTap(item),
            width: 160,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: widget.items.length,
      itemBuilder: (context, i) {
        if (widget.isStore) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: StoreListTile(
              store: widget.items[i],
              onTap: () => widget.onStoreTap(widget.items[i]),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ProductListTile(
            product: widget.items[i],
            onTap: () => widget.onProductTap(widget.items[i]),
          ),
        );
      },
    );
  }
}
