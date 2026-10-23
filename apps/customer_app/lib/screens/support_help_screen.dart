import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../config/buildto_theme.dart';
import '../widgets/ui/snack.dart';

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
      'a': 'All cement brands (OPC/PPC) and steel rebars (Fe 500D / 550D) sold on Buildto are 100% BIS certified with manufacturer test certificates provided upon request.',
    },
  ];

  final Set<int> _expandedIndices = {0};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BuildtoColors.surfaceLight,
      appBar: AppBar(
        backgroundColor: BuildtoColors.bgWhite,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: BuildtoColors.primaryNavy),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Help & Support',
          style: TextStyle(
            color: BuildtoColors.primaryNavy,
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
            // Quick Support Channels
            const Text(
              'Contact Site Support',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: BuildtoColors.textDark,
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildContactCard(
                    icon: LucideIcons.messageSquare,
                    title: 'Live Chat',
                    subtitle: 'Instant Site Help',
                    onTap: () {
                      showKSnack(context, 'Connecting to Buildto Site Support Representative...');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildContactCard(
                    icon: LucideIcons.phoneCall,
                    title: 'Call Us',
                    subtitle: '+91 98765 00123',
                    onTap: () {
                      showKSnack(context, 'Calling Buildto Dispatch Support Desk (+91 98765 00123)...');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildContactCard(
              icon: LucideIcons.mail,
              title: 'Email Dispatch Desk',
              subtitle: 'support@buildto.in (Responses within 2 hours)',
              onTap: () {
                showKSnack(context, 'Opening email to support@buildto.in');
              },
            ),
            const SizedBox(height: 24),

            // FAQs Section
            const Text(
              'Frequently Asked Questions',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: BuildtoColors.textDark,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: BuildtoColors.bgWhite,
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
                border: Border.all(color: BuildtoColors.cardBorder),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _faqs.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: BuildtoColors.cardBorder),
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
                                    color: isExpanded ? BuildtoColors.primaryNavy : BuildtoColors.textDark,
                                  ),
                                ),
                              ),
                              Icon(
                                isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                                size: 16,
                                color: BuildtoColors.textMuted,
                              ),
                            ],
                          ),
                          if (isExpanded) ...[
                            const SizedBox(height: 8),
                            Text(
                              faq['a']!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: BuildtoColors.textMuted,
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
                    color: BuildtoColors.primaryNavy,
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
      borderRadius: BorderRadius.circular(BuildtoRadius.md),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BuildtoColors.bgWhite,
          borderRadius: BorderRadius.circular(BuildtoRadius.md),
          border: Border.all(color: BuildtoColors.cardBorder),
          boxShadow: BuildtoShadows.card,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: BuildtoColors.primaryNavy.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: BuildtoColors.primaryNavy, size: 18),
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
                      color: BuildtoColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
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
