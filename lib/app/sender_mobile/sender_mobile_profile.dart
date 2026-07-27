import 'dart:typed_data';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../sender_profile/sender_profile.dart';
import '../send_package/view/ride_chats.dart';
import 'design_system/sender_design_system.dart';
import 'sender_saved_addresses.dart';
import 'sender_notifications.dart';
import 'sender_wallet.dart';

class SenderTrustActivity {
  final int points;
  final String label;
  final DateTime? occurredAt;

  const SenderTrustActivity({
    required this.points,
    required this.label,
    this.occurredAt,
  });

  factory SenderTrustActivity.fromMap(Map<String, dynamic> data) {
    final rawType = SenderMobileProfileData.firstText([
      data['label'],
      data['eventLabel'],
      data['reason'],
      data['eventType'],
      data['action'],
    ]);
    return SenderTrustActivity(
      points: ((data['points'] ?? data['delta'] ?? data['amount']) as num?)
              ?.toInt() ??
          0,
      label: _friendlyTrustLabel(rawType),
      occurredAt: SenderMobileProfileData.profileDate(
        data['createdAt'] ?? data['occurredAt'] ?? data['timestamp'],
      ),
    );
  }

  static String _friendlyTrustLabel(String value) {
    if (value.isEmpty) return 'Trust activity';
    final normalized =
        value.trim().toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ');
    if (normalized.contains('system baseline') ||
        normalized.contains('delivery history baseline')) {
      return 'Account trust baseline established';
    }
    if (normalized.contains('successful delivery') ||
        normalized.contains('delivery completed')) {
      return 'Delivery completed';
    }
    if (normalized.contains('adjustment') ||
        normalized.contains('manual credit')) {
      return 'Adjustment by Circum';
    }
    return value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  bool get isBaselineEvent {
    final normalized = label.trim().toLowerCase();
    return normalized == 'account trust baseline established';
  }
}

class SenderMobileProfileData {
  final String userId;
  final String displayName;
  final String username;
  final String email;
  final String phone;
  final String photoUrl;
  final String accountType;
  final DateTime? createdAt;
  final int trustScore;
  final bool hasTrustScore;
  final String trustTier;
  final String? nextTier;
  final int pointsToNextTier;
  final int completedDeliveries;
  final bool hasCompletedDeliveries;
  final List<SenderTrustActivity> trustHistory;

  const SenderMobileProfileData({
    required this.userId,
    required this.displayName,
    this.username = '',
    required this.email,
    required this.phone,
    required this.photoUrl,
    this.accountType = 'sender',
    this.createdAt,
    this.trustScore = 0,
    this.hasTrustScore = true,
    this.trustTier = 'new_sender',
    this.nextTier,
    this.pointsToNextTier = 25,
    this.completedDeliveries = 0,
    this.hasCompletedDeliveries = true,
    this.trustHistory = const [],
  });

