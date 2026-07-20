import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../platform/address_engine.dart';
import '../send_package/models/suggestions.m.dart';
import 'design_system/sender_design_system.dart';

class SenderSavedAddress {
  final String id;
  final String label;
  final String customLabel;
  final Map<String, dynamic> address;
  final String deliveryInstructions;
  final bool isDefaultPickup;
  final bool isDefaultDropoff;
  final int version;

  const SenderSavedAddress({
    required this.id,
    required this.label,
    required this.customLabel,
    required this.address,
    required this.deliveryInstructions,
    required this.isDefaultPickup,
    required this.isDefaultDropoff,
    required this.version,
  });

  factory SenderSavedAddress.fromMap(String id, Map<String, dynamic> data) {
    return SenderSavedAddress(
      id: id,
      label: AddressEngine.clean(data['label']).isEmpty
          ? 'other'
          : AddressEngine.clean(data['label']),
      customLabel: AddressEngine.clean(data['customLabel']),
      address: AddressEngine.normalize(
        components: data,
        addressId: id,
        placeId: data['placeId'],
        latitude: data['latitude'],
        longitude: data['longitude'],
        source: 'saved',
      ),
      deliveryInstructions: AddressEngine.clean(data['deliveryInstructions']),
      isDefaultPickup: data['isDefaultPickup'] == true,
      isDefaultDropoff: data['isDefaultDropoff'] == true,
      version: (data['version'] as num?)?.toInt() ?? 1,
    );
  }

  String get displayLabel => label == 'other' && customLabel.isNotEmpty
      ? customLabel
      : '${label[0].toUpperCase()}${label.substring(1)}';
  String get formattedAddress => AddressEngine.display(address);

  Suggestion toSuggestion() => Suggestion(
        placeId: AddressEngine.clean(address['placeId']).isEmpty
            ? id
            : AddressEngine.clean(address['placeId']),
        description: formattedAddress,
        mainText: AddressEngine.clean(address['addressLine1']),
        subText: AddressEngine.joinParts([
          address['city'],
          address['postcode'],
          address['country'],
        ]),
        lat: AddressEngine.toDouble(address['latitude']),
        lng: AddressEngine.toDouble(address['longitude']),
        components: address,
      );
}

abstract class SenderSavedAddressesRepository {
  Stream<List<SenderSavedAddress>> watch();
  Future<List<Suggestion>> search(String query);
  Future<void> save({
    String? addressId,
    required String label,
    required String customLabel,
    required Map<String, dynamic> address,
    required String deliveryInstructions,
    required bool isDefaultPickup,
    required bool isDefaultDropoff,
  });
  Future<void> delete(String addressId);
}

class EmptySenderSavedAddressesRepository
    implements SenderSavedAddressesRepository {
  const EmptySenderSavedAddressesRepository();
  @override
  Stream<List<SenderSavedAddress>> watch() => Stream.value(const []);
  @override
  Future<List<Suggestion>> search(String query) async => const [];
  @override
  Future<void> save(
          {String? addressId,
          required String label,
          required String customLabel,
          required Map<String, dynamic> address,
          required String deliveryInstructions,
          required bool isDefaultPickup,
          required bool isDefaultDropoff}) =>
      throw UnsupportedError('Saved addresses are unavailable.');
  @override
  Future<void> delete(String addressId) =>
      throw UnsupportedError('Saved addresses are unavailable.');
}

