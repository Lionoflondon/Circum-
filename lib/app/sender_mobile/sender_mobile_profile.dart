import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

class SenderMobileProfileData {
  final String userId;
  final String displayName;
  final String email;
  final String phone;
  final String photoUrl;
  final String accountType;
  final DateTime? createdAt;

  const SenderMobileProfileData({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.phone,
    required this.photoUrl,
    this.accountType = 'sender',
    this.createdAt,
  });

  factory SenderMobileProfileData.fromSources({
    required User user,
    Map<String, dynamic>? data,
  }) {
    final profile = data ?? const <String, dynamic>{};
    return SenderMobileProfileData(
      userId: user.uid,
      displayName: _firstText([
        profile['displayName'],
        profile['fullName'],
        profile['fullname'],
        profile['name'],
        user.displayName,
      ]),
      email: _firstText([profile['email'], user.email]),
      phone: _firstText([
        profile['phone'],
        profile['phoneNumber'],
        user.phoneNumber,
      ]),
      photoUrl: _firstText([
        profile['photoURL'],
        profile['photoUrl'],
        user.photoURL,
      ]),
      accountType: 'sender',
      createdAt:
          _profileDate(profile['createdAt']) ?? user.metadata.creationTime,
    );
  }

  String get memberSinceYear => '${createdAt?.year ?? DateTime.now().year}';