  factory SenderMobileProfileData.fromSources({
    required User user,
    Map<String, dynamic>? data,
    List<Map<String, dynamic>>? trustEvents,
  }) {
    final profile = data ?? const <String, dynamic>{};
    final hasTrustScore = profile.containsKey('senderTrustPoints') ||
        profile.containsKey('trustPoints') ||
        profile.containsKey('trustScore');
    final hasCompletedDeliveries = profile.containsKey('completedDeliveries') ||
        profile.containsKey('deliveriesCompleted');
    final trustScore =
        ((profile['senderTrustPoints'] ?? profile['trustPoints']) as num?)
                ?.toInt() ??
            (profile['trustScore'] as num?)?.toInt() ??
            0;
    final trustTier = SenderTrustPolicy.normalizeTier(
      profile['senderTier'] ?? profile['trustTier'],
      points: trustScore,
    );
    final backendNextTier = firstText([profile['nextTier']]);
    final nextTier = backendNextTier.isNotEmpty
        ? SenderTrustPolicy.normalizeTier(backendNextTier)
        : SenderTrustPolicy.nextTier(trustTier);
    final embeddedHistory = (profile['trustHistory'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final historySource =
        trustEvents?.isNotEmpty == true ? trustEvents! : embeddedHistory;
    final history = historySource
        .map(SenderTrustActivity.fromMap)
        .where((activity) => !activity.isBaselineEvent)
        .toList(growable: false)
      ..sort((a, b) {
        final aDate = a.occurredAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.occurredAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    final dedupedHistory = <SenderTrustActivity>[];
    final seenHistoryKeys = <String>{};
    for (final activity in history) {
      final dateKey = activity.occurredAt == null
          ? ''
          : DateTime(
              activity.occurredAt!.year,
              activity.occurredAt!.month,
              activity.occurredAt!.day,
            ).toIso8601String();
      final key = '${activity.label}|${activity.points}|$dateKey';
      if (seenHistoryKeys.add(key)) dedupedHistory.add(activity);
    }
    return SenderMobileProfileData(
      userId: user.uid,
      displayName: firstText([
        profile['displayName'],
        profile['fullName'],
        profile['fullname'],
        profile['name'],
        user.displayName,
      ]),
      username: firstText([
        profile['username'],
        profile['handle'],
        profile['userHandle'],
      ]).replaceFirst(RegExp(r'^@'), ''),
      email: firstText([profile['email'], user.email]),
      phone: firstText([
        profile['phone'],
        profile['phoneNumber'],
        user.phoneNumber,
      ]),
      photoUrl: firstText([
        profile['photoURL'],
        profile['photoUrl'],
        user.photoURL,
      ]),
      accountType: 'sender',
      createdAt:
          profileDate(profile['createdAt']) ?? user.metadata.creationTime,
      trustScore: trustScore,
      hasTrustScore: hasTrustScore,
      trustTier: trustTier,
      nextTier: nextTier,
      pointsToNextTier: (profile['pointsToNextTier'] as num?)?.toInt() ??
          SenderTrustPolicy.pointsForNextTier(trustScore),
      completedDeliveries: ((profile['completedDeliveries'] ??
                  profile['deliveriesCompleted']) as num?)
              ?.toInt() ??
          0,
      hasCompletedDeliveries: hasCompletedDeliveries,
      trustHistory: dedupedHistory,
    );
  }

  String get memberSinceLabel => createdAt == null
      ? 'Member since unavailable'
      : 'Member since ${createdAt!.year}';

  String get memberSinceValue =>
      createdAt == null ? 'Unavailable' : _profileDateLabel(createdAt!);

  String get trustScoreLabel => hasTrustScore ? '$trustScore' : '—';

  String get completedDeliveriesLabel =>
      hasCompletedDeliveries ? '$completedDeliveries' : '—';

  double get trustProgress {
    final resolvedNextTier = nextTier ?? SenderTrustPolicy.nextTier(trustTier);
    if (resolvedNextTier == null) return 1;
    final currentThreshold = SenderTrustPolicy.thresholds[trustTier] ?? 0;
    final nextThreshold =
        SenderTrustPolicy.thresholds[resolvedNextTier] ?? trustScore;
    final range = nextThreshold - currentThreshold;
    if (range <= 0) return 1;
    return ((trustScore - currentThreshold) / range).clamp(0, 1).toDouble();
  }

  String get trustTierLabel =>
      (SenderTrustPolicy.tierLabels[trustTier] ?? 'New Sender')
          .replaceAll(' Sender', '');

  String? get nextTierLabel {
    final resolvedNextTier = nextTier ?? SenderTrustPolicy.nextTier(trustTier);
    return resolvedNextTier == null
        ? null
        : (SenderTrustPolicy.tierLabels[resolvedNextTier] ?? '')
            .replaceAll(' Sender', '');
  }

  static DateTime? profileDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = value == null ? '' : '$value'.trim();
      if (text.isNotEmpty && text != 'null' && text != 'undefined') {
        return text;
      }
    }
    return '';
  }
}

abstract class SenderMobileProfileRepository {
  Future<SenderMobileProfileData> load();

  Stream<SenderMobileProfileData> watch();

  Future<SenderMobileProfileData> save({
    required String displayName,
    required String username,
    required String phone,
  });

  Future<SenderMobileProfileData> uploadPhoto(SenderProfilePhoto photo);

  Future<void> logout();

  Future<void> closeAccount();
}

class SenderProfilePhoto {
  final Uint8List bytes;
  final String filename;
  final String contentType;

  const SenderProfilePhoto({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });
}

abstract class SenderProfilePhotoPicker {
  Future<SenderProfilePhoto?> pick();
}

class ImagePickerSenderProfilePhotoPicker implements SenderProfilePhotoPicker {
  final ImagePicker picker;

  ImagePickerSenderProfilePhotoPicker({ImagePicker? picker})
      : picker = picker ?? ImagePicker();

  @override
  Future<SenderProfilePhoto?> pick() async {
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (image == null) return null;
    final extension = image.name.toLowerCase().split('.').last;
    return SenderProfilePhoto(
      bytes: await image.readAsBytes(),
      filename: image.name,
      contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
    );
  }
}

class FirebaseSenderMobileProfileRepository
    implements SenderMobileProfileRepository {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseStorage storage;
  final FirebaseFunctions functions;

  FirebaseSenderMobileProfileRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        storage = storage ?? FirebaseStorage.instance,
        functions = functions ?? FirebaseFunctions.instance;

  @override
  Future<SenderMobileProfileData> load() async {
    final user = auth.currentUser;
    if (user == null) {
      throw const SenderMobileProfileException(
        'Sign in again to load your profile.',
      );
    }
    DocumentSnapshot<Map<String, dynamic>>? snapshot;
    SenderMobileProfileException? profileReadError;
    try {
      snapshot = await firestore.collection('users').doc(user.uid).get();
    } catch (_) {
      profileReadError = const SenderMobileProfileException(
        'Profile details are temporarily limited. Your account is still available.',
      );
    }
    List<Map<String, dynamic>> trustEvents = const [];
    try {
      final eventSnapshot = await firestore
          .collection('senderTrustEvents')
          .where('userId', isEqualTo: user.uid)
          .limit(20)
          .get();
      trustEvents = eventSnapshot.docs
          .map((document) => document.data())
          .toList(growable: false);
    } catch (_) {
      // The profile's embedded trust history remains the safe fallback.
    }
    final profile = SenderMobileProfileData.fromSources(
      user: user,
      data: snapshot?.data(),
      trustEvents: trustEvents,
    );
    if (profileReadError != null &&
        profile.displayName.isEmpty &&
        profile.email.isEmpty &&
        profile.phone.isEmpty) {
      throw profileReadError;
    }
    return profile;
  }

  @override
  Stream<SenderMobileProfileData> watch() async* {
    final user = auth.currentUser;
    if (user == null) {
      throw const SenderMobileProfileException(
        'Sign in again to load your profile.',
      );
    }
    await for (final snapshot
        in firestore.collection('users').doc(user.uid).snapshots()) {
      List<Map<String, dynamic>> trustEvents = const [];
      try {
        final eventSnapshot = await firestore
            .collection('senderTrustEvents')
            .where('userId', isEqualTo: user.uid)
            .limit(20)
            .get();
        trustEvents = eventSnapshot.docs
            .map((document) => document.data())
            .toList(growable: false);
      } catch (_) {
        // The profile's embedded trust history remains the safe fallback.
      }
      yield SenderMobileProfileData.fromSources(
        user: user,
        data: snapshot.data(),
        trustEvents: trustEvents,
      );
    }
  }

  @override
  Future<SenderMobileProfileData> save({
    required String displayName,
    required String username,
    required String phone,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw const SenderMobileProfileException(
        'Sign in again before saving your profile.',
      );
    }
    final normalizedUsername = username.trim().replaceFirst(RegExp(r'^@'), '');
    await functions.httpsCallable('updateSenderProfile').call({
      'displayName': displayName.trim(),
      'username': normalizedUsername,
      'phone': phone.trim(),
    });
    if (user.displayName != displayName.trim()) {
      await user.updateDisplayName(displayName.trim());
    }
    final updated = await firestore.collection('users').doc(user.uid).get();
    return SenderMobileProfileData.fromSources(
      user: user,
      data: {
        ...?updated.data(),
        'displayName': displayName.trim(),
        'username': normalizedUsername,
        'email': user.email?.trim() ?? '',
        'phone': phone.trim(),
        'photoURL': user.photoURL?.trim() ?? '',
      },
    );
  }

  @override
  Future<SenderMobileProfileData> uploadPhoto(
    SenderProfilePhoto photo,
  ) async {
    final user = auth.currentUser;
    if (user == null) {
      throw const SenderMobileProfileException(
        'Sign in again before uploading a profile photo.',
      );
    }
    if (photo.bytes.isEmpty || photo.bytes.lengthInBytes > 8 * 1024 * 1024) {
      throw const SenderMobileProfileException(
        'Choose a profile photo smaller than 8 MB.',
      );
    }
    final extension = photo.contentType == 'image/png' ? 'png' : 'jpg';
    final reference = storage.ref(
      'users/${user.uid}/profile/avatar.$extension',
    );
    await reference.putData(
      photo.bytes,
      SettableMetadata(
        contentType: photo.contentType,
        cacheControl: 'public,max-age=3600',
        customMetadata: {
          'ownerUid': user.uid,
          'source': 'sender_mobile_profile',
        },
      ),
    );
    final downloadUrl = await reference.getDownloadURL();
    await functions.httpsCallable('updateSenderProfilePhoto').call({
      'photoURL': downloadUrl,
    });
    await user.updatePhotoURL(downloadUrl);
    final current = await load();
    return SenderMobileProfileData(
      userId: current.userId,
      displayName: current.displayName,
      username: current.username,
      email: current.email,
      phone: current.phone,
      photoUrl: downloadUrl,
      createdAt: current.createdAt,
      trustScore: current.trustScore,
      hasTrustScore: current.hasTrustScore,
      trustTier: current.trustTier,
      nextTier: current.nextTier,
      pointsToNextTier: current.pointsToNextTier,
      completedDeliveries: current.completedDeliveries,
      hasCompletedDeliveries: current.hasCompletedDeliveries,
      trustHistory: current.trustHistory,
    );
  }

  @override
  Future<void> logout() => auth.signOut();

  @override
  Future<void> closeAccount() async {
    await functions.httpsCallable('closeCircumAccount').call<void>({
      'accountType': 'sender',
    });
    await auth.signOut();
  }
}

class SenderMobileProfileException implements Exception {
  final String message;

  const SenderMobileProfileException(this.message);

  @override
  String toString() => message;
}

class SenderMobileProfileView extends StatefulWidget {
  final SenderMobileProfileRepository? repository;
  final SenderProfilePhotoPicker? photoPicker;
  final VoidCallback? onLoggedOut;
  final VoidCallback? onOpenWallet;
  final SenderSavedAddressesRepository? savedAddressesRepository;

  const SenderMobileProfileView({
    super.key,
    this.repository,
    this.photoPicker,
    this.onLoggedOut,
    this.onOpenWallet,
    this.savedAddressesRepository,
  });

  @override
  State<SenderMobileProfileView> createState() =>
      _SenderMobileProfileViewState();
}

class _SenderMobileProfileViewState extends State<SenderMobileProfileView> {
  late final SenderMobileProfileRepository _repository;
  late final SenderProfilePhotoPicker _photoPicker;
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  SenderMobileProfileData? _profile;
  String? _error;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  bool _uploadingPhoto = false;
  StreamSubscription<SenderMobileProfileData>? _profileSubscription;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseSenderMobileProfileRepository();
    _photoPicker = widget.photoPicker ?? ImagePickerSenderProfilePhotoPicker();
    _load();
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _profileSubscription?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _repository.load();
      if (!mounted) return;
      _applyProfile(profile);
      setState(() {
        _profile = profile;
        _loading = false;
        _error = null;
      });
      _profileSubscription = _repository.watch().listen((liveProfile) {
        if (!mounted) return;
        if (!_editing && !_saving) _applyProfile(liveProfile);
        setState(() {
          _profile = liveProfile;
          _error = null;
        });
      }, onError: (_) {
        if (!mounted) return;
        setState(() {
          _error = 'Live profile updates could not connect. Please try again.';
        });
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is SenderMobileProfileException
            ? error.message
            : 'We could not load your profile. Check your connection.';
      });
    }
  }

