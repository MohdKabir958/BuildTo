import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'customer_api.dart';
import 'customer_design.dart';
import 'customer_catalog.dart';
import 'customer_workspace.dart';

/// Navy / orange design language taken from the approved customer mockups.
/// Keep labels and prices dynamic: screenshot examples are not live suppliers.
abstract final class SplyzoReferenceColors {
  static const navy = Color(0xFF071B4C);
  static const deepBlue = Color(0xFF07336F);
  static const orange = Color(0xFFFF7000);
  static const field = Color(0xFFECF3FD);
  static const border = Color(0xFFD7E2F4);
  static const secondary = Color(0xFF455472);
}

class SplyzoReferenceLogo extends StatelessWidget {
  const SplyzoReferenceLogo({super.key, this.large = false});
  final bool large;

  @override
  Widget build(BuildContext context) {
    final height = large ? 55.0 : 39.0;
    return SizedBox(
      height: height,
      child: const FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 87,
              height: 62,
              child: CustomPaint(painter: _SplyzoSkyline()),
            ),
            SizedBox(width: 4),
            Text(
              'Splyzo',
              style: TextStyle(
                fontFamily: 'packages/kraveo_ui/Bricolage',
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.7,
                color: SplyzoReferenceColors.navy,
              ),
            ),
            SizedBox(width: 2),
            Icon(
              Icons.location_on_rounded,
              size: 35,
              color: SplyzoReferenceColors.orange,
            ),
          ],
        ),
      ),
    );
  }
}

class _SplyzoSkyline extends CustomPainter {
  const _SplyzoSkyline();

