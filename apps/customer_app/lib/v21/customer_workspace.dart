import 'package:flutter/material.dart';
import 'customer_api.dart';
import 'customer_design.dart';
import 'customer_checkout.dart';
import 'customer_catalog.dart';
import 'customer_orders.dart';
import 'customer_rfq.dart';
export 'customer_rfq.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext c) {
    final s = CustomerScope.of(c);
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Text('Built around you.', style: Theme.of(c).textTheme.headlineLarge),
        const SizedBox(height: 22),
        Panel(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: accent.withValues(alpha: .12),
                child: const Icon(
                  Icons.person_outline,
                  color: accent,
                  size: 30,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.signedIn
                          ? field(s.user!, 'displayName', 'Your account')
                          : 'Welcome to Splyzo',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      s.signedIn
                          ? 'Your materials. Your projects.'
                          : 'A better way to build.',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!s.signedIn) ...[
          const SizedBox(height: 15),
          ActionButton('Sign in securely', s.signIn),
        ],
        const Section('Your workspace'),
        Panel(
          padding: 6,
          child: Column(
            children: [
              _tile(
                c,
                Icons.location_on_outlined,
                'Delivery addresses',
                const AddressesPage(),
              ),
              _tile(
                c,
                Icons.business_outlined,
                'Projects & construction sites',
                const ProjectsPage(),
              ),
              _tile(
                c,
                Icons.request_quote_outlined,
                'Bulk quotations',
                const RfqsPage(),
              ),
              _tile(
                c,
                Icons.favorite_border,
                'Saved supplier offers',
                const WishlistPage(),
              ),
              _tile(
                c,
                Icons.notifications_none,
                'Notifications',
                const NotificationsPage(),
              ),
            ],
          ),
        ),
        const Section('Here to help'),
        Panel(
          padding: 6,
          child: Column(
            children: [
              _tile(
                c,
                Icons.support_agent,
                'Help & support',
                const SupportPage(),
              ),
              _tile(
                c,
                Icons.policy_outlined,
                'Return & refund policy',
                const ContentPage(
                  'return-refund-policy',
                  'Return & refund policy',
                ),
              ),
              _tile(
                c,
                Icons.privacy_tip_outlined,
                'Privacy policy',
                const ContentPage('privacy-policy', 'Privacy policy'),
              ),
            ],
          ),
        ),
        if (s.signedIn) ...[
          const SizedBox(height: 22),
          ActionButton('Sign out', () async {
            if (await confirm(
              c,
              'Sign out?',
              'Your saved orders and sites remain securely in your account.',
            )) {
              await s.signOut();
            }
          }, tonal: true),
        ],
        const SizedBox(height: 25),
        const Text(
          'SPLYZO · MATERIALS FOR WHAT’S NEXT',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1),
        ),
      ],
    );
  }

  Widget _tile(BuildContext c, IconData icon, String text, Widget page) =>
      ListTile(
        leading: Icon(icon, color: ink),
        title: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.chevron_right, size: 19),
        onTap: () => push(c, page),
      );
}