  void _applyProfile(SenderMobileProfileData profile) {
    _nameController.text = profile.displayName;
    _usernameController.text = profile.username;
    _phoneController.text = profile.phone;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await _repository.save(
        displayName: _nameController.text,
        username: _usernameController.text,
        phone: _phoneController.text,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _editing = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Your changes could not be saved. Please try again.';
      });
    }
  }

  Future<void> _logout() async {
    try {
      await _repository.logout();
      if (!mounted) return;
      widget.onLoggedOut?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'We could not log you out. Please try again.');
    }
  }

  Future<void> _uploadPhoto() async {
    if (_uploadingPhoto) return;
    try {
      final photo = await _photoPicker.pick();
      if (photo == null || !mounted) return;
      setState(() {
        _uploadingPhoto = true;
        _error = null;
      });
      final profile = await _repository.uploadPhoto(photo);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _uploadingPhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        _error = error is SenderMobileProfileException
            ? error.message
            : 'Your profile photo could not be saved. Please try again.';
      });
    }
  }

  Future<void> _confirmCloseAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _ProfileTokens.panel,
        title: const Text('Close your Circum account?'),
        content: const Text(
          'This permanently closes your Circum account. Active deliveries, '
          'open disputes or pending payments must be resolved first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep account'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            child: const Text('Close account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repository.closeAccount();
      if (!mounted) return;
      widget.onLoggedOut?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is FirebaseFunctionsException &&
                (error.message?.trim().isNotEmpty ?? false)
            ? error.message!.trim()
            : 'Your account could not be closed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _ProfileLoadingState();
    }
    if (_profile == null) {
      return _ProfileErrorState(message: _error, onRetry: _load);
    }
    final profile = _profile!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final horizontalPadding = wide ? 28.0 : 18.0;
        final identity = _ProfileIdentityCard(
          profile: profile,
          uploadingPhoto: _uploadingPhoto,
          editing: _editing,
          onUploadPhoto: _uploadPhoto,
          onEdit: () => setState(() => _editing = true),
        );
        final details = _editing
            ? _EditProfileCard(
                nameController: _nameController,
                usernameController: _usernameController,
                phoneController: _phoneController,
                email: profile.email,
                saving: _saving,
                onCancel: () {
                  _applyProfile(profile);
                  setState(() {
                    _editing = false;
                    _error = null;
                  });
                },
                onSave: _save,
              )
            : _ProfileDetailsCard(profile: profile);
        final trust = _ProfileTrustCard(
          profile: profile,
          onViewDetails: () => _showTrustDetails(profile),
          onViewHistory: () => _showTrustHistory(profile),
        );
        return ListView(
          key: const Key('sender-profile-view'),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            22,
            horizontalPadding,
            104,
          ),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                key: const Key('sender-profile-constrained-layout'),
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Profile',
                      style: GoogleFonts.dmSerifDisplay(
                        color: Colors.white,
                        fontSize: wide ? 34 : 30,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _ProfileMessage(message: _error!),
                    ],
                    const SizedBox(height: 20),
                    identity,
                    if (_editing) ...[
                      const SizedBox(height: 18),
                      details,
                    ],
                    const SizedBox(height: 24),
                    trust,
                    const SizedBox(height: 28),
                    _circumShortcuts(),
                    const SizedBox(height: 28),
                    _accountSection(),
                    const SizedBox(height: 28),
                    _helpSection(),
                    const SizedBox(height: 28),
                    _ProfileGlassCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _ProfileShortcut(
                            key: const Key('sender-profile-close-account'),
                            icon: Icons.delete_outline_rounded,
                            title: 'Close account',
                            subtitle: 'Permanently close your Circum account.',
                            onTap: _confirmCloseAccount,
                            danger: true,
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ProfileGlassCard(
                      padding: EdgeInsets.zero,
                      child: _ProfileShortcut(
                        key: const Key('sender-profile-logout'),
                        icon: Icons.logout_rounded,
                        title: 'Log out',
                        subtitle: 'Sign out of this device.',
                        onTap: _logout,
                        showDivider: false,
                      ),
                    ),
                    const SizedBox(height: 26),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _circumShortcuts() => _ProfileGlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            const _ProfileSectionTitleRow(title: 'Circum tools'),
            SenderSavedAddressesProfileShortcut(
              repository: widget.savedAddressesRepository ??
                  (widget.repository == null
                      ? null
                      : const EmptySenderSavedAddressesRepository()),
            ),
            _ProfileShortcut(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Wallet',
              subtitle: 'Roth balance, rewards and transactions.',
              onTap: widget.onOpenWallet ??
                  () => _showLocalMessage('Wallet is unavailable.'),
            ),
            _ProfileShortcut(
              icon: Icons.group_add_outlined,
              title: 'Referrals',
              subtitle: 'Invite friends and view referral rewards.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SenderReferralScreen(),
                  settings:
                      const RouteSettings(name: '/sender-mobile/wallet/earn'),
                ),
              ),
              showDivider: false,
            ),
          ],
        ),
      );

  Widget _accountSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileGlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                const _ProfileSectionTitleRow(title: 'Account'),
                _ProfileShortcut(
                  icon: Icons.notifications_none_rounded,
                  title: 'Notifications',
                  subtitle: 'Choose how Circum keeps you informed.',
                  onTap: _openNotifications,
                ),
                _ProfileShortcut(
                  icon: Icons.credit_card_rounded,
                  title: 'Payment methods',
                  subtitle: 'Manage saved payment methods.',
                  onTap: widget.onOpenWallet ??
                      () => _showLocalMessage('Wallet is unavailable.'),
                ),
                _ProfileShortcut(
                  icon: Icons.lock_outline_rounded,
                  title: 'Security',
                  subtitle: 'Password and account protection.',
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const _SenderSecuritySettingsScreen(),
                    settings: const RouteSettings(
                        name: '/sender-mobile/profile/security'),
                  )),
                ),
                _ProfileShortcut(
                  icon: Icons.language_rounded,
                  title: 'Language',
                  subtitle: 'Language, region and time format.',
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const _SenderLanguageSettingsScreen(),
                    settings: const RouteSettings(
                        name: '/sender-mobile/profile/language'),
                  )),
                ),
                _ProfileShortcut(
                  icon: Icons.accessibility_new_rounded,
                  title: 'Accessibility',
                  subtitle: 'Adjust your Circum experience.',
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const _SenderAccessibilitySettingsScreen(),
                    settings: const RouteSettings(
                        name: '/sender-mobile/profile/accessibility'),
                  )),
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
      );

  Widget _helpSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileGlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                const _ProfileSectionTitleRow(title: 'Support and policies'),
                _ProfileShortcut(
                  icon: Icons.support_agent_rounded,
                  title: 'Help & Support',
                  subtitle: 'Get help with your Circum account.',
                  onTap: _openSupport,
                ),
                _ProfileShortcut(
                  key: const Key('sender-profile-help-shape-circum'),
                  icon: Icons.auto_awesome_outlined,
                  title: 'Help Shape Circum',
                  subtitle: 'Share product feedback with the Circum team.',
                  onTap: _openFeedback,
                ),
                _ProfileShortcut(
                  key: const Key('sender-profile-community-requests'),
                  icon: Icons.forum_outlined,
                  title: 'Community Requests',
                  subtitle: 'View the Circum community request centre.',
                  onTap: _openCommunityRequests,
                ),
                _ProfileShortcut(
                  key: const Key('sender-profile-terms'),
                  icon: Icons.description_outlined,
                  title: 'Terms',
                  subtitle: 'Circum Terms of Service.',
                  onTap: () => _openLegalDocument(
                      'Terms', '/sender-mobile/profile/terms'),
                ),
                _ProfileShortcut(
                  key: const Key('sender-profile-privacy'),
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy',
                  subtitle: 'How Circum protects your information.',
                  onTap: () => _openLegalDocument(
                      'Privacy', '/sender-mobile/profile/privacy'),
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
      );

  void _showLocalMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openLegalDocument(String title, String routeName) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _SenderLegalDocumentScreen(title: title),
      settings: RouteSettings(name: routeName),
    ));
  }

  Future<void> _openNotifications() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SenderNotificationsView(),
          settings:
              const RouteSettings(name: '/sender-mobile/profile/notifications'),
        ),
      );

  Future<void> _openSupport() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const RideChatPageView(
            title: 'Circum Support',
            supportConversation: true,
          ),
          settings: const RouteSettings(name: '/sender-mobile/profile/support'),
        ),
      );

  Future<void> _openFeedback() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const _SenderClosedSubmissionScreen(
            title: 'Help Shape Circum',
            subtitle:
                'Send feedback to Circum Admin. This creates a closed admin note, not a live chat.',
            topic: 'sender_feedback',
            messageLabel: 'What should the Circum team know?',
            messageHint:
                'Tell us what worked, what broke, or what would improve Circum.',
            submitLabel: 'Send feedback',
            successMessage: 'Feedback sent to Circum Admin.',
            rows: [
              _SenderSubmissionInfo(
                icon: Icons.lightbulb_outline_rounded,
                title: 'Product feedback',
                subtitle:
                    'Tell us what would make Circum booking, tracking or support better.',
              ),
              _SenderSubmissionInfo(
                icon: Icons.bug_report_outlined,
                title: 'Report a Circum issue',
                subtitle:
                    'Share broken flows, confusing moments or missing Circum details.',
              ),
              _SenderSubmissionInfo(
                icon: Icons.favorite_border_rounded,
                title: 'What worked well',
                subtitle:
                    'Positive feedback helps the Circum team protect the good parts.',
              ),
            ],
          ),
          settings: const RouteSettings(
              name: '/sender-mobile/profile/help-shape-circum'),
        ),
      );

  Future<void> _openCommunityRequests() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const _SenderClosedSubmissionScreen(
            title: 'Community Requests',
            subtitle:
                'Send a request to Circum Admin. Requests are reviewed internally and are not trackable in-app.',
            topic: 'community_request',
            messageLabel: 'What should Circum consider?',
            messageHint:
                'Describe the request, who it helps, and why it matters.',
            submitLabel: 'Send request',
            successMessage: 'Community request sent to Circum Admin.',
            rows: [
              _SenderSubmissionInfo(
                icon: Icons.forum_outlined,
                title: 'One-way submission',
                subtitle:
                    'Circum receives the request with your account details for review.',
              ),
              _SenderSubmissionInfo(
                icon: Icons.lock_outline_rounded,
                title: 'No tracking queue',
                subtitle:
                    'You will not need to monitor statuses or manage request history.',
              ),
              _SenderSubmissionInfo(
                icon: Icons.admin_panel_settings_outlined,
                title: 'Admin review',
                subtitle:
                    'The request appears in Admin as a closed message with sender context.',
              ),
            ],
          ),
          settings: const RouteSettings(
              name: '/sender-mobile/profile/community-requests'),
        ),
      );

  void _showTrustDetails(SenderMobileProfileData profile) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _ProfileTokens.panel,
      showDragHandle: true,
      builder: (_) => _TrustDetailsSheet(profile: profile),
    );
  }

  void _showTrustHistory(SenderMobileProfileData profile) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _ProfileTokens.panel,
      showDragHandle: true,
      builder: (_) => _TrustHistorySheet(activities: profile.trustHistory),
    );
  }
}