  @override
  void paint(Canvas canvas, Size size) {
    const blue = SplyzoReferenceColors.navy;
    const blueLight = Color(0xFF237DDB);
    const orange = SplyzoReferenceColors.orange;
    final towers = [
      (7.0, 25.0, 14.0),
      (20.0, 19.0, 22.0),
      (34.0, 11.0, 30.0),
      (49.0, 4.0, 37.0),
      (64.0, 16.0, 25.0),
    ];
    for (var i = 0; i < towers.length; i++) {
      final (x, top, h) = towers[i];
      final r = Rect.fromLTWH(x, top, i == 3 ? 13 : 11, h);
      canvas.drawRect(r, Paint()..color = i.isEven ? blue : blueLight);
      for (double wx = x + 2; wx < r.right - 2; wx += 4) {
        for (double wy = top + 5; wy < r.bottom - 2; wy += 7) {
          canvas.drawRect(
            Rect.fromLTWH(wx, wy, 1.5, 3),
            Paint()..color = const Color(0xFFE8F6FF),
          );
        }
      }
    }
    final path = Path()
      ..moveTo(0, 54)
      ..quadraticBezierTo(41, 37, 86, 54)
      ..quadraticBezierTo(43, 47, 0, 58)
      ..close();
    canvas.drawPath(path, Paint()..color = orange);
    final highlight = Path()
      ..moveTo(18, 49)
      ..quadraticBezierTo(47, 42, 78, 50);
    canvas.drawPath(
      highlight,
      Paint()
        ..color = const Color(0xFFFFBB1C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SplyzoReferenceBanner extends StatelessWidget {
  const SplyzoReferenceBanner({super.key, this.auth = false});
  final bool auth;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: auth ? 3.12 : 3.8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 370;
            return Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: SplyzoReferenceColors.deepBlue),
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/construction_hero_banner.jpg',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF061C4C),
                        Color(0xFF072B65),
                        Color(0xFF074B91),
                        Color(0x00084B91),
                      ],
                      stops: [0, .40, .65, 1],
                    ),
                  ),
                ),
                Positioned(
                  top: -30,
                  bottom: -30,
                  left: constraints.maxWidth * .60,
                  child: Container(
                    width: 5,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFAD00),
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                    transform: Matrix4.skewX(-.24),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 13 : 17,
                    13,
                    9,
                    compact ? 9 : 13,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: auth
                              ? const [
                                  TextSpan(text: 'India’s Trusted\n'),
                                  TextSpan(
                                    text: 'Building Materials\n',
                                    style: TextStyle(color: Color(0xFFFFB01A)),
                                  ),
                                  TextSpan(text: 'Marketplace'),
                                ]
                              : const [
                                  TextSpan(text: 'Building Materials\nFrom '),
                                  TextSpan(
                                    text: 'Trusted Suppliers',
                                    style: TextStyle(color: Color(0xFFFFAD13)),
                                  ),
                                ],
                        ),
                        maxLines: auth ? 3 : 2,
                        style: TextStyle(
                          fontSize: auth
                              ? (compact ? 15 : 18)
                              : (compact ? 14 : 16),
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.12,
                          letterSpacing: -.6,
                        ),
                      ),
                      FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: compact ? 12 : 15,
                              color: const Color(0xFFFFB01A),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Verified Suppliers',
                              style: TextStyle(
                                fontSize: compact ? 7.5 : 9,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: compact ? 10 : 15),
                            Icon(
                              Icons.local_shipping_outlined,
                              size: compact ? 14 : 17,
                              color: const Color(0xFFFFB01A),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'On-time Delivery',
                              style: TextStyle(
                                fontSize: compact ? 7.5 : 9,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SplyzoReferenceHome extends StatefulWidget {
  const SplyzoReferenceHome({super.key});
  @override
  State<SplyzoReferenceHome> createState() => _SplyzoReferenceHomeState();
}

class _HomeContent {
  const _HomeContent(this.categories, this.products, this.suppliers);
  final List<Data> categories, products, suppliers;
}

class _SplyzoReferenceHomeState extends State<SplyzoReferenceHome> {
  Future<_HomeContent>? _future;
  final search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _fetch();
  }

  Future<_HomeContent> _fetch() async {
    final api = CustomerScope.of(context).api;
    Future<List<Data>> safeCategories() async {
      try {
        return await api.categories();
      } catch (_) {
        return [];
      }
    }

    Future<List<Data>> safeProducts() async {
      try {
        return rows(await api.products());
      } catch (_) {
        return [];
      }
    }

    Future<List<Data>> safeSuppliers() async {
      try {
        return rows(
          await api.call('/api/v2/catalog/suppliers', authenticated: false),
        );
      } catch (_) {
        return [];
      }
    }

    final values = await Future.wait<List<Data>>([
      safeCategories(),
      safeProducts(),
      safeSuppliers(),
    ]);
    return _HomeContent(values[0], values[1], values[2]);
  }

  Future<void> _reload() async {
    final next = _fetch();
    setState(() => _future = next);
    await next;
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = CustomerScope.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 13, 9),
              child: Row(
                children: [
                  const Expanded(child: SplyzoReferenceLogo()),
                  Material(
                    color: Colors.white,
                    shape: const StadiumBorder(
                      side: BorderSide(color: SplyzoReferenceColors.border),
                    ),
                    child: InkWell(
                      key: const Key('reference-location'),
                      customBorder: const StadiumBorder(),
                      onTap: () => push(context, const AddressesPage()),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              color: SplyzoReferenceColors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 3),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 84),
                              child: Text(
                                scope.address == null
                                    ? 'Choose area'
                                    : field(
                                        scope.address!,
                                        'locality',
                                        field(
                                          scope.address!,
                                          'label',
                                          'Your site',
                                        ),
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: SplyzoReferenceColors.navy,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: SplyzoReferenceColors.navy,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () => push(context, const NotificationsPage()),
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      color: SplyzoReferenceColors.navy,
                      size: 26,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
              child: TextField(
                key: const Key('reference-search'),
                controller: search,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    push(context, CatalogPage(search: value.trim()));
                  }
                },
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search for cement, steel, paint...',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: SplyzoReferenceColors.navy,
                    size: 24,
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Search materials',
                    icon: const Icon(
                      Icons.mic_none_rounded,
                      color: SplyzoReferenceColors.secondary,
                    ),
                    onPressed: () =>
                        push(context, CatalogPage(search: search.text.trim())),
                  ),
                  filled: true,
                  fillColor: SplyzoReferenceColors.field,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: const BorderSide(
                      color: SplyzoReferenceColors.border,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: const BorderSide(
                      color: SplyzoReferenceColors.border,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<_HomeContent>(
                future: _future,
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView(
                      key: const Key('reference-home-scroll'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 22),
                      children: [
                        const SplyzoReferenceBanner(),
                        const SizedBox(height: 8),
                        _SectionTitle(
                          title: 'Nearby Suppliers',
                          action: 'See All',
                          onTap: () =>
                              push(context, const _SupplierDirectory()),
                        ),
                        if (data == null &&
                            snapshot.connectionState != ConnectionState.done)
                          const SizedBox(
                            height: 115,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (data == null || data.suppliers.isEmpty)
                          const _EmptyRow(
                            'Approved suppliers will appear here when available.',
                            icon: Icons.storefront_outlined,
                          )
                        else
                          SizedBox(
                            height: 137,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: math.min(6, data.suppliers.length),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 9),
                              itemBuilder: (context, index) =>
                                  _SupplierCard(data.suppliers[index]),
                            ),
                          ),
                        _SectionTitle(
                          title: 'Shop by Category',
                          action: 'View All',
                          onTap: () => push(
                            context,
                            Scaffold(
                              appBar: AppBar(title: const Text('Categories')),
                              body: const SafeArea(
                                child: CustomerHome(categoriesOnly: true),
                              ),
                            ),
                          ),
                        ),
                        _Categories(
                          categories: data?.categories ?? [],
                          loading:
                              data == null &&
                              snapshot.connectionState != ConnectionState.done,
                        ),
                        _SectionTitle(
                          title: 'Best Deals Near You',
                          action: 'See All',
                          onTap: () => push(context, const CatalogPage()),
                        ),
                        if (data == null &&
                            snapshot.connectionState != ConnectionState.done)
                          const SizedBox(
                            height: 115,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (data == null || data.products.isEmpty)
                          const _EmptyRow(
                            'Products and live prices will appear here.',
                            icon: Icons.inventory_2_outlined,
                          )
                        else
                          SizedBox(
                            height: 138,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: math.min(8, data.products.length),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) =>
                                  _DealCard(data.products[index]),
                            ),
                          ),
                      ],
                    ),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.action,
    required this.onTap,
  });
  final String title, action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(1, 17, 0, 10),
    child: Row(
      children: [
        Container(
          width: 5,
          height: 23,
          decoration: BoxDecoration(
            color: SplyzoReferenceColors.orange,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            style: const TextStyle(
              color: SplyzoReferenceColors.navy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -.4,
            ),
          ),
        ),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: SplyzoReferenceColors.orange,
            padding: const EdgeInsets.only(left: 4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                action,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_rounded, size: 17),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.message, {required this.icon});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    height: 105,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: SplyzoReferenceColors.field,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: SplyzoReferenceColors.border),
    ),
    child: Row(
      children: [
        Icon(icon, color: SplyzoReferenceColors.navy),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: SplyzoReferenceColors.secondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard(this.supplier);
  final Data supplier;

  @override
  Widget build(BuildContext context) {
    final name = field(supplier, 'displayName', 'Approved supplier');
    return SizedBox(
      width: 176,
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: SplyzoReferenceColors.border),
        ),
        child: InkWell(
          onTap: () => push(
            context,
            CatalogPage(supplier: field(supplier, 'id'), supplierName: name),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  SizedBox(
                    height: 78,
                    width: double.infinity,
                    child: Image.asset(
                      'assets/images/construction_engineer.jpg',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                  Positioned(
                    right: 6,
                    top: 5,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => push(context, const WishlistPage()),
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(
                            Icons.favorite_border_rounded,
                            size: 19,
                            color: SplyzoReferenceColors.navy,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: SplyzoReferenceColors.navy,
                    fontSize: 13,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 7),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Verified supplier',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          color: SplyzoReferenceColors.secondary,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF079D62),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Text(
                        'View',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierDirectory extends StatelessWidget {
  const _SupplierDirectory();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nearby Suppliers')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: const [
        Text(
          'Browse verified supplier storefronts and available materials.',
          style: TextStyle(color: SplyzoReferenceColors.secondary),
        ),
        SizedBox(height: 16),
        SupplierStrip(),
      ],
    ),
  );
}

class _Categories extends StatelessWidget {
  const _Categories({required this.categories, required this.loading});
  final List<Data> categories;
  final bool loading;

  static const _samples = [
    ('Cement', 'cement', Color(0xFFFFF8EA)),
    ('Bricks', 'bricks', Color(0xFFFFF0ED)),
    ('Steel', 'steel', Color(0xFFEDF5FF)),
    ('Sand', 'sand', Color(0xFFFFF2E8)),
    ('Paint', 'paint', Color(0xFFE9F5FD)),
    ('Electrical', 'electrical', Color(0xFFFFF7EA)),
    ('Plumbing', 'pipes', Color(0xFFECF5FF)),
    ('Tiles', 'concrete', Color(0xFFF9EBF6)),
  ];

  Data? _matched(String name) {
    for (final c in categories) {
      final n = '${field(c, 'name')} ${field(c, 'slug')}'.toLowerCase();
      if (name == 'Bricks' && (n.contains('brick') || n.contains('block'))) {
        return c;
      }
      if (name == 'Tiles' && n.contains('tile')) return c;
      if (name == 'Plumbing' && (n.contains('plumb') || n.contains('pipe'))) {
        return c;
      }
      if (n.contains(name.toLowerCase())) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _samples.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: .90,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final (name, asset, background) = _samples[index];
        final matched = _matched(name);
        return Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Colors.white, width: 1.6),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('reference-category-$name'),
            onTap: () => push(
              context,
              CatalogPage(
                category: matched == null ? null : field(matched, 'id'),
                search: matched == null ? name : null,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(5, 6, 5, 0),
                    child: Image.asset(
                      'assets/images/categories/$asset.webp',
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    name,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: SplyzoReferenceColors.navy,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DealCard extends StatelessWidget {
  const _DealCard(this.product);
  final Data product;
  @override
  Widget build(BuildContext context) {
    final name = field(product, 'name', 'Material');
    final lower = name.toLowerCase();
    final image = lower.contains('cement')
        ? 'ultratech_cement.jpg'
        : lower.contains('brick')
        ? 'red_bricks.jpg'
        : lower.contains('steel') || lower.contains('tmt')
        ? 'tmt_steel_bars.jpg'
        : lower.contains('sand')
        ? 'sand_aggregates.jpg'
        : 'construction_hero_banner.jpg';
    return SizedBox(
      width: 120,
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: SplyzoReferenceColors.border),
        ),
        child: InkWell(
          onTap: () => push(context, ProductPage(product)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(5, 5, 5, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: Image.asset(
                      'assets/images/$image',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: SplyzoReferenceColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 3, 6, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        product['fromPrice'] == null
                            ? 'View price'
                            : price(product['fromPrice']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SplyzoReferenceColors.navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: SplyzoReferenceColors.orange,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 5,
                      ),
                      child: const Text(
                        'Add +',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
