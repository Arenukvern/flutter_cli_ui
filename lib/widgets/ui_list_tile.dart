import 'package:flutter/material.dart';

class UiListTile extends StatelessWidget {
  const UiListTile({
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isSelected = false,
    this.isOutdated = false,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool isOutdated;

  @override
  Widget build(final BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      color: isSelected ? Colors.blue.withValues(alpha: 0.1) : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isOutdated ? Colors.red : null,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: isOutdated ? Colors.red[300] : Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}