class AddressesPage extends StatelessWidget {
  const AddressesPage({super.key});
  @override
  Widget build(BuildContext c) {
    final s = CustomerScope.of(c);
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery addresses')),
      body: SignedIn(
        child: RemotePage<List<Data>>(
          load: s.api.addresses,
          builder: (list, reload) => ListView(
            padding: const EdgeInsets.all(22),
            children: [
              const Text(
                'Deliver to the right place.',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              if (list.isEmpty)
                const EmptyState(
                  'Where are you building?',
                  'Save an address to check supplier coverage and delivery.',
                ),
              ...list.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                field(a, 'label'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            if (a['isDefault'] == true)
                              const StatusPill('DEFAULT'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(addressText(a)),
                        Text(
                          field(a, 'phoneE164'),
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ActionButton(
                              s.address?['id'] == a['id']
                                  ? 'Selected'
                                  : 'Deliver here',
                              () async {
                                s.chooseAddress(a);
                                notice(c, 'Delivery site selected');
                              },
                            ),
                            ActionButton('Edit', () async {
                              await Navigator.push(
                                c,
                                MaterialPageRoute(
                                  builder: (_) => AddressEditor(address: a),
                                ),
                              );
                              reload();
                            }, tonal: true),
                            IconButton(
                              tooltip: 'Delete address',
                              onPressed: () async {
                                if (!await confirm(
                                  c,
                                  'Delete this address?',
                                  'Existing orders retain their delivery details.',
                                )) {
                                  return;
                                }
                                try {
                                  await s.api.call(
                                    '/api/v2/me/addresses/${a['id']}',
                                    method: 'DELETE',
                                  );
                                  if (s.address?['id'] == a['id']) {
                                    s.chooseAddress(null);
                                  }
                                  reload();
                                } catch (e) {
                                  if (c.mounted) {
                                    notice(
                                      c,
                                      e is CustomerProblem
                                          ? e.message
                                          : 'Unable to delete address.',
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ActionButton('Add a delivery address', () async {
                await Navigator.push(
                  c,
                  MaterialPageRoute(builder: (_) => const AddressEditor()),
                );
                reload();
              }, icon: Icons.add),
            ],
          ),
        ),
      ),
    );
  }
}

String indianMobileDigits(String input) {
  final compact = input.replaceAll(RegExp(r'[\s()-]'), '');
  return compact.replaceFirst(RegExp(r'^(?:\+91|91|0)(?=\d{10}$)'), '');
}

class AddressEditor extends StatefulWidget {
  const AddressEditor({super.key, this.address});
  final Data? address;
  @override
  State<AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends State<AddressEditor> {
  final form = GlobalKey<FormState>();
  final controls = <String, TextEditingController>{};
  String? city;
  bool defaultAddress = false;
  @override
  void initState() {
    super.initState();
    for (final k in [
      'label',
      'recipientName',
      'phoneE164',
      'line1',
      'line2',
      'locality',
      'postalCode',
    ]) {
      final value = field(widget.address ?? {}, k);
      controls[k] = TextEditingController(
          text: k == 'phoneE164'
              ? value.replaceFirst(RegExp(r'^\+91(?=\d{10}$)'), '')
              : value);
    }
    city = widget.address?['cityId']?.toString();
    defaultAddress = widget.address?['isDefault'] == true;
  }

  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final s = CustomerScope.of(c);
    return RemotePage<List<Data>>(
      title: widget.address == null ? 'New delivery address' : 'Edit address',
      load: () async => rows(
        await s.api.call('/api/v2/delivery/cities', authenticated: false),
      ),
      builder: (cities, reload) => Form(
        key: form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const Text(
              'Where should we deliver?',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text('Add the site address and a contact for the delivery.',
                style: TextStyle(color: muted)),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: cities.any((e) => e['id'] == city) ? city : null,
              isExpanded: true,
              decoration:
                  const InputDecoration(label: RequiredLabel('Delivery city')),
              items: cities
                  .map(
                    (a) => DropdownMenuItem(
                      value: field(a, 'id'),
                      child: Text(field(a, 'name')),
                    ),
                  )
                  .toList(),
              onChanged: (v) => city = v,
              validator: (v) =>
                  v == null ? 'Choose an active delivery city' : null,
            ),
            if (cities.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Delivery is not available in any city yet. Please contact support.',
                ),
              ),
            const SizedBox(height: 14),
            ...controls.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextFormField(
                  controller: e.value,
                  textInputAction: e.key == 'postalCode'
                      ? TextInputAction.done
                      : TextInputAction.next,
                  textCapitalization:
                      const ['phoneE164', 'postalCode'].contains(e.key)
                          ? TextCapitalization.none
                          : TextCapitalization.words,
                  keyboardType: e.key == 'postalCode'
                      ? TextInputType.number
                      : e.key == 'phoneE164'
                          ? TextInputType.phone
                          : TextInputType.streetAddress,
                  decoration: InputDecoration(
                    label: e.key == 'line2'
                        ? const Text('Landmark (optional)')
                        : RequiredLabel(const {
                            'label': 'Address label',
                            'recipientName': 'Recipient name',
                            'phoneE164': 'Mobile number',
                            'line1': 'Building, plot or street',
                            'locality': 'Area or locality',
                            'postalCode': 'PIN code',
                          }[e.key]!),
                    prefixText: e.key == 'phoneE164' ? '+91  ' : null,
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    hintText: const {
                      'label': 'e.g. New home',
                      'phoneE164': '10-digit number',
                      'postalCode': '6-digit PIN code',
                    }[e.key],
                  ),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (e.key == 'line2') return null;
                    if (v.isEmpty) return 'This field is required';
                    if (e.key == 'postalCode' &&
                        !RegExp(r'^\d{6}$').hasMatch(v)) {
                      return 'Enter a 6-digit PIN code';
                    }
                    if (e.key == 'phoneE164' &&
                        !RegExp(r'^[6-9]\d{9}$')
                            .hasMatch(indianMobileDigits(v))) {
                      return 'Enter a valid 10-digit mobile number';
                    }
                    return null;
                  },
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Default delivery address'),
              value: defaultAddress,
              onChanged: (v) => setState(() => defaultAddress = v),
            ),
            const SizedBox(height: 14),
            ActionButton('Save address', () async {
              if (!form.currentState!.validate()) return;
              final body = <String, dynamic>{
                'cityId': city,
                'isDefault': defaultAddress,
                for (final e in controls.entries)
                  if (e.key != 'phoneE164' && e.value.text.trim().isNotEmpty)
                    e.key: e.value.text.trim(),
                'phoneE164':
                    '+91${indianMobileDigits(controls['phoneE164']!.text)}',
              };
              final id = widget.address?['id'];
              final result = object(
                await s.api.call(
                  '/api/v2/me/addresses${id == null ? '' : '/$id'}',
                  method: id == null ? 'POST' : 'PATCH',
                  body: body,
                ),
              );
              s.chooseAddress(result);
              if (c.mounted) Navigator.pop(c);
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class WishlistPage extends StatelessWidget {
  const WishlistPage({super.key});
  @override
  Widget build(BuildContext c) {
    final s = CustomerScope.of(c);
    return Scaffold(
      appBar: AppBar(title: const Text('Saved supplier offers')),
      body: SignedIn(
        child: RemotePage<List<Data>>(
          load: () async => rows(await s.api.call('/api/v2/me/wishlist')),
          builder: (list, reload) => ListView(
            padding: const EdgeInsets.all(22),
            children: [
              if (list.isEmpty)
                const EmptyState(
                  'Save a little inspiration',
                  'Tap the heart on a supplier offer to find it here.',
                ),
              ...list.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          field(p, 'productName'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          field(p, 'supplierName'),
                          style: const TextStyle(color: muted),
                        ),
                        const SizedBox(height: 10),
                        Text('${price(p['unitPrice'])} / ${p['unitCode']}'),
                        const SizedBox(height: 14),
                        ActionButton(
                          p['available'] == true
                              ? 'Review latest supplier offers'
                              : 'Check availability',
                          () async => push(
                            c,
                            ProductPage({
                              'id': p['productId'],
                              'name': p['productName'],
                            }),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            try {
                              await s.api.call(
                                '/api/v2/me/wishlist/${p['listingId']}',
                                method: 'DELETE',
                              );
                              reload();
                            } catch (e) {
                              if (c.mounted) {
                                notice(c, 'Unable to remove saved offer.');
                              }
                            }
                          },
                          child: const Text('Remove saved offer'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String? cursor;
  final items = <Data>[];
  @override
  Widget build(BuildContext c) {
    final s = CustomerScope.of(c);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SignedIn(
        child: RemotePage<Data>(
          load: () async {
            final p = object(
              await s.api.call(
                '/api/v2/me/notifications',
                query: {if (cursor != null) 'cursor': cursor!},
              ),
            );
            for (final i in rows(p)) {
              if (!items.any((x) => x['id'] == i['id'])) items.add(i);
            }
            return p;
          },
          builder: (p, reload) => ListView(
            padding: const EdgeInsets.all(22),
            children: [
              if (items.isEmpty)
                const EmptyState(
                  'You’re all caught up',
                  'Order and supplier updates will appear here.',
                ),
              ...items.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          field(n, 'title'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          field(n, 'body'),
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        ActionButton(
                          n['readAt'] == null ? 'Mark as read' : 'Read',
                          n['readAt'] != null
                              ? null
                              : () async {
                                  await s.api.call(
                                    '/api/v2/me/notifications/${n['id']}/read',
                                    method: 'POST',
                                    body: {},
                                  );
                                  setState(
                                    () => n['readAt'] =
                                        DateTime.now().toIso8601String(),
                                  );
                                },
                          tonal: true,
                        ),
                        if (object(n['payload'])['orderId'] != null)
                          TextButton(
                            onPressed: () => push(
                              c,
                              OrderPage(field(object(n['payload']), 'orderId')),
                            ),
                            child: const Text('View order'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (p['nextCursor'] != null)
                OutlinedButton(
                  onPressed: () {
                    cursor = field(p, 'nextCursor');
                    reload();
                  },
                  child: const Text('Load earlier updates'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SupportPage extends StatelessWidget {
  const SupportPage({super.key, this.orderId});
  final String? orderId;
  @override
  Widget build(BuildContext c) {
    final s = CustomerScope.of(c);
    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      body: SignedIn(
        child: RemotePage<List<Data>>(
          load: () async => rows(await s.api.call('/api/v2/support/cases')),
          builder: (list, reload) => ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Text(
                'Let’s sort it out.',
                style: Theme.of(c).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Send a message to our support team and keep every update together.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 22),
              ActionButton('Create a support request', () async {
                await Navigator.push(
                  c,
                  MaterialPageRoute(
                    builder: (_) => NewSupportPage(orderId: orderId),
                  ),
                );
                reload();
              }, icon: Icons.add),
              const Section('Your conversations'),
              if (list.isEmpty)
                const EmptyState(
                  'No support requests',
                  'We’re here whenever you need a hand.',
                ),
              ...list
                  .where((p) => orderId == null || p['orderId'] == orderId)
                  .map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Panel(
                        padding: 5,
                        child: ListTile(
                          title: Text(field(p, 'subject')),
                          subtitle: Text(
                            '${p['publicNumber']} · ${label(p['status'])}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              push(c, ConversationPage(field(p, 'id'))),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class NewSupportPage extends StatefulWidget {
  const NewSupportPage({super.key, this.orderId});
  final String? orderId;
  @override
  State<NewSupportPage> createState() => _NewSupportPageState();
}

class _NewSupportPageState extends State<NewSupportPage> {
  final subject = TextEditingController(), message = TextEditingController();
  final key = requestKey();
  @override
  void dispose() {
    subject.dispose();
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final api = CustomerScope.of(c).api;
    return Scaffold(
      appBar: AppBar(title: const Text('New support request')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          TextField(
            controller: subject,
            maxLength: 250,
            decoration: const InputDecoration(
              label: RequiredLabel('Subject (8+ characters)'),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: message,
            maxLines: 6,
            maxLength: 3000,
            decoration: const InputDecoration(
              label: RequiredLabel('Tell us how we can help (8+ characters)'),
            ),
          ),
          const SizedBox(height: 20),
          ActionButton('Send request', () async {
            if (subject.text.trim().length < 8 ||
                message.text.trim().length < 8) {
              throw const CustomerProblem(
                'Please add a subject and message of at least 8 characters each.',
              );
            }
            final result = object(
              await api.call(
                '/api/v2/support/cases',
                method: 'POST',
                key: key,
                body: {
                  if (widget.orderId != null) 'orderId': widget.orderId,
                  'subject': subject.text.trim(),
                  'message': message.text.trim(),
                },
              ),
            );
            if (c.mounted) {
              Navigator.of(c).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ConversationPage(field(result, 'id')),
                ),
              );
            }
          }),
        ],
      ),
    );
  }
}

class ConversationPage extends StatefulWidget {
  const ConversationPage(this.id, {super.key});
  final String id;
  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final text = TextEditingController();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final s = CustomerScope.of(c);
    return RemotePage<Data>(
      title: 'Support conversation',
      load: () async =>
          object(await s.api.call('/api/v2/support/cases/${widget.id}')),
      builder: (p, reload) => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text(field(p, 'subject'), style: Theme.of(c).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(field(p, 'status')),
          ),
          const SizedBox(height: 20),
          ...rows(p['messages']).map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Panel(
                color: m['authorId'] == s.user?['id']
                    ? const Color(0xFFEAF1EC)
                    : Colors.white,
                child: Text(field(m, 'body')),
              ),
            ),
          ),
          if (p['status'] != 'CLOSED') ...[
            const SizedBox(height: 15),
            TextField(
              controller: text,
              maxLines: 3,
              maxLength: 3000,
              decoration:
                  const InputDecoration(label: RequiredLabel('Your reply')),
            ),
            const SizedBox(height: 12),
            ActionButton('Send reply', () async {
              if (text.text.trim().length < 2) {
                throw const CustomerProblem('Enter a message.');
              }
              await s.api.call(
                '/api/v2/support/cases/${widget.id}/messages',
                method: 'POST',
                body: {'message': text.text.trim()},
              );
              text.clear();
              reload();
            }),
          ],
        ],
      ),
    );
  }
}

class ContentPage extends StatelessWidget {
  const ContentPage(this.slug, this.title, {super.key});
  final String slug, title;
  @override
  Widget build(BuildContext c) {
    final api = CustomerScope.of(c).api;
    return RemotePage<Data>(
      title: title,
      load: () async =>
          object(await api.call('/api/v2/content/$slug', authenticated: false)),
      builder: (p, reload) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SelectableText(
            field(p, 'title', title),
            style: Theme.of(c).textTheme.headlineSmall,
          ),
          const SizedBox(height: 18),
          SelectableText(field(p, 'body'), style: const TextStyle(height: 1.8)),
        ],
      ),
    );
  }
}

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});
  @override
  Widget build(BuildContext c) {
    final s = CustomerScope.of(c);
    return Scaffold(
      appBar: AppBar(title: const Text('Projects & sites')),
      body: SignedIn(
        child: RemotePage<Data>(
          load: () async => {
            'projects': await s.api.call('/api/v2/me/projects'),
            'sites': await s.api.call('/api/v2/me/sites'),
          },
          builder: (data, reload) => ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Text(
                'Every site, organised.',
                style: Theme.of(c).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              ActionButton(
                'Create a project',
                () async {
                  final name = await ask(c, 'New project', 'Project name');
                  if (name == null) return;
                  await s.api.call(
                    '/api/v2/me/projects',
                    method: 'POST',
                    body: {'name': name},
                  );
                  reload();
                },
                icon: Icons.add,
                tonal: true,
              ),
              const Section('Projects'),
              ...rows(data['projects']).map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            field(p, 'name'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        StatusPill(field(p, 'status')),
                      ],
                    ),
                  ),
                ),
              ),
              const Section('Construction sites'),
              if (rows(data['sites']).isEmpty)
                const EmptyState(
                  'Bring your sites together',
                  'Create a site linked to a delivery address and project.',
                ),
              ...rows(data['sites']).map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Row(
                      children: [
                        const Icon(Icons.apartment_outlined, color: accent),
                        const SizedBox(width: 12),
                        Expanded(child: Text(field(p, 'name'))),
                        StatusPill(p['active'] == true ? 'ACTIVE' : 'ARCHIVED'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              ActionButton('Add a construction site', () async {
                await Navigator.push(
                  c,
                  MaterialPageRoute(
                    builder: (_) =>
                        NewSitePage(projects: rows(data['projects'])),
                  ),
                );
                reload();
              }, icon: Icons.add),
            ],
          ),
        ),
      ),
    );
  }
}

class NewSitePage extends StatefulWidget {
  const NewSitePage({super.key, required this.projects});
  final List<Data> projects;
  @override
  State<NewSitePage> createState() => _NewSitePageState();
}

class _NewSitePageState extends State<NewSitePage> {
  final name = TextEditingController(), notes = TextEditingController();
  String? address, project;
  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final api = CustomerScope.of(c).api;
    return RemotePage<List<Data>>(
      title: 'New construction site',
      load: api.addresses,
      builder: (list, reload) => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          TextField(
            controller: name,
            maxLength: 200,
            decoration:
                const InputDecoration(label: RequiredLabel('Site name')),
          ),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration:
                const InputDecoration(label: RequiredLabel('Delivery address')),
            items: list
                .map(
                  (a) => DropdownMenuItem(
                    value: field(a, 'id'),
                    child: Text(field(a, 'label')),
                  ),
                )
                .toList(),
            onChanged: (v) => address = v,
          ),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Project (optional)'),
            items: widget.projects
                .where((p) => p['status'] == 'ACTIVE')
                .map(
                  (p) => DropdownMenuItem(
                    value: field(p, 'id'),
                    child: Text(field(p, 'name')),
                  ),
                )
                .toList(),
            onChanged: (v) => project = v,
          ),
          const SizedBox(height: 15),
          TextField(
            controller: notes,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Vehicle access / unloading notes (optional)',
            ),
          ),
          const SizedBox(height: 20),
          ActionButton('Save site', () async {
            if (name.text.trim().isEmpty || address == null) {
              throw const CustomerProblem(
                'Enter a site name and choose an address.',
              );
            }
            await api.call(
              '/api/v2/me/sites',
              method: 'POST',
              body: {
                'name': name.text.trim(),
                'addressId': address,
                if (project != null) 'projectId': project,
                if (notes.text.trim().isNotEmpty)
                  'accessNotes': notes.text.trim(),
              },
            );
            if (c.mounted) Navigator.pop(c);
          }),
        ],
      ),
    );
  }
}