class FirebaseSenderSavedAddressesRepository
    implements SenderSavedAddressesRepository {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  FirebaseSenderSavedAddressesRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        functions = functions ?? FirebaseFunctions.instance;

  User? get _maybeUser => auth.currentUser;

  @override
  Stream<List<SenderSavedAddress>> watch() {
    final user = _maybeUser;
    if (user == null) return Stream.value(const <SenderSavedAddress>[]);
    return firestore
        .collection('users')
        .doc(user.uid)
        .collection('savedAddresses')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SenderSavedAddress.fromMap(doc.id, doc.data()))
            .toList(growable: false));
  }

  @override
  Future<List<Suggestion>> search(String query) async {
    if (query.trim().length < 3) return const [];
    final response = await functions
        .httpsCallable('searchFreeUkAddresses')
        .call({'query': query.trim()});
    final data = Map<String, dynamic>.from(response.data as Map);
    return (data['results'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => AddressEngine.suggestionFromBackend(
            Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  @override
  Future<void> save({
    String? addressId,
    required String label,
    required String customLabel,
    required Map<String, dynamic> address,
    required String deliveryInstructions,
    required bool isDefaultPickup,
    required bool isDefaultDropoff,
  }) async {
    if (_maybeUser == null) {
      throw StateError('Sign in to manage saved addresses.');
    }
    if (!AddressEngine.isValid(address)) {
      throw StateError('Complete address line 1, city, postcode and country.');
    }
    await functions.httpsCallable('saveSenderSavedAddress').call({
      if (addressId != null) 'addressId': addressId,
      'label': label,
      'customLabel': customLabel,
      'address': address,
      'deliveryInstructions': deliveryInstructions,
      'isDefaultPickup': isDefaultPickup,
      'isDefaultDropoff': isDefaultDropoff,
    });
  }

  @override
  Future<void> delete(String addressId) async {
    if (_maybeUser == null) {
      throw StateError('Sign in to manage saved addresses.');
    }
    await functions
        .httpsCallable('deleteSenderSavedAddress')
        .call({'addressId': addressId});
  }
}

class SenderSavedAddressesView extends StatelessWidget {
  final SenderSavedAddressesRepository? repository;
  const SenderSavedAddressesView({super.key, this.repository});

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? FirebaseSenderSavedAddressesRepository();
    return Scaffold(
      backgroundColor: _AddressColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Saved Addresses'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, repo),
        backgroundColor: _AddressColors.blue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add Address'),
      ),
      body: StreamBuilder<List<SenderSavedAddress>>(
        stream: repo.watch(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final permission = '${snapshot.error}'.contains('permission');
            return _AddressState(
              icon: permission ? Icons.lock_outline : Icons.cloud_off_outlined,
              title: permission
                  ? 'Saved addresses unavailable'
                  : 'Could not load addresses',
              body: permission
                  ? 'Sign in again to access your saved locations.'
                  : 'Check your connection and try again.',
            );
          }
          final addresses = snapshot.data ?? const [];
          if (addresses.isEmpty) {
            return const _AddressState(
              icon: Icons.location_on_outlined,
              title: 'No saved addresses yet',
              body:
                  'Save Home, Work or another location to make future bookings faster.',
            );
          }
          final pickup =
              addresses.where((item) => item.isDefaultPickup).firstOrNull;
          final dropoff =
              addresses.where((item) => item.isDefaultDropoff).firstOrNull;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              const Text('Your frequent locations, ready when you need them.',
                  style: TextStyle(color: _AddressColors.muted, height: 1.45)),
              if (pickup != null) ...[
                const _SectionLabel('Default pickup'),
                _AddressCard(address: pickup, repository: repo),
              ],
              if (dropoff != null) ...[
                const _SectionLabel('Default drop-off'),
                _AddressCard(address: dropoff, repository: repo),
              ],
              const _SectionLabel('All saved addresses'),
              ...addresses.map((address) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AddressCard(address: address, repository: repo),
                  )),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _openEditor(
      BuildContext context, SenderSavedAddressesRepository repository,
      [SenderSavedAddress? address]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SenderSavedAddressEditor(
        repository: repository,
        existing: address,
      ),
    ));
  }
}

class SenderSavedAddressEditor extends StatefulWidget {
  final SenderSavedAddressesRepository repository;
  final SenderSavedAddress? existing;
  const SenderSavedAddressEditor(
      {super.key, required this.repository, this.existing});
  @override
  State<SenderSavedAddressEditor> createState() =>
      _SenderSavedAddressEditorState();
}

class _SenderSavedAddressEditorState extends State<SenderSavedAddressEditor> {
  late String _label;
  late final TextEditingController _customLabel;
  late final TextEditingController _search;
  late final TextEditingController _line1;
  late final TextEditingController _line2;
  late final TextEditingController _city;
  late final TextEditingController _postcode;
  late final TextEditingController _country;
  late final TextEditingController _instructions;
  Map<String, dynamic> _selected = {};
  List<Suggestion> _suggestions = const [];
  bool _defaultPickup = false;
  bool _defaultDropoff = false;
  bool _searching = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _label = existing?.label ?? 'home';
    _selected = {...?existing?.address};
    _customLabel = TextEditingController(text: existing?.customLabel ?? '');
    _search = TextEditingController(text: existing?.formattedAddress ?? '');
    _line1 = TextEditingController(
        text: AddressEngine.clean(_selected['addressLine1']));
    _line2 = TextEditingController(
        text: AddressEngine.clean(_selected['addressLine2']));
    _city = TextEditingController(text: AddressEngine.clean(_selected['city']));
    _postcode =
        TextEditingController(text: AddressEngine.clean(_selected['postcode']));
    _country =
        TextEditingController(text: AddressEngine.clean(_selected['country']));
    _instructions =
        TextEditingController(text: existing?.deliveryInstructions ?? '');
    _defaultPickup = existing?.isDefaultPickup ?? false;
    _defaultDropoff = existing?.isDefaultDropoff ?? false;
  }

  @override
  void dispose() {
    for (final controller in [
      _customLabel,
      _search,
      _line1,
      _line2,
      _city,
      _postcode,
      _country,
      _instructions
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _lookup(String value) async {
    if (value.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final values = await widget.repository.search(value);
      if (mounted) setState(() => _suggestions = values);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Address search is unavailable. You can enter the details manually.');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _select(Suggestion suggestion) {
    final normalized = AddressEngine.normalize(suggestion: suggestion);
    _selected = normalized;
    _search.text = AddressEngine.display(normalized);
    _line1.text = AddressEngine.clean(normalized['addressLine1']);
    _line2.text = AddressEngine.clean(normalized['addressLine2']);
    _city.text = AddressEngine.clean(normalized['city']);
    _postcode.text = AddressEngine.clean(normalized['postcode']);
    _country.text = AddressEngine.clean(normalized['country']);
    setState(() => _suggestions = const []);
  }

  Map<String, dynamic> _address() => AddressEngine.normalize(
        components: {
          ..._selected,
          'addressLine1': _line1.text,
          'addressLine2': _line2.text,
          'city': _city.text,
          'postcode': _postcode.text,
          'country': _country.text
        },
        placeId: _selected['placeId'],
        latitude: _selected['latitude'],
        longitude: _selected['longitude'],
        source: _selected.isEmpty ? 'manual' : 'autocomplete',
      );

  Future<void> _save() async {
    if (_saving) return;
    final address = _address();
    if (_label == 'other' && _customLabel.text.trim().isEmpty) {
      setState(() => _error = 'Add a custom label.');
      return;
    }
    if (!AddressEngine.isValid(address)) {
      setState(() =>
          _error = 'Complete address line 1, city, postcode and country.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.save(
          addressId: widget.existing?.id,
          label: _label,
          customLabel: _customLabel.text,
          address: address,
          deliveryInstructions: _instructions.text,
          isDefaultPickup: _defaultPickup,
          isDefaultDropoff: _defaultDropoff);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Address saved.')));
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error'.replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _AddressColors.bg,
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title:
                Text(widget.existing == null ? 'Add Address' : 'Edit Address')),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            children: [
              const _SectionLabel('Choose label'),
              SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'home',
                        label: Text('Home'),
                        icon: Icon(Icons.home_outlined)),
                    ButtonSegment(
                        value: 'work',
                        label: Text('Work'),
                        icon: Icon(Icons.work_outline)),
                    ButtonSegment(
                        value: 'other',
                        label: Text('Other'),
                        icon: Icon(Icons.place_outlined))
                  ],
                  selected: {
                    _label
                  },
                  onSelectionChanged: (value) =>
                      setState(() => _label = value.first)),
              if (_label == 'other') ...[
                const SizedBox(height: 12),
                _Field(controller: _customLabel, label: 'Custom label')
              ],
              const _SectionLabel('Find address'),
              _Field(
                  controller: _search,
                  label: 'Search address or postcode',
                  onChanged: _lookup),
              if (_searching) const LinearProgressIndicator(minHeight: 2),
              ..._suggestions.take(4).map((suggestion) => ListTile(
                  title: Text(suggestion.mainText,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(suggestion.subText,
                      style: const TextStyle(color: _AddressColors.muted)),
                  onTap: () => _select(suggestion))),
              const _SectionLabel('Confirm address details'),
              _Field(controller: _line1, label: 'Address line 1'),
              const SizedBox(height: 10),
              _Field(controller: _line2, label: 'Address line 2 (optional)'),
              const SizedBox(height: 10),
              _Field(controller: _city, label: 'City'),
              const SizedBox(height: 10),
              _Field(controller: _postcode, label: 'Postcode'),
              const SizedBox(height: 10),
              _Field(controller: _country, label: 'Country'),
              const _SectionLabel('Delivery instructions'),
              _Field(
                  controller: _instructions,
                  label: 'Access, entrance or handover notes (optional)',
                  maxLines: 3),
              const _SectionLabel('Default settings'),
              SwitchListTile(
                  value: _defaultPickup,
                  onChanged: (value) => setState(() => _defaultPickup = value),
                  title: const Text('Set as default pickup',
                      style: TextStyle(color: Colors.white))),
              SwitchListTile(
                  value: _defaultDropoff,
                  onChanged: (value) => setState(() => _defaultDropoff = value),
                  title: const Text('Set as default drop-off',
                      style: TextStyle(color: Colors.white))),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: Color(0xFFFCA5A5)))),
              const SizedBox(height: 18),
              SizedBox(
                  height: 54,
                  child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Review and save'))),
            ]),
      );
}

