import 'package:flutter/material.dart';

class PackageList extends StatelessWidget {
  final List<String> packages;
  final bool isLoading;
  final String? selectedPackage;
  final Function(String) onPackageSelected;
  final Function(int, int) onReorder;

  const PackageList({
    super.key,
    required this.packages,
    required this.isLoading,
    required this.selectedPackage,
    required this.onPackageSelected,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : packages.isNotEmpty
              ? ReorderableListView.builder(
                  itemCount: packages.length,
                  itemBuilder: (context, index) {
                    final package = packages[index];
                    return ListTile(
                      key: ValueKey(package),
                      title: Text(package),
                      selected: package == selectedPackage,
                      onTap: () => onPackageSelected(package),
                    );
                  },
                  onReorder: onReorder,
                )
              : const Center(child: Text('No Flutter packages found.')),
    );
  }
}
