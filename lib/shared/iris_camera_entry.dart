import 'package:flutter/material.dart';

enum IrisCameraState {
  idle,
  permissionRequired,
  capturing,
  uploading,
  analysing,
  completed,
  failed,
}

class IrisCameraEntry extends StatelessWidget {
  final IrisCameraState state;
  final bool hasPhoto;
  final Future<void> Function() onTakePhoto;
  final Future<void> Function() onChoosePhoto;
  final VoidCallback? onRemove;
  final VoidCallback? onRetry;

  const IrisCameraEntry({
    super.key,
    required this.state,
    required this.hasPhoto,
    required this.onTakePhoto,
    required this.onChoosePhoto,
    this.onRemove,
    this.onRetry,
  });

  bool get _busy => const {
        IrisCameraState.capturing,
        IrisCameraState.uploading,
        IrisCameraState.analysing,
      }.contains(state);

  Future<void> _openChoices(BuildContext context) async {
    if (_busy) return;
    if (state == IrisCameraState.failed && onRetry != null) {
      onRetry!();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take Photo'),
                textColor: Colors.white,
                iconColor: const Color(0xFF60A5FA),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onTakePhoto();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose Photo'),
                textColor: Colors.white,
                iconColor: const Color(0xFFA78BFA),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onChoosePhoto();
                },
              ),
              if (hasPhoto && onRemove != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Remove Photo'),
                  textColor: Colors.white,
                  iconColor: const Color(0xFFFCA5A5),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onRemove!();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      IrisCameraState.permissionRequired =>
        'Camera permission required. Add parcel photo for IRIS verification',
      IrisCameraState.capturing => 'Capturing parcel photo',
      IrisCameraState.uploading => 'Uploading parcel photo',
      IrisCameraState.analysing => 'Verifying parcel photo with IRIS',
      IrisCameraState.completed => 'Parcel photo added for IRIS verification',
      IrisCameraState.failed => 'Retry parcel photo for IRIS verification',
      IrisCameraState.idle => 'Add parcel photo for IRIS verification',
    };
    return Semantics(
      button: true,
      enabled: !_busy,
      label: label,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: _busy ? null : () => _openChoices(context),
          radius: 30,
          child: Container(
            key: const ValueKey('iris-camera-entry'),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: state == IrisCameraState.failed
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFF818CF8),
                width: 1.4,
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x334F46E5), blurRadius: 14),
              ],
            ),
            child: _busy
                ? const Padding(
                    padding: EdgeInsets.all(15),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF60A5FA),
                    ),
                  )
                : hasPhoto && state != IrisCameraState.failed
                    ? const Icon(
                        Icons.check_circle_outline,
                        color: Color(0xFF86EFAC),
                        size: 24,
                      )
                    : const _IrisCameraGlyph(),
          ),
        ),
      ),
    );
  }
}

class _IrisCameraGlyph extends StatelessWidget {
  const _IrisCameraGlyph();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(
          Icons.camera_alt_outlined,
          color: Color(0xFFE0E7FF),
          size: 27,
        ),
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF38BDF8), Color(0xFFA78BFA)],
            ),
            boxShadow: [
              BoxShadow(color: Color(0x994F46E5), blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(
          width: 17,
          height: 17,
          child: CircularProgressIndicator(
            value: .72,
            strokeWidth: 1.2,
            color: Color(0xFF60A5FA),
          ),
        ),
      ],
    );
  }
}
