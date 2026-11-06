import 'package:flutter/material.dart';

import '../config/buildto_theme.dart';
import '../models/delivery_address.dart';

/// Local-only delivery site picker for the customer client APK.
/// Never contacts BuildTo APIs or persists private addresses.
abstract final class ClientPreviewAddressStore {
  static DeliveryAddress _make(
    String id,
    String label,
    String house,
    String street,
    String locality,
    String pin,
  ) =>
      DeliveryAddress({
        'id': id,
        'customerId': 'client-preview',
        'isDefault': id == 'demo-site-1',
        'label': label,
        'houseNumber': house,
        'street': street,
        'locality': locality,
        'cityId': 'demo-hyderabad',
        'city': {'name': 'Hyderabad'},
        'pinCode': pin,
        'country': 'IN',
        'landmark': '',
        'instructions': 'Call before unloading',
      });

  static final List<DeliveryAddress> addresses = [
    _make('demo-site-1', 'Construction site', 'Plot 42', 'Miyapur Main Road',
        'Miyapur', '500049'),
    _make('demo-site-2', 'Office', 'Unit 301', 'Business Park Road',
        'Gachibowli', '500032'),
  ];

  static final ValueNotifier<DeliveryAddress> selected =
      ValueNotifier<DeliveryAddress>(addresses.first);

  static void choose(DeliveryAddress address) => selected.value = address;
}

class ClientPreviewAddressesScreen extends StatefulWidget {
  const ClientPreviewAddressesScreen({super.key});

  @override
  State<ClientPreviewAddressesScreen> createState() =>
      _ClientPreviewAddressesScreenState();
}

class _ClientPreviewAddressesScreenState
    extends State<ClientPreviewAddressesScreen> {
  Future<void> _addSite() async {
    final label = TextEditingController(text: 'New construction site');
    final street = TextEditingController();
    final area = TextEditingController();
    final pin = TextEditingController();
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Add delivery site'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: 'Site name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: street,
                  decoration:
                      const InputDecoration(labelText: 'Building / Street'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: area,
                  decoration: const InputDecoration(labelText: 'Area'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pin,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration:
                      const InputDecoration(labelText: 'Hyderabad PIN code'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (street.text.trim().isEmpty ||
                    area.text.trim().isEmpty ||
                    !RegExp(r'^[1-9][0-9]{5}$').hasMatch(pin.text.trim())) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Enter street, area and a valid 6-digit PIN.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save demo address'),
            ),
          ],
        ),
      );
      if (result != true || !mounted) return;
      final item = DeliveryAddress({
        'id': 'demo-site-${ClientPreviewAddressStore.addresses.length + 1}',
        'customerId': 'client-preview',
        'isDefault': false,
        'label': label.text.trim().isEmpty ? 'Site address' : label.text.trim(),
        'houseNumber': street.text.trim(),
        'street': street.text.trim(),
        'locality': area.text.trim(),
        'cityId': 'demo-hyderabad',
        'city': {'name': 'Hyderabad'},
        'pinCode': pin.text.trim(),
        'country': 'IN',
        'landmark': '',
        'instructions': '',
      });
      setState(() => ClientPreviewAddressStore.addresses.add(item));
      ClientPreviewAddressStore.choose(item);
    } finally {
      label.dispose();
      street.dispose();
      area.dispose();
      pin.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: BuildtoColors.surfaceLight,
        appBar: AppBar(
          title: const Text('Delivery sites'),
          backgroundColor: Colors.white,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4DF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_user_outlined,
                        color: BuildtoColors.primaryNavy),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Client preview · These are example sites; no address is uploaded.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: BuildtoColors.primaryNavy,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text('Choose your delivery site',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('Material delivery right to the site gate.'),
              const SizedBox(height: 16),
              for (final address in ClientPreviewAddressStore.addresses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ValueListenableBuilder<DeliveryAddress>(
                    valueListenable: ClientPreviewAddressStore.selected,
                    builder: (context, selected, _) {
                      final chosen = selected.id == address.id;
                      return Card(
                        color: Colors.white,
                        elevation: chosen ? 1.5 : 0,
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(10),
                          leading: CircleAvatar(
                            backgroundColor: chosen
                                ? BuildtoColors.primaryNavy
                                : BuildtoColors.surfaceLight,
                            child: Icon(
                              Icons.location_on_outlined,
                              color: chosen
                                  ? Colors.white
                                  : BuildtoColors.primaryNavy,
                            ),
                          ),
                          title: Text(address.label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800)),
                          subtitle: Text(address.formatted),
                          trailing: chosen
                              ? const Icon(Icons.check_circle,
                                  color: Color(0xFF07805A))
                              : const Icon(Icons.chevron_right),
                          onTap: () {
                            ClientPreviewAddressStore.choose(address);
                            Navigator.pop(context, address);
                          },
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _addSite,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add another delivery site'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sample addresses and delivery coverage are illustrative. '
                'No live order or payment is submitted.',
                style: TextStyle(
                    fontSize: 12, color: BuildtoColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}
