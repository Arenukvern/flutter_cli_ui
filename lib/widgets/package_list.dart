import 'package:flutter/material.dart';
import 'package:flutter_cli_ui/widgets/ui_list_tile.dart';

class PackageList extends StatelessWidget {
  const PackageList({
    required this.packages,
    required this.isLoading,
    required this.selectedPackage,
    required this.onPackageSelected,
    required this.onReorder,
    super.key,
  });
  final List<String> packages;
  final bool isLoading;
  final String? selectedPackage;
  final Function(String) onPackageSelected;
  final Function(int, int) onReorder;

  @override
  Widget build(final BuildContext context) => Card(
    margin: const EdgeInsets.all(8),
    child: isLoading
        ? const Center(child: CircularProgressIndicator())
        : packages.isNotEmpty
        ? ReorderableListView.builder(
            itemCount: packages.length,
            itemBuilder: (final context, final index) {
              final package = packages[index];
              return UiListTile(
                key: ValueKey(package),
                title: package,
                isSelected: package == selectedPackage,
                onTap: () => onPackageSelected(package),
              );
            },
            onReorder: onReorder,
          )
        : const Center(child: Text('No Flutter packages found.')),
  );
}