class SenderSavedAddressSuggestions extends StatelessWidget {
  final bool forPickup;
  final ValueChanged<SenderSavedAddress> onSelected;
  final SenderSavedAddressesRepository? repository;
  const SenderSavedAddressSuggestions(
      {super.key,
      required this.forPickup,
      required this.onSelected,
      this.repository});
  @override
  Widget build(BuildContext context) {
    final repo = repository ?? FirebaseSenderSavedAddressesRepository();
    return StreamBuilder<List<SenderSavedAddress>>(
        stream: repo.watch(),
        builder: (context, snapshot) {
          final addresses = [...?snapshot.data];
          addresses.sort((a, b) =>
              ((forPickup ? b.isDefaultPickup : b.isDefaultDropoff) ? 1 : 0)
                  .compareTo(
                      (forPickup ? a.isDefaultPickup : a.isDefaultDropoff)
                          ? 1
                          : 0));
          if (addresses.isEmpty) return const SizedBox.shrink();
          return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                  height: 42,
                  child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: addresses
                          .map((address) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                  avatar: const Icon(Icons.location_on_outlined,
                                      size: 17),
                                  label: Text(address.displayLabel),
                                  onPressed: () => onSelected(address))))
                          .toList())));
        });
  }
}

class SenderSavedAddressesProfileShortcut extends StatelessWidget {
  final SenderSavedAddressesRepository? repository;
  const SenderSavedAddressesProfileShortcut({super.key, this.repository});
  @override
  Widget build(BuildContext context) {
    final repo = repository ?? FirebaseSenderSavedAddressesRepository();
    return StreamBuilder<List<SenderSavedAddress>>(
        stream: repo.watch(),
        builder: (context, snapshot) {
          final addresses = snapshot.data ?? const [];
          final preview = addresses.isEmpty
              ? 'No saved addresses yet.'
              : addresses
                  .take(2)
                  .map((item) =>
                      '${item.displayLabel} · ${AddressEngine.clean(item.address['addressLine1'])}')
                  .join('\n');
          return Material(
            color: Colors.transparent,
            child: ListTile(
              minTileHeight: 66,
              leading: const Icon(Icons.location_on_outlined,
                  color: _AddressColors.lightBlue),
              title: const Text('Saved addresses',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
              subtitle: Text(preview,
                  style: const TextStyle(color: _AddressColors.muted)),
              trailing:
                  const Icon(Icons.chevron_right, color: _AddressColors.muted),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => SenderSavedAddressesView(repository: repo))),
            ),
          );
        });
  }
}

