import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class DeliveryEvidencePhoto extends StatefulWidget {
  final String? legacyUrl;
  final String? storagePath;
  final double? width;
  final BoxFit fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const DeliveryEvidencePhoto({
    super.key,
    this.legacyUrl,
    this.storagePath,
    this.width,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  @override
  State<DeliveryEvidencePhoto> createState() => _DeliveryEvidencePhotoState();
}

class _DeliveryEvidencePhotoState extends State<DeliveryEvidencePhoto> {
  late Future<String?> _url;

  @override
  void initState() {
    super.initState();
    _url = _resolve();
  }

  @override
  void didUpdateWidget(covariant DeliveryEvidencePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.legacyUrl != widget.legacyUrl ||
        oldWidget.storagePath != widget.storagePath) {
      _url = _resolve();
    }
  }

  Future<String?> _resolve() async {
    final legacy = (widget.legacyUrl ?? '').trim();
    if (legacy.isNotEmpty) return legacy;
    final path = (widget.storagePath ?? '').trim();
    if (path.isEmpty) return null;
    return FirebaseStorage.instance.ref(path).getDownloadURL();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final url = snapshot.data;
        if (url == null || url.isEmpty || snapshot.hasError) {
          return widget.errorBuilder?.call(
                context,
                snapshot.error ?? StateError('Evidence photo unavailable'),
                snapshot.stackTrace,
              ) ??
              const Center(child: Icon(Icons.broken_image_outlined));
        }
        return Image.network(url, width: widget.width, fit: widget.fit, errorBuilder: widget.errorBuilder);
      },
    );
  }
}
