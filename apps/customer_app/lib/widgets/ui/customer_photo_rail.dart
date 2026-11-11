import 'package:flutter/material.dart';

import '../../config/buildto_theme.dart';

/// Photo-led shortcuts shown only in the offline customer client showroom.
/// Images are bundled locally, so client walkthroughs never need a connection.
class CustomerPhotoRail extends StatelessWidget {
  const CustomerPhotoRail({super.key, required this.onCategorySelected});

  final ValueChanged<String> onCategorySelected;

  static const _categories = <({String title, String subtitle, String image})>[
    (
      title: 'Cement & Concrete',
      subtitle: 'Premium cement',
      image: 'assets/images/ultratech_cement.jpg',
    ),
    (
      title: 'Steel & TMT Bars',
      subtitle: 'Strong foundations',
      image: 'assets/images/tmt_steel_bars.jpg',
    ),
    (
      title: 'Bricks & Blocks',
      subtitle: 'Built to last',
      image: 'assets/images/red_bricks.jpg',
    ),
    (
      title: 'Sand & Aggregates',
      subtitle: 'Ready for your site',
      image: 'assets/images/sand_aggregates.jpg',
    ),
  ];

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_outlined,
                    color: BuildtoColors.accentAmber, size: 21),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Shop by Material',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: BuildtoColors.primaryNavy,
                    ),
                  ),
                ),
                Text(
                  'CURATED FOR YOU',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: BuildtoColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 178,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = _categories[index];
                return Semantics(
                  button: true,
                  label: 'Explore ${item.title}',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onCategorySelected(item.title),
                    child: Ink(
                      width: 210,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: BuildtoColors.primaryNavy,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x16042B55),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              item.image,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const ColoredBox(
                                color: BuildtoColors.primaryNavy,
                                child: Center(
                                  child: Icon(Icons.construction,
                                      color: Colors.white, size: 38),
                                ),
                              ),
                            ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Color(0x8006192F),
                                    Color(0xE9002548),
                                  ],
                                  stops: [0.28, 0.65, 1.0],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 14,
                              right: 12,
                              bottom: 14,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.subtitle,
                                    style: const TextStyle(
                                      color: Color(0xFFFFD88D),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          maxLines: 2,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.arrow_outward_rounded,
                                        size: 20,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      );
}