class _AddressCard extends StatelessWidget {
  final SenderSavedAddress address;
  final SenderSavedAddressesRepository repository;
  const _AddressCard({required this.address, required this.repository});
  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
                    title: const Text('Delete saved address?'),
                    content: Text(address.isDefaultPickup ||
                            address.isDefaultDropoff
                        ? 'This is a default address. Deleting it removes that default and preserves no replacement.'
                        : 'This address will be removed from your account.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete'))
                    ])) ??
        false;
    if (confirmed) await repository.delete(address.id);
  }

  @override
  Widget build(BuildContext context) => _Glass(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(address.displayLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900))),
          IconButton(
              tooltip: 'Edit address',
              onPressed: () => SenderSavedAddressesView._openEditor(
                  context, repository, address),
              icon: const Icon(Icons.edit_outlined)),
          IconButton(
              tooltip: 'Delete address',
              onPressed: () => _delete(context),
              icon: const Icon(Icons.delete_outline))
        ]),
        Text(address.formattedAddress,
            style: const TextStyle(color: _AddressColors.muted, height: 1.4)),
        if (address.deliveryInstructions.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(address.deliveryInstructions,
                  style: const TextStyle(color: Colors.white70))),
        if (address.isDefaultPickup || address.isDefaultDropoff)
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 8, children: [
                if (address.isDefaultPickup)
                  const Chip(label: Text('Default pickup')),
                if (address.isDefaultDropoff)
                  const Chip(label: Text('Default drop-off'))
              ])),
      ]));
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  const _Field(
      {required this.controller,
      required this.label,
      this.onChanged,
      this.maxLines = 1});
  @override
  Widget build(BuildContext context) => TextField(
      controller: controller,
      onChanged: onChanged,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _AddressColors.muted),
          filled: true,
          fillColor: Colors.white.withValues(alpha: .04),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))));
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900)));
}

class _AddressState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _AddressState(
      {required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: _AddressColors.lightBlue, size: 42),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: _AddressColors.muted, height: 1.45))
          ])));
}

class _Glass extends StatelessWidget {
  final Widget child;
  const _Glass({required this.child});
  @override
  Widget build(BuildContext context) => AppGlassContainer(
        radius: AppTokens.radius22,
        child: child,
      );
}

class _AddressColors {
  static const bg = Color(0xFF07090F);
  static const blue = Color(0xFF3B82F6);
  static const lightBlue = Color(0xFF60A5FA);
  static const muted = Color(0xFF9CA3AF);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
