import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A standard card container for sections in detail views.
class DetailSection extends StatelessWidget {
  const DetailSection({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: ThemeSize.space12),
      child: Padding(
        padding: ThemePadding.paddingAll12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (trailing != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  trailing!,
                ],
              )
            else
              Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: ThemeSize.space8),
            child,
          ],
        ),
      ),
    );
  }
}

/// A standard two-column key-value row for detail views.
class DetailKeyValueRow extends StatelessWidget {
  const DetailKeyValueRow({
    required this.label,
    required this.valueWidget,
    super.key,
  });

  DetailKeyValueRow.text(String label, String value, {Key? key})
    : this(label: label, valueWidget: SelectableText(value), key: key);

  final String label;
  final Widget valueWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ThemeSize.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ThemeSize.size120,
            child: Text(
              '$label:',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: ThemeSize.space8),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}
