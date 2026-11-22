import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Reusable searchable picker for backend-provided catalog masters.
class CatalogSearchOption {
  const CatalogSearchOption(this.value, this.label);
  final String value;
  final String label;
}

class CatalogSearchSheet extends StatefulWidget {
  const CatalogSearchSheet({
    super.key,
    required this.title,
    required this.options,
    this.selected,
  });

  final String title;
  final List<CatalogSearchOption> options;
  final String? selected;

  @override
  State<CatalogSearchSheet> createState() => _CatalogSearchSheetState();
}

class _CatalogSearchSheetState extends State<CatalogSearchSheet> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final height = math.max(
      190.0,
      math.min(500.0, MediaQuery.sizeOf(context).height * 0.74 - keyboard),
    );
    final query = search.text.trim().toLowerCase();
    final visible = widget.options
        .where((item) => item.label.toLowerCase().contains(query))
        .toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              TextField(
                key: const Key('catalog-option-search'),
                controller: search,
                autofocus: false,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search options',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(widget.options.isEmpty
                            ? 'No options are available. Refresh the catalog.'
                            : 'No matches. Try another name.'))
                    : ListView.builder(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final option = visible[index];
                          return ListTile(
                            key: Key('catalog-option-${option.value}'),
                            title: Text(option.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            trailing: widget.selected == option.value
                                ? const Icon(Icons.check_circle_rounded)
                                : null,
                            onTap: () => Navigator.pop(context, option.value),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
