import 'package:flutter/material.dart';
import 'customer_api.dart';
import 'customer_design.dart';
import 'customer_checkout.dart';
import 'customer_workspace.dart';

IconData materialIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('plumbing') || n.contains('pipe'))
    return Icons.plumbing_rounded;
  if (n.contains('waterproof')) return Icons.water_drop_outlined;
  if (n.contains('electrical')) return Icons.electrical_services_outlined;
  if (n.contains('hardware')) return Icons.handyman_outlined;
  if (n.contains('ready-mix')) return Icons.foundation_outlined;
  return n.contains('cement')
      ? Icons.foundation_outlined
      : n.contains('steel')
      ? Icons.view_week_outlined
      : n.contains('brick')
      ? Icons.grid_view_rounded
      : n.contains('sand')
      ? Icons.landscape_outlined
      : n.contains('paint')
      ? Icons.format_paint_outlined
      : Icons.category_outlined;
}

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key, this.categoriesOnly = false});
  final bool categoriesOnly;
  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  String? category;
  String search = '';
  final query = TextEditingController();
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = CustomerScope.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'splyzo',
                    style: TextStyle(
                      fontFamily: 'packages/kraveo_ui/Bricolage',
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.3,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () => push(context, const NotificationsPage()),
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => push(context, const AddressesPage()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 19,
                        color: accent,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          s.address == null
                              ? 'Choose your delivery site'
                              : '${field(s.address!, 'label')} · ${field(s.address!, 'locality')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down, size: 18),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
              child: TextField(
                controller: query,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => setState(() => search = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search materials',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      query.clear();
                      setState(() => search = '');
                    },
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
              ),
            ),
            Expanded(
              child: RemotePage<Data>(
                key: ValueKey('$category|$search|${widget.categoriesOnly}'),
                load: () async {
                  final results = await Future.wait<dynamic>([
                    s.api.categories(),
                    s.api.products(category: category, search: search),
                  ]);
                  return {'categories': results[0], 'page': results[1]};
                },
                builder: (data, reload) {
                  final categories = rows(data['categories']);
                  final page = object(data['page']);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (!widget.categoriesOnly &&
                          search.isEmpty &&
                          category == null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(25),
                          child: Container(
                            color: ink,
                            child: Stack(
                              children: [
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: 165,
                                  child: Image.asset(
                                    'assets/images/construction_hero_banner.jpg',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          ink,
                                          ink.withValues(alpha: .94),
                                          ink.withValues(alpha: .08),
                                        ],
                                        stops: const [0, .48, 1],
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'BUILT FOR YOUR NEXT BIG THING',
                                        style: TextStyle(
                                          color: Color(0xFFFFBB91),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 13),
                                      const Text(
                                        'Good materials.\nGreat beginnings.',
                                        style: TextStyle(
                                          fontFamily:
                                              'packages/kraveo_ui/Bricolage',
                                          fontSize: 29,
                                          fontWeight: FontWeight.w700,
                                          height: 1.12,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Source materials. Build with confidence.',
                                        style: TextStyle(
                                          color: Color(0xFFD9E1E5),
                                          fontSize: 11,
                                          height: 1.7,
                                        ),
                                      ),
                                      const SizedBox(height: 17),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: accent,
                                          foregroundColor: ink,
                                          minimumSize: const Size(0, 42),
                                        ),
                                        onPressed: () =>
                                            push(context, const RfqsPage()),
                                        child: const Text(
                                          'Get a bulk quote  ↗',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Row(
                          children: [
                            Icon(
                              Icons.fact_check_outlined,
                              color: green,
                              size: 17,
                            ),
                            SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'Supplier offers. Clear pricing. Site delivery.',
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (!widget.categoriesOnly &&
                          search.isEmpty &&
                          category == null) ...[
                        const Section('Your material partners'),
                        const SupplierStrip(),
                      ],
                      Section(
                        widget.categoriesOnly
                            ? 'Find your materials'
                            : 'Shop by category',
                      ),
                      if (categories.isEmpty)
                        const Text(
                          'Categories will appear when the catalog is published.',
                          style: TextStyle(color: muted),
                        ),
                      CategoryGrid(
                        categories: categories,
                        selected: category,
                        onChanged: (value) => setState(() => category = value),
                      ),
                      Section(
                        search.isNotEmpty
                            ? 'Results for “$search”'
                            : 'Explore materials',
                        action: category != null ? 'Clear filter' : null,
                        onTap: () => setState(() => category = null),
                      ),
                      ProductGrid(
                        products: rows(page),
                        empty:
                            'No materials found. Try another category or search.',
                      ),
                      if (page['nextCursor'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: OutlinedButton(
                            onPressed: () => push(
                              context,
                              CatalogPage(category: category, search: search),
                            ),
                            child: const Text('View more materials'),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Panel(
                        color: const Color(0xFFF0ECE2),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.support_agent_rounded,
                              size: 30,
                              color: ink,
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'A little help for your big build',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 5),
                                  Text(
                                    'Questions about an order or material?',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Get support',
                              onPressed: () =>
                                  push(context, const SupportPage()),
                              icon: const Icon(Icons.arrow_forward_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Older staging imports use several slugs for the same shopping department.
String categoryDepartment(Data category) {
  final name = field(category, 'name');
  final slug = field(category, 'slug');
  if (slug.contains('steel')) return 'Steel & rebar';
  if (slug.startsWith('plumbing')) return 'Plumbing';
  if (slug.startsWith('paints')) return 'Paint & finishes';
  return switch (slug) {
    'cement-concrete' => 'Cement',
    'ready-mix-concrete' => 'Ready-mix concrete',
    _ => name,
  };
}

class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    super.key,
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  final List<Data> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;

  Future<void> select(BuildContext context, List<Data> options) async {
    if (options.length < 2) {
      onChanged(options.isEmpty ? null : field(options.single, 'id'));
      return;
    }
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                categoryDepartment(options.first),
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
            ),
            for (final option in options)
              ListTile(
                title: Text(field(option, 'name')),
                selected: selected == option['id'],
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(sheet, field(option, 'id')),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (value != null && context.mounted) onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final departments = <String, List<Data>>{'All materials': []};
    for (final category in categories) {
      (departments[categoryDepartment(category)] ??= []).add(category);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = (constraints.maxWidth / (115 * scale)).floor().clamp(
          2,
          5,
        );
        const gap = 10.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final entry in departments.entries)
              SizedBox(
                width: width,
                child: Builder(
                  builder: (context) {
                    final active = entry.value.isEmpty
                        ? selected == null
                        : entry.value.any(
                            (category) => category['id'] == selected,
                          );
                    return Semantics(
                      button: true,
                      selected: active,
                      child: Material(
                        color: active ? const Color(0xFFFFEEE2) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: active ? accent : line),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => select(context, entry.value),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 13,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: 44 + 30 * scale,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: active
                                          ? const Color(0xFFFFDBC4)
                                          : const Color(0xFFEFF3F0),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      entry.value.isEmpty
                                          ? Icons.grid_view_rounded
                                          : materialIcon(entry.key),
                                      size: 19,
                                      color: ink,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.25,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class ProductGrid extends StatelessWidget {
  const ProductGrid({super.key, required this.products, required this.empty});
  final List<Data> products;
  final String empty;
  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return EmptyState('Nothing here yet', empty);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = (constraints.maxWidth / (142 * scale)).floor().clamp(
          1,
          4,
        );
        const gap = 12.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Column(
          children: [
            for (var index = 0; index < products.length; index += columns)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : gap),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var column = 0;
                        column < columns && index + column < products.length;
                        column++
                      ) ...[
                        if (column > 0) const SizedBox(width: gap),
                        SizedBox(
                          width: width,
                          child: ProductCard(products[index + column]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class ProductPhoto extends StatelessWidget {
  const ProductPhoto(this.product, {super.key, this.height = 120});
  final Data product;
  final double height;
  @override
  Widget build(BuildContext context) {
    final api = CustomerScope.of(context).api;
    final images = rows(product['images']);
    final uri = api.imageUri(
      product['imageUrl']?.toString() ??
          (images.isNotEmpty
              ? '/api/v2/catalog/images/${images.first['id']}'
              : null),
    );
    final fallback = Center(
      child: Icon(
        materialIcon(field(product, 'name')),
        size: 44,
        color: ink.withValues(alpha: .35),
      ),
    );
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3EE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: uri == null
          ? fallback
          : ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                uri.toString(),
                fit: BoxFit.contain,
                errorBuilder: (_, e, st) => fallback,
              ),
            ),
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard(this.product, {super.key});
  final Data product;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => push(context, ProductPage(product)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(aspectRatio: 1.28, child: ProductPhoto(product)),
            const SizedBox(height: 12),
            Text(
              field(object(product['category']), 'name', 'BUILDING MATERIAL'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: muted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              field(product, 'name'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const Spacer(),
            const SizedBox(height: 10),
            if (product['fromPrice'] != null)
              Text.rich(
                TextSpan(
                  text: price(product['fromPrice']),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  children: [
                    TextSpan(
                      text: ' / ${field(product, 'fromUnit').toLowerCase()}',
                      style: const TextStyle(
                        color: muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else
              const Text(
                'Price unavailable',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'View offers',
                    style: TextStyle(
                      fontSize: 10,
                      color: green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, size: 17, color: green),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    this.category,
    this.search,
    this.supplier,
    this.supplierName,
  });
  final String? category, search, supplier, supplierName;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final List<Data> products = [];
  String? cursor;
  bool first = true;
  @override
  Widget build(BuildContext context) {
    final api = CustomerScope.of(context).api;
    return RemotePage<Data>(
      title: widget.supplierName ?? 'Materials',
      load: () async {
        final page = await api.products(
          category: widget.category,
          supplier: widget.supplier,
          search: widget.search,
          cursor: cursor,
        );
        if (first) {
          products.clear();
          first = false;
        }
        for (final p in rows(page)) {
          if (!products.any((x) => x['id'] == p['id'])) products.add(p);
        }
        return page;
      },
      builder: (page, reload) => ListView(
        padding: const EdgeInsets.all(22),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ProductGrid(
            products: products,
            empty: 'No materials match this search.',
          ),
          if (page['nextCursor'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: OutlinedButton(
                onPressed: () {
                  cursor = field(page, 'nextCursor');
                  reload();
                },
                child: const Text('Load more'),
              ),
            ),
        ],
      ),
    );
  }
}

class ProductPage extends StatelessWidget {
  const ProductPage(this.product, {super.key});
  final Data product;
  @override
  Widget build(BuildContext context) {
    final s = CustomerScope.of(context);
    return RemotePage<List<Data>>(
      title: 'Material details',
      load: () => s.api.offers(field(product, 'id')),
      builder: (offers, reload) => ListView(
        padding: const EdgeInsets.all(22),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ProductPhoto(product, height: 240),
          const SizedBox(height: 22),
          Text(
            field(object(product['category']), 'name').toUpperCase(),
            style: const TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            field(product, 'name'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (product['description'] != null) ...[
            const SizedBox(height: 12),
            Text(
              field(product, 'description'),
              style: const TextStyle(color: muted),
            ),
          ],
          if (object(product['specification']).isNotEmpty) ...[
            const Section('Specifications'),
            Panel(
              child: Column(
                children: object(product['specification']).entries
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                label(e.key),
                                style: const TextStyle(color: muted),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${e.value}',
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          const Section('Choose a supplier offer'),
          const Text(
            'Prices and quantities are specific to each supplier. Stock and delivery are confirmed at checkout.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (offers.isEmpty)
            const EmptyState(
              'No offers available',
              'Try again later or request a bulk quotation.',
            ),
          ...offers.map(
            (o) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: OfferCard(o),
            ),
          ),
          ActionButton(
            'Request a bulk quote',
            () async => push(context, NewRfqPage(product: product)),
            tonal: true,
          ),
        ],
      ),
    );
  }
}

class OfferCard extends StatefulWidget {
  const OfferCard(this.offer, {super.key});
  final Data offer;
  @override
  State<OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<OfferCard> {
  late String quantity;
  @override
  void initState() {
    super.initState();
    quantity = field(widget.offer, 'minOrderQty', '1');
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final s = CustomerScope.of(context);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_outlined, size: 20, color: green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  field(o, 'supplierName', 'Approved supplier'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Save offer',
                onPressed: () async {
                  try {
                    if (!s.signedIn) await s.signIn();
                    if (!s.signedIn) return;
                    await s.api.call(
                      '/api/v2/me/wishlist/${o['id']}',
                      method: 'PUT',
                      body: {},
                    );
                    if (context.mounted) {
                      notice(context, 'Saved to your wishlist');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      notice(
                        context,
                        e is CustomerProblem
                            ? e.message
                            : 'Unable to save this offer.',
                      );
                    }
                  }
                },
                icon: const Icon(Icons.favorite_border_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${price(o['unitPrice'])} / ${o['unitCode']}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Text(
            'Minimum ${o['minOrderQty']} ${o['unitCode']} · increments of ${o['stepQty']}',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          Text(
            o['taxInclusive'] == true
                ? 'Tax included'
                : 'Tax calculated at checkout',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          if (rows(o['priceTiers']).isNotEmpty) ...[
            const SizedBox(height: 10),
            ...rows(o['priceTiers']).map(
              (t) => Text(
                '${t['minQty']}+ ${o['unitCode']}: ${price(t['pricePerUnit'])} per unit',
                style: const TextStyle(fontSize: 11, color: green),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Decrease quantity',
                      onPressed: () => setState(
                        () => quantity = quantityStep(
                          quantity,
                          field(o, 'minOrderQty', '1'),
                          field(o, 'stepQty', '1'),
                          o['maxOrderQty']?.toString(),
                          -1,
                        ),
                      ),
                      icon: const Icon(Icons.remove, size: 18),
                    ),
                    Text(
                      quantity,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      tooltip: 'Increase quantity',
                      onPressed: () => setState(
                        () => quantity = quantityStep(
                          quantity,
                          field(o, 'minOrderQty', '1'),
                          field(o, 'stepQty', '1'),
                          o['maxOrderQty']?.toString(),
                          1,
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                    ),
                  ],
                ),
              ),
              ActionButton('Add to cart', () async {
                if (!s.signedIn) await s.signIn();
                if (!s.signedIn) return;
                final cart = await s.api.cart();
                await s.api.setLine(
                  field(o, 'id'),
                  quantity,
                  cart['version'] as int,
                );
                if (context.mounted) {
                  notice(context, 'Added to your cart');
                  push(context, const CartPage());
                }
              }, icon: Icons.shopping_bag_outlined),
            ],
          ),
        ],
      ),
    );
  }
}

class SupplierStrip extends StatefulWidget {
  const SupplierStrip({super.key});
  @override
  State<SupplierStrip> createState() => _SupplierStripState();
}

class _SupplierStripState extends State<SupplierStrip> {
  Future<dynamic>? future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= CustomerScope.of(
      context,
    ).api.call('/api/v2/catalog/suppliers', authenticated: false);
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<dynamic>(
    future: future,
    builder: (c, s) {
      if (s.connectionState != ConnectionState.done) {
        return const SizedBox(
          height: 70,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (s.hasError) {
        return const Text(
          'Supplier directory is temporarily unavailable.',
          style: TextStyle(color: muted, fontSize: 12),
        );
      }
      final list = rows(s.data);
      if (list.isEmpty) {
        return const Text(
          'Supplier storefronts will appear as materials become available.',
          style: TextStyle(color: muted, fontSize: 12),
        );
      }
      return SizedBox(
        height: 108 + MediaQuery.textScalerOf(c).scale(36),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list.length,
          separatorBuilder: (_, i) => const SizedBox(width: 10),
          itemBuilder: (c, i) {
            final p = list[i];
            return SizedBox(
              width: 170,
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: line),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => push(
                    c,
                    CatalogPage(
                      supplier: field(p, 'id'),
                      supplierName: field(p, 'displayName'),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.storefront_outlined, color: green),
                        const SizedBox(height: 12),
                        Text(
                          field(p, 'displayName'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'View materials  ↗',
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}