  static DateTime? _profileDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String _firstText(Iterable<Object?> values) {
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

  Future<SenderMobileProfileData> save({
    required String displayName,
    required String phone,
  });

  Future<SenderMobileProfileData> uploadPhoto(SenderProfilePhoto photo);

  Future<void> logout();
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

  FirebaseSenderMobileProfileRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        storage = storage ?? FirebaseStorage.instance;

  @override
  Future<SenderMobileProfileData> load() async {
    final user = auth.currentUser;
    if (user == null) {
      throw const SenderMobileProfileException(
        'Sign in again to load your profile.',
      );
    }
    final snapshot = await firestore.collection('users').doc(user.uid).get();
    return SenderMobileProfileData.fromSources(
      user: user,
      data: snapshot.data(),
    );
  }

  @override
  Future<SenderMobileProfileData> save({
    required String displayName,
    required String phone,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw const SenderMobileProfileException(
        'Sign in again before saving your profile.',
      );
    }
    final reference = firestore.collection('users').doc(user.uid);
    final existing = await reference.get();
    await reference.set({
      'displayName': displayName.trim(),
      'email': user.email?.trim() ?? '',
      'phone': phone.trim(),
      'photoURL': user.photoURL?.trim() ?? '',
      'accountType': 'sender',
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (user.displayName != displayName.trim()) {
      await user.updateDisplayName(displayName.trim());
    }
    return SenderMobileProfileData(
      userId: user.uid,
      displayName: displayName.trim(),
      email: user.email?.trim() ?? '',
      phone: phone.trim(),
      photoUrl: user.photoURL?.trim() ?? '',
      createdAt: existing.data()?['createdAt'] is Timestamp
          ? (existing.data()!['createdAt'] as Timestamp).toDate()
          : user.metadata.creationTime,
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
    await firestore.collection('users').doc(user.uid).set({
      'photoURL': downloadUrl,
      'accountType': 'sender',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await user.updatePhotoURL(downloadUrl);
    final current = await load();
    return SenderMobileProfileData(
      userId: current.userId,
      displayName: current.displayName,
      email: current.email,
      phone: current.phone,
      photoUrl: downloadUrl,
      createdAt: current.createdAt,
    );
  }

  @override
  Future<void> logout() => auth.signOut();
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

  const SenderMobileProfileView({
    super.key,
    this.repository,
    this.photoPicker,
    this.onLoggedOut,
  });

  @override
  State<SenderMobileProfileView> createState() =>
      _SenderMobileProfileViewState();
}

class _SenderMobileProfileViewState extends State<SenderMobileProfileView> {
  late final SenderMobileProfileRepository _repository;
  late final SenderProfilePhotoPicker _photoPicker;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  SenderMobileProfileData? _profile;
  String? _error;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseSenderMobileProfileRepository();
    _photoPicker = widget.photoPicker ?? ImagePickerSenderProfilePhotoPicker();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'We could not load your profile. Check your connection.';
      });
    }
  }

  void _applyProfile(SenderMobileProfileData profile) {
    _nameController.text = profile.displayName;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: Semantics(
          label: 'Loading profile',
          child: const CircularProgressIndicator(
            color: _ProfileTokens.accent,
          ),
        ),
      );
    }
    if (_profile == null) {
      return _ProfileErrorState(message: _error, onRetry: _load);
    }
    final profile = _profile!;
    return ListView(
      key: const Key('sender-profile-view'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
      children: [
        Row(
          children: [
            Text(
              'Profile',
              style: GoogleFonts.dmSerifDisplay(
                color: Colors.white,
                fontSize: 32,
              ),
            ),
            const Spacer(),
            if (!_editing)
              _ProfileIconButton(
                icon: Icons.edit_rounded,
                label: 'Edit profile',
                onTap: () => setState(() => _editing = true),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _ProfileGlassCard(
          child: Column(
            children: [
              _ProfileAvatar(
                profile: profile,
                uploading: _uploadingPhoto,
                onUpload: _uploadPhoto,
              ),
              const SizedBox(height: 14),
              Text(
                profile.displayName.isEmpty
                    ? 'Add your name'
                    : profile.displayName,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                profile.email.isEmpty ? 'Email unavailable' : profile.email,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: _ProfileTokens.muted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              _AccountTypeBadge(memberSinceYear: profile.memberSinceYear),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('sender-profile-primary-edit'),
                  onPressed:
                      _editing ? null : () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit Profile'),
                  style: _secondaryButtonStyle(),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ProfileMessage(message: _error!),
        ],
        const SizedBox(height: 16),
        if (_editing)
          _EditProfileCard(
            nameController: _nameController,
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
        else
          _ProfileDetailsCard(profile: profile),
        const SizedBox(height: 16),
        _ProfileGlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _ProfileShortcut(
                icon: Icons.location_on_outlined,
                title: 'Saved addresses',
                subtitle: 'Manage your saved pickup and delivery locations.',
                onTap: () => _showLocalMessage(
                  'Saved addresses will open here.',
                ),
              ),
              _ProfileShortcut(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Wallet',
                subtitle:
                    'Available soon · Manage your Roth balance and rewards.',
                onTap: () => _showLocalMessage('Wallet is available soon.'),
              ),
              _ProfileShortcut(
                icon: Icons.group_add_outlined,
                title: 'Referrals',
                subtitle: 'Invite friends and earn Roth rewards.',
                onTap: () => _showLocalMessage('Referrals are available soon.'),
                showDivider: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const _ProfileSectionTitle(title: 'Account'),
        const SizedBox(height: 10),
        _ProfileGlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _ProfileShortcut(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                subtitle: 'Choose how Circum keeps you informed.',
                onTap: () => _showLocalMessage(
                  'Notification preferences will open here.',
                ),
              ),
              _ProfileShortcut(
                icon: Icons.credit_card_rounded,
                title: 'Payment methods',
                subtitle: 'Manage saved payment methods.',
                onTap: () => _showLocalMessage(
                  'Payment methods will open here.',
                ),
              ),
              _ProfileShortcut(
                icon: Icons.lock_outline_rounded,
                title: 'Security',
                subtitle: 'Password and account protection.',
                onTap: () => _showLocalMessage('Security will open here.'),
              ),
              _ProfileShortcut(
                icon: Icons.language_rounded,
                title: 'Language',
                subtitle: 'Choose your preferred language.',
                onTap: () => _showLocalMessage('Language will open here.'),
              ),
              _ProfileShortcut(
                icon: Icons.accessibility_new_rounded,
                title: 'Accessibility',
                subtitle: 'Adjust your Circum experience.',
                onTap: () => _showLocalMessage(
                  'Accessibility settings will open here.',
                ),
                showDivider: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const _ProfileSectionTitle(title: 'Help'),
        const SizedBox(height: 10),
        _ProfileGlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _ProfileShortcut(
                icon: Icons.support_agent_rounded,
                title: 'Help & support',
                subtitle: 'Get help with your Circum account',
                onTap: () => _showLocalMessage(
                  'Help & support will open here.',
                ),
              ),
              _ProfileShortcut(
                icon: Icons.gavel_outlined,
                title: 'Legal',
                subtitle: 'Terms and Privacy',
                onTap: _showLegal,
                showDivider: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Semantics(
          button: true,
          label: 'Log out of Circum',
          child: OutlinedButton.icon(
            key: const Key('sender-profile-logout'),
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Log out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFCA5A5),
              minimumSize: const Size.fromHeight(54),
              side: const BorderSide(color: Color(0x66F87171)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showLocalMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showLegal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _ProfileTokens.panel,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProfileShortcut(
                icon: Icons.description_outlined,
                title: 'Terms',
                subtitle: 'Circum Terms of Service',
                onTap: () => Navigator.pop(context),
              ),
              _ProfileShortcut(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy',
                subtitle: 'Circum Privacy Policy',
                onTap: () => Navigator.pop(context),
                showDivider: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditProfileCard extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final String email;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _EditProfileCard({
    required this.nameController,
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

class _ProfileShortcut extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  const _ProfileShortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = true,
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
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _ProfileTokens.lightAccent,
                  Color(0xFF38BDF8),
                  _ProfileTokens.accent,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _ProfileTokens.accent.withValues(alpha: .28),
                  blurRadius: 24,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 52,
              backgroundColor: _ProfileTokens.accent,
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
  final String memberSinceYear;

  const _AccountTypeBadge({required this.memberSinceYear});

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
            'SENDER ACCOUNT',
            style: GoogleFonts.jetBrainsMono(
              color: _ProfileTokens.lightAccent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Member since $memberSinceYear',
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

class _ProfileIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ProfileIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon),
        color: Colors.white,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          backgroundColor: _ProfileTokens.glass,
          side: const BorderSide(color: _ProfileTokens.border),
        ),
      ),
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
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: _ProfileTokens.glass,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _ProfileTokens.border),
          ),
          child: child,
        ),
      ),
    );
  }
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
  static const glass = Color(0x0DF5F7FB);
}