class _ProfileIdentityCard extends StatelessWidget {
  final SenderMobileProfileData profile;
  final bool uploadingPhoto;
  final bool editing;
  final VoidCallback onUploadPhoto;
  final VoidCallback onEdit;

  const _ProfileIdentityCard({
    required this.profile,
    required this.uploadingPhoto,
    required this.editing,
    required this.onUploadPhoto,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return _ProfileGlassCard(
      child: Column(
        children: [
          _ProfileAvatar(
            profile: profile,
            uploading: uploadingPhoto,
            onUpload: onUploadPhoto,
          ),
          const SizedBox(height: 18),
          Text(
            profile.displayName.isEmpty ? 'Add your name' : profile.displayName,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          _UsernameSummary(
            username: profile.username,
            onCreate: editing ? null : onEdit,
          ),
          const SizedBox(height: 10),
          if (profile.email.isNotEmpty)
            Text(
              profile.email,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: _ProfileTokens.muted,
                fontSize: 13,
                height: 1.25,
              ),
            ),
          const SizedBox(height: 16),
          _AccountTypeBadge(memberSinceLabel: profile.memberSinceValue),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('sender-profile-primary-edit'),
              onPressed: editing ? null : onEdit,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Edit Profile'),
              style: _secondaryButtonStyle(),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditProfileCard extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController usernameController;
  final TextEditingController phoneController;
  final String email;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _EditProfileCard({
    required this.nameController,
    required this.usernameController,
    required this.phoneController,
    required this.email,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _ProfileGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit profile',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          _ProfileField(
            key: const Key('sender-profile-name-field'),
            controller: nameController,
            label: 'Display name',
            hint: 'Add your name',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          _ProfileField(
            key: const Key('sender-profile-username-field'),
            controller: usernameController,
            label: 'Username',
            hint: 'Choose a username',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          _ProfileField(
            key: const Key('sender-profile-phone-field'),
            controller: phoneController,
            label: 'Phone number',
            hint: 'Add your phone number',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: _fieldDecoration('Email'),
            child: Text(
              email.isEmpty ? 'Email unavailable' : email,
              style: GoogleFonts.inter(color: _ProfileTokens.muted),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: saving ? null : onCancel,
                  style: _secondaryButtonStyle(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  key: const Key('sender-profile-save'),
                  onPressed: saving ? null : onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ProfileTokens.accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsernameSummary extends StatelessWidget {
  final String username;
  final VoidCallback? onCreate;

  const _UsernameSummary({
    required this.username,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    if (username.isNotEmpty) {
      return Column(
        children: [
          Text(
            'Username',
            style: GoogleFonts.inter(
              color: _ProfileTokens.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '@$username',
            key: const Key('sender-profile-username'),
            style: GoogleFonts.jetBrainsMono(
              color: _ProfileTokens.lightAccent,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Text(
          'Username',
          style: GoogleFonts.inter(
            color: _ProfileTokens.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Not set',
          key: const Key('sender-profile-username'),
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: onCreate,
          style: TextButton.styleFrom(
            foregroundColor: _ProfileTokens.lightAccent,
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Create Username'),
        ),
      ],
    );
  }
}

class _ProfileField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  const _ProfileField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: GoogleFonts.inter(color: Colors.white),
      decoration: _fieldDecoration(label).copyWith(hintText: hint),
    );
  }
}

class _ProfileDetailsCard extends StatelessWidget {
  final SenderMobileProfileData profile;

  const _ProfileDetailsCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _ProfileGlassCard(
      child: Column(
        children: [
          _ProfileDetail(
            label: 'Name',
            value: profile.displayName.isEmpty
                ? 'Not added yet'
                : profile.displayName,
          ),
          _ProfileDetail(
            label: 'Username',
            value: profile.username.isEmpty
                ? 'Not added yet'
                : '@${profile.username}',
          ),
          _ProfileDetail(
            label: 'Email',
            value: profile.email.isEmpty ? 'Not available' : profile.email,
          ),
          _ProfileDetail(
            label: 'Phone',
            value: profile.phone.isEmpty ? 'Not added yet' : profile.phone,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class _ProfileTrustCard extends StatelessWidget {
  final SenderMobileProfileData profile;
  final VoidCallback onViewDetails;
  final VoidCallback onViewHistory;

  const _ProfileTrustCard({
    required this.profile,
    required this.onViewDetails,
    required this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) {
    final progressCopy = !profile.hasTrustScore
        ? 'Trust progress unavailable'
        : profile.nextTierLabel == null
            ? 'Highest Circum tier reached'
            : '${profile.pointsToNextTier} Trust Points until ${profile.nextTierLabel}';
    return _ProfileGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _ProfileTokens.accent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _ProfileTokens.accent.withValues(alpha: .35),
                  ),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: _ProfileTokens.lightAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trust',
                      style: GoogleFonts.dmSerifDisplay(
                        color: Colors.white,
                        fontSize: 24,
                      ),
                    ),
                    Text(
                      'Your standing across Circum',
                      style: GoogleFonts.inter(
                        color: _ProfileTokens.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _TrustMetric(
                label: 'Current tier',
                value: profile.trustTierLabel,
                compact: true,
              ),
              _TrustMetric(
                label: 'Trust Score',
                value: profile.trustScoreLabel,
                compact: true,
              ),
              _TrustMetric(
                label: 'Deliveries completed',
                value: profile.completedDeliveriesLabel,
                compact: true,
              ),
              _TrustMetric(
                label: 'Member since',
                value: profile.memberSinceValue,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _TrustProgress(
            value: profile.hasTrustScore ? profile.trustProgress : 0,
            label: progressCopy,
          ),
          const SizedBox(height: 20),
          Text(
            'Recent Trust Activity',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (profile.trustHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'No recent trust activity.',
                style: GoogleFonts.inter(
                  color: _ProfileTokens.muted,
                  fontSize: 12,
                ),
              ),
            )
          else
            ...profile.trustHistory.take(3).map(_TrustActivityRow.new),
          const SizedBox(height: 8),
          _TrustTextAction(
            label: 'View Full History',
            onTap: onViewHistory,
          ),
          _TrustTextAction(
            label: 'View Trust Details →',
            onTap: onViewDetails,
          ),
        ],
      ),
    );
  }
}

class _TrustMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool compact;

  const _TrustMetric({
    required this.label,
    required this.value,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 132 : null,
      constraints: const BoxConstraints(minHeight: 70),
      padding: EdgeInsets.all(compact ? 11 : 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ProfileTokens.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: _ProfileTokens.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: compact ? 17 : 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustProgress extends StatelessWidget {
  final double value;
  final String label;

  const _TrustProgress({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: '${(value * 100).round()} percent',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: value,
              backgroundColor: Colors.white.withValues(alpha: .08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                _ProfileTokens.lightAccent,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: GoogleFonts.inter(
              color: _ProfileTokens.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustActivityRow extends StatelessWidget {
  final SenderTrustActivity activity;

  const _TrustActivityRow(this.activity);

  @override
  Widget build(BuildContext context) {
    final positive = activity.points >= 0;
    final points =
        activity.points == 0 ? '—' : '${positive ? '+' : ''}${activity.points}';
    return Semantics(
      label: '$points ${activity.label}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _ProfileTokens.border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Text(
                points,
                style: GoogleFonts.jetBrainsMono(
                  color: positive
                      ? const Color(0xFF86EFAC)
                      : const Color(0xFFFCA5A5),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.label,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (activity.occurredAt != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      _profileDateLabel(activity.occurredAt!),
                      style: GoogleFonts.inter(
                        color: _ProfileTokens.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustTextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TrustTextAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: _ProfileTokens.lightAccent,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileDetail extends StatelessWidget {
  final String label;
  final String value;
  final bool showDivider;

  const _ProfileDetail({
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: _ProfileTokens.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, color: _ProfileTokens.border),
      ],
    );
  }
}

class _SenderSettingsShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _SenderSettingsShell({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(title, style: GoogleFonts.dmSerifDisplay()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(
              subtitle,
              style: GoogleFonts.inter(
                color: _ProfileTokens.muted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SenderSecuritySettingsScreen extends StatefulWidget {
  const _SenderSecuritySettingsScreen();

  @override
  State<_SenderSecuritySettingsScreen> createState() =>
      _SenderSecuritySettingsScreenState();
}

class _SenderSecuritySettingsScreenState
    extends State<_SenderSecuritySettingsScreen> {
  bool _twoFactorEnabled = false;
  bool _biometricsEnabled = false;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final biometricLabel =
        platform == TargetPlatform.iOS ? 'Face ID / Touch ID' : 'Fingerprint';
    return _SenderSettingsShell(
      title: 'Security',
      subtitle: 'Manage sign-in, account protection and signed-in devices.',
      children: [
        _ProfileGlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _SettingsActionRow(
                icon: Icons.password_rounded,
                title: 'Password',
                subtitle: 'Change password',
                onTap: () => _showPending(context, 'Change password'),
              ),
              _SettingsSwitchRow(
                icon: Icons.verified_user_outlined,
                title: 'Two-Factor Authentication',
                subtitle: _twoFactorEnabled ? 'Disable 2FA' : 'Enable 2FA',
                value: _twoFactorEnabled,
                onChanged: (value) => setState(() {
                  _twoFactorEnabled = value;
                }),
              ),
              _SettingsSwitchRow(
                icon: Icons.fingerprint_rounded,
                title: 'Biometrics',
                subtitle: biometricLabel,
                value: _biometricsEnabled,
                onChanged: (value) => setState(() {
                  _biometricsEnabled = value;
                }),
              ),
              _SettingsActionRow(
                icon: Icons.devices_other_rounded,
                title: 'Active Devices',
                subtitle: 'This device · Manage signed-in sessions',
                onTap: () => _showActiveDevices(context),
              ),
              _SettingsActionRow(
                icon: Icons.alternate_email_rounded,
                title: 'Email Address',
                subtitle: 'Change email',
                onTap: () => _showPending(context, 'Change email'),
              ),
              _SettingsActionRow(
                icon: Icons.phone_iphone_rounded,
                title: 'Phone Number',
                subtitle: 'Change phone number',
                onTap: () => _showPending(context, 'Change phone number'),
                showDivider: false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showActiveDevices(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _ProfileTokens.panel,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Active Devices',
                style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 14),
              _ProfileGlassCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.smartphone_rounded,
                      color: _ProfileTokens.lightAccent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This device\nCurrent session',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          height: 1.35,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _showPending(
                        context,
                        'Sign out this device',
                      ),
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: _secondaryButtonStyle(),
                onPressed: () => _showPending(
                  context,
                  'Sign out all other devices',
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out all other devices'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SenderLanguageSettingsScreen extends StatefulWidget {
  const _SenderLanguageSettingsScreen();

  @override
  State<_SenderLanguageSettingsScreen> createState() =>
      _SenderLanguageSettingsScreenState();
}

class _SenderLanguageSettingsScreenState
    extends State<_SenderLanguageSettingsScreen> {
  String _language = 'Device Default';
  String _timeFormat = 'Automatic';

  @override
  Widget build(BuildContext context) {
    return _SenderSettingsShell(
      title: 'Language',
      subtitle:
          'Choose app language preferences where Circum localisation is available.',
      children: [
        const _ProfileSectionTitle(title: 'App Language'),
        const SizedBox(height: 10),
        _SettingsChoiceCard<String>(
          value: _language,
          options: const ['Device Default', 'English'],
          onChanged: (value) => setState(() {
            _language = value;
          }),
        ),
        const SizedBox(height: 20),
        const _ProfileSectionTitle(title: 'Region'),
        const SizedBox(height: 10),
        const _ProfileGlassCard(
          child: _SettingsStaticRow(
            icon: Icons.public_rounded,
            title: 'Region',
            subtitle: 'Uses device region by default',
          ),
        ),
        const SizedBox(height: 20),
        const _ProfileSectionTitle(title: 'Date & Time Format'),
        const SizedBox(height: 10),
        _SettingsChoiceCard<String>(
          value: _timeFormat,
          options: const ['Automatic', '12-hour', '24-hour'],
          onChanged: (value) => setState(() {
            _timeFormat = value;
          }),
        ),
      ],
    );
  }
}

class _SenderAccessibilitySettingsScreen extends StatefulWidget {
  const _SenderAccessibilitySettingsScreen();

  @override
  State<_SenderAccessibilitySettingsScreen> createState() =>
      _SenderAccessibilitySettingsScreenState();
}

class _SenderAccessibilitySettingsScreenState
    extends State<_SenderAccessibilitySettingsScreen> {
  String _appearance = 'Follow System';
  String _textSize = 'Default';
  bool _highContrast = false;
  bool _reduceMotion = false;
  bool _screenReaderOptimisations = false;

  @override
  Widget build(BuildContext context) {
    return _SenderSettingsShell(
      title: 'Accessibility',
      subtitle: 'Tune the visual and motion experience for your needs.',
      children: [
        const _ProfileSectionTitle(title: 'Appearance'),
        const SizedBox(height: 10),
        _SettingsChoiceCard<String>(
          value: _appearance,
          options: const ['Follow System', 'Dark', 'Light'],
          onChanged: (value) => setState(() {
            _appearance = value;
          }),
        ),
        const SizedBox(height: 20),
        const _ProfileSectionTitle(title: 'Text Size'),
        const SizedBox(height: 10),
        _SettingsChoiceCard<String>(
          value: _textSize,
          options: const ['Small', 'Default', 'Large'],
          onChanged: (value) => setState(() {
            _textSize = value;
          }),
        ),
        const SizedBox(height: 20),
        _ProfileGlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _SettingsSwitchRow(
                icon: Icons.contrast_rounded,
                title: 'High Contrast',
                subtitle: _highContrast ? 'On' : 'Off',
                value: _highContrast,
                onChanged: (value) => setState(() {
                  _highContrast = value;
                }),
              ),
              _SettingsSwitchRow(
                icon: Icons.motion_photos_off_rounded,
                title: 'Reduce Motion',
                subtitle: _reduceMotion ? 'On' : 'Off',
                value: _reduceMotion,
                onChanged: (value) => setState(() {
                  _reduceMotion = value;
                }),
              ),
              _SettingsSwitchRow(
                icon: Icons.record_voice_over_rounded,
                title: 'Screen Reader Optimisations',
                subtitle: _screenReaderOptimisations ? 'On' : 'Off',
                value: _screenReaderOptimisations,
                onChanged: (value) => setState(() {
                  _screenReaderOptimisations = value;
                }),
                showDivider: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SenderSubmissionInfo {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SenderSubmissionInfo({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class _SenderClosedSubmissionScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final String topic;
  final String messageLabel;
  final String messageHint;
  final String submitLabel;
  final String successMessage;
  final List<_SenderSubmissionInfo> rows;

  const _SenderClosedSubmissionScreen({
    required this.title,
    required this.subtitle,
    required this.topic,
    required this.messageLabel,
    required this.messageHint,
    required this.submitLabel,
    required this.successMessage,
    required this.rows,
  });

  @override
  State<_SenderClosedSubmissionScreen> createState() =>
      _SenderClosedSubmissionScreenState();
}

class _SenderClosedSubmissionScreenState
    extends State<_SenderClosedSubmissionScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _controller.text.trim();
    if (message.isEmpty || _sending) return;
    setState(() => _sending = true);
    final user = FirebaseAuth.instance.currentUser;
    final identity = [
      if ((user?.displayName ?? '').trim().isNotEmpty)
        'Name: ${user!.displayName!.trim()}',
      if ((user?.email ?? '').trim().isNotEmpty)
        'Email: ${user!.email!.trim()}',
      if ((user?.uid ?? '').trim().isNotEmpty) 'UID: ${user!.uid}',
    ].join('\n');
    final body = [
      widget.title,
      if (identity.isNotEmpty) identity,
      'Message:',
      message,
    ].join('\n\n');
    try {
      await FirebaseFunctions.instance
          .httpsCallable('getOrCreateSupportConversation')
          .call({
        'topic': widget.topic,
        'title': widget.title,
        'participantRole': 'sender',
        'initialMessage': body,
        'closeImmediately': true,
        if ((user?.displayName ?? '').trim().isNotEmpty)
          'displayName': user!.displayName!.trim(),
      });
      if (!mounted) return;
      _controller.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.successMessage)),
      );
      Navigator.of(context).pop();
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Message could not be sent.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SenderSettingsShell(
      title: widget.title,
      subtitle: widget.subtitle,
      children: [
        _ProfileGlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: widget.rows
                .map((row) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: _SettingsStaticRow(
                        icon: row.icon,
                        title: row.title,
                        subtitle: row.subtitle,
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          minLines: 5,
          maxLines: 8,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration(widget.messageLabel).copyWith(
            hintText: widget.messageHint,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: Key('sender-${widget.topic}-closed-submit'),
          onPressed: _sending ? null : _submit,
          icon: _sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
          label: Text(_sending ? 'Sending...' : widget.submitLabel),
        ),
      ],
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  const _SettingsActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return _ProfileShortcut(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      showDivider: showDivider,
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  const _SettingsSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          button: true,
          toggled: value,
          label: '$title. $subtitle',
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _ProfileTokens.accent.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: _ProfileTokens.accent.withValues(alpha: .3),
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: _ProfileTokens.lightAccent,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            color: _ProfileTokens.muted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: value,
                    activeThumbColor: _ProfileTokens.lightAccent,
                    onChanged: onChanged,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider) const Divider(height: 1, color: _ProfileTokens.border),
      ],
    );
  }
}

class _SettingsStaticRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SettingsStaticRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _ProfileTokens.lightAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  color: _ProfileTokens.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsChoiceCard<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final ValueChanged<T> onChanged;

  const _SettingsChoiceCard({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _ProfileGlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < options.length; index++)
            _SettingsChoiceRow<T>(
              label: options[index].toString(),
              value: options[index],
              groupValue: value,
              onChanged: onChanged,
              showDivider: index != options.length - 1,
            ),
        ],
      ),
    );
  }
}

class _SettingsChoiceRow<T> extends StatelessWidget {
  final String label;
  final T value;
  final T groupValue;
  final ValueChanged<T> onChanged;
  final bool showDivider;

  const _SettingsChoiceRow({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Column(
      children: [
        Semantics(
          button: true,
          selected: selected,
          label: label,
          child: InkWell(
            onTap: () => onChanged(value),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected
                          ? _ProfileTokens.lightAccent
                          : _ProfileTokens.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showDivider) const Divider(height: 1, color: _ProfileTokens.border),
      ],
    );
  }
}

void _showPending(BuildContext context, String action) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$action is being prepared.')),
  );
}

class _ProfileShortcut extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;
  final bool danger;

  const _ProfileShortcut({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = true,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          button: true,
          label: '$title. $subtitle',
          child: InkWell(
            onTap: onTap,
            hoverColor: _ProfileTokens.accent.withValues(alpha: .055),
            focusColor: _ProfileTokens.accent.withValues(alpha: .09),
            highlightColor: _ProfileTokens.accent.withValues(alpha: .08),
            splashColor: _ProfileTokens.accent.withValues(alpha: .12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _ProfileTokens.accent.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: _ProfileTokens.accent.withValues(alpha: .24),
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: danger
                            ? const Color(0xFFFCA5A5)
                            : _ProfileTokens.lightAccent,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: GoogleFonts.inter(
                              color: _ProfileTokens.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _ProfileTokens.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showDivider) const Divider(height: 1, color: _ProfileTokens.border),
      ],
    );
  }
}

class _ProfileSectionTitle extends StatelessWidget {
  final String title;

  const _ProfileSectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ProfileSectionTitleRow extends StatelessWidget {
  final String title;

  const _ProfileSectionTitleRow({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final SenderMobileProfileData profile;
  final bool uploading;
  final VoidCallback onUpload;

  const _ProfileAvatar({
    required this.profile,
    required this.uploading,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final initial = profile.displayName.trim().isEmpty
        ? 'S'
        : profile.displayName.trim().characters.first.toUpperCase();
    return Semantics(
      image: true,
      label: 'Profile photo',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .06),
              border: Border.all(color: _ProfileTokens.border),
            ),
            child: CircleAvatar(
              radius: 54,
              backgroundColor: _ProfileTokens.accent.withValues(alpha: .16),
              backgroundImage: profile.photoUrl.isEmpty
                  ? null
                  : NetworkImage(profile.photoUrl),
              child: profile.photoUrl.isEmpty
                  ? Text(
                      initial,
                      style: GoogleFonts.dmSerifDisplay(
                        color: Colors.white,
                        fontSize: 40,
                      ),
                    )
                  : null,
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Semantics(
              button: true,
              label: 'Upload profile photo',
              child: Tooltip(
                message: 'Upload profile photo',
                child: InkWell(
                  key: const Key('sender-profile-photo-upload'),
                  customBorder: const CircleBorder(),
                  onTap: uploading ? null : onUpload,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _ProfileTokens.panel,
                      shape: BoxShape.circle,
                      border: Border.all(color: _ProfileTokens.border),
                    ),
                    child: uploading
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _ProfileTokens.lightAccent,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_outlined,
                            color: _ProfileTokens.lightAccent,
                            size: 17,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTypeBadge extends StatelessWidget {
  final String memberSinceLabel;

  const _AccountTypeBadge({required this.memberSinceLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: _ProfileTokens.accent.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _ProfileTokens.accent.withValues(alpha: .35),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Circum Account',
            style: GoogleFonts.jetBrainsMono(
              color: _ProfileTokens.lightAccent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            memberSinceLabel,
            style: GoogleFonts.inter(
              color: _ProfileTokens.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileLoadingState extends StatelessWidget {
  const _ProfileLoadingState();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading profile',
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 96),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 130,
                  height: 34,
                  alignment: Alignment.centerLeft,
                  child: _ProfileSkeleton(width: 112, height: 26),
                ),
                const SizedBox(height: 18),
                const _ProfileGlassCard(
                  child: Column(
                    children: [
                      _ProfileSkeleton(width: 104, height: 104, circular: true),
                      SizedBox(height: 18),
                      _ProfileSkeleton(width: 180, height: 18),
                      SizedBox(height: 10),
                      _ProfileSkeleton(width: 220, height: 13),
                      SizedBox(height: 24),
                      _ProfileSkeleton(width: double.infinity, height: 52),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const _ProfileGlassCard(
                  child: Column(
                    children: [
                      _ProfileSkeleton(width: double.infinity, height: 58),
                      SizedBox(height: 10),
                      _ProfileSkeleton(width: double.infinity, height: 58),
                      SizedBox(height: 10),
                      _ProfileSkeleton(width: double.infinity, height: 58),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  final double width;
  final double height;
  final bool circular;

  const _ProfileSkeleton({
    required this.width,
    required this.height,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .07),
          shape: circular ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circular ? null : BorderRadius.circular(10),
          border: Border.all(color: _ProfileTokens.border),
        ),
      );
}

class _TrustDetailsSheet extends StatelessWidget {
  final SenderMobileProfileData profile;

  const _TrustDetailsSheet({required this.profile});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trust details',
                style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white,
                  fontSize: 26,
                ),
              ),
              const SizedBox(height: 14),
              _ProfileDetail(
                label: 'Current tier',
                value: profile.trustTierLabel,
              ),
              _ProfileDetail(
                label: 'Trust Score',
                value: profile.trustScoreLabel,
              ),
              _ProfileDetail(
                label: 'Deliveries completed',
                value: profile.completedDeliveriesLabel,
                showDivider: false,
              ),
              const SizedBox(height: 16),
              Text(
                'Trust Score reflects all qualifying account activity. '
                'Deliveries completed counts completed delivery records only, '
                'so these totals may change independently.',
                style: GoogleFonts.inter(
                  color: _ProfileTokens.muted,
                  height: 1.45,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      );
}

class _TrustHistorySheet extends StatelessWidget {
  final List<SenderTrustActivity> activities;

  const _TrustHistorySheet({required this.activities});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trust history',
                style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white,
                  fontSize: 26,
                ),
              ),
              const SizedBox(height: 12),
              if (activities.isEmpty)
                Text(
                  'No trust activity yet.',
                  style: GoogleFonts.inter(color: _ProfileTokens.muted),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: activities.map(_TrustActivityRow.new).toList(),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _SenderLegalDocumentScreen extends StatelessWidget {
  final String title;

  const _SenderLegalDocumentScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    final isTerms = title == 'Terms';
    final uri = Uri.parse(
      isTerms ? 'https://circumuk.com/terms' : 'https://circumuk.com/privacy',
    );
    return _SenderSettingsShell(
      title: title,
      subtitle: isTerms
          ? 'Review the terms that apply to your Circum account.'
          : 'Learn how Circum uses and protects your information.',
      children: [
        _ProfileGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isTerms
                    ? Icons.description_outlined
                    : Icons.privacy_tip_outlined,
                color: _ProfileTokens.lightAccent,
                size: 30,
              ),
              const SizedBox(height: 14),
              Text(
                isTerms ? 'Circum Terms of Service' : 'Circum Privacy Policy',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The latest policy is available on circumuk.com.',
                style: GoogleFonts.inter(color: _ProfileTokens.muted),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => launchUrl(uri),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(isTerms ? 'View Terms' : 'View Privacy Policy'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileErrorState extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;

  const _ProfileErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: _ProfileGlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: _ProfileTokens.lightAccent,
                size: 38,
              ),
              const SizedBox(height: 14),
              Text(
                'Profile unavailable',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message ?? 'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: _ProfileTokens.muted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileMessage extends StatelessWidget {
  final String message;

  const _ProfileMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0x22F87171),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x55F87171)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFFCA5A5),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(color: const Color(0xFFFECACA)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _ProfileGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: AppGlassContainer(
          padding: padding,
          radius: AppTokens.radius22,
          accent: AppTokens.primary,
          child: child,
        ),
      );
}

InputDecoration _fieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.inter(color: _ProfileTokens.muted),
    hintStyle: GoogleFonts.inter(color: _ProfileTokens.muted),
    filled: true,
    fillColor: Colors.white.withValues(alpha: .035),
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _ProfileTokens.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _ProfileTokens.accent, width: 1.5),
    ),
  );
}

ButtonStyle _secondaryButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(52),
    side: const BorderSide(color: _ProfileTokens.border),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}

class _ProfileTokens {
  static const panel = Color(0xFF0D111C);
  static const accent = Color(0xFF3B82F6);
  static const lightAccent = Color(0xFF60A5FA);
  static const muted = Color(0xFF9CA3AF);
  static const border = Color(0x29FFFFFF);
}

String _profileDateLabel(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}
