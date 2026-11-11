import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../config/buildto_theme.dart';
import '../widgets/ui/snack.dart';
import 'package:kraveo_ui/kraveo_ui.dart' show SupportCenter;
import '../services/support_api.dart';

/// Screen 14 — Help & Support
/// Customer assistance options, site delivery hotline, and construction FAQs accordion.
class SupportHelpScreen extends StatefulWidget {
  const SupportHelpScreen({super.key});

  @override
  State<SupportHelpScreen> createState() => _SupportHelpScreenState();
}

class _SupportHelpScreenState extends State<SupportHelpScreen> {
  final List<Map<String, String>> _faqs = [
    {
      'q': 'How is bulk cement and steel unloaded at the site?',
      'a': 'Suppliers dispatch heavy flatbed trucks with dedicated loaders. Drivers call 30 minutes prior to arrival to confirm gate clearance and unloading access.',
    },
    {
      'q': 'Can I schedule delivery for a specific date and time?',
      'a': 'Yes, during checkout you can enter site unloading instructions or call our logistics desk to schedule delivery to match your concrete pouring or slab casting timetable.',
    },
    {
      'q': 'What is the return policy for torn bags or damaged bricks?',
      'a': 'Inspect materials upon delivery. If bags are wet or torn or bricks are damaged, mention it on the delivery challan. Our driver will issue an instant replacement or refund.',
    },
    {
      'q': 'How do I get a GST input tax credit invoice for my firm?',
      'a': 'Add your GSTIN under Profile > Company / Tax Information. Every order automatically generates a tax invoice with B2B input tax credit eligibility.',
    },
    {
      'q': 'Are steel bars and cement BIS certified?',
      'a': 'Check the supplier listing and ask for the relevant BIS certification and manufacturer test certificates before ordering.',
    },
  ];

  final Set<int> _expandedIndices = {0};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SplyzoColors.surfaceLight,
      appBar: AppBar(
        backgroundColor: SplyzoColors.bgWhite,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: SplyzoColors.primaryNavy),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Help & Support',
          style: TextStyle(
            color: SplyzoColors.primaryNavy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Demonstration Mode Banner
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SplyzoColors.infoBg,
                borderRadius: BorderRadius.circular(SplyzoRadius.md),
                border: Border.all(color: SplyzoColors.infoBlue.withValues(alpha: 0.25)),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.info, size: 18, color: SplyzoColors.infoBlue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Demonstration Mode: Support channels demonstrate contractor workflows. In active production, live chat connects directly to regional depot dispatchers.',
                      style: TextStyle(
                        fontSize: 11,
                        color: SplyzoColors.infoBlue,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Quick Support Channels
            const Text(
              'Contact Site Support',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: SplyzoColors.textDark,
              ),
            ),
            const SizedBox(height: 12),

            _buildContactCard(
              icon: LucideIcons.messageSquare,
              title: 'Help and requests',
              subtitle: 'Contact the Splyzo support team',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SupportCenter(call: SupportApi.call),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // FAQs Section
            const Text(
              'Frequently Asked Questions',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: SplyzoColors.textDark,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: SplyzoColors.bgWhite,
                borderRadius: BorderRadius.circular(SplyzoRadius.md),
                border: Border.all(color: SplyzoColors.cardBorder),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _faqs.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: SplyzoColors.cardBorder),
                itemBuilder: (context, index) {
                  final faq = _faqs[index];
                  final isExpanded = _expandedIndices.contains(index);

                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedIndices.remove(index);
                        } else {
                          _expandedIndices.add(index);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  faq['q']!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isExpanded ? FontWeight.bold : FontWeight.w600,
                                    color: isExpanded ? SplyzoColors.primaryNavy : SplyzoColors.textDark,
                                  ),
                                ),
                              ),
                              Icon(
                                isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                                size: 16,
                                color: SplyzoColors.textMuted,
                              ),
                            ],
                          ),
                          if (isExpanded) ...[
                            const SizedBox(height: 8),
                            Text(
                              faq['a']!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: SplyzoColors.textMuted,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // Return policy link
            Center(
              child: TextButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Return & Refund Policy'),
                      content: const Text(
                        'Damaged materials noted on delivery challans during unloading are inspected for replacement or credit note. Cancellations prior to yard dispatch are refunded via original payment mode within standard banking cycles (3-5 business days). In demo mode, no real money was charged.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text(
                  'View Return & Refund Policy',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: SplyzoColors.primaryNavy,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SplyzoRadius.md),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SplyzoColors.bgWhite,
          borderRadius: BorderRadius.circular(SplyzoRadius.md),
          border: Border.all(color: SplyzoColors.cardBorder),
          boxShadow: SplyzoShadows.card,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: SplyzoColors.primaryNavy.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: SplyzoColors.primaryNavy, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: SplyzoColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: SplyzoColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
