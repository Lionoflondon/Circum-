import 'gifts_social_policy.dart';

const giftStoryMaxSlides = 16;
const giftStorySourcePath = 'story/source';
const giftStorySilentExportPath = 'story/exports/silent';
const giftStorySoundExportPath = 'story/exports/sound';
const giftStoryThumbPath = 'story/thumbs';

enum GiftStorySkin {
  iridescent('iridescent'),
  pink('pink'),
  blue('blue'),
  classicDark('classic_dark');

  final String value;
  const GiftStorySkin(this.value);

  static GiftStorySkin fromValue(Object? value) {
    final clean = '$value'.trim().toLowerCase().replaceAll('-', '_');
    return GiftStorySkin.values.firstWhere(
      (skin) => skin.value == clean || skin.name.toLowerCase() == clean,
      orElse: () => GiftStorySkin.iridescent,
    );
  }
}

enum GiftStorySlideType {
  arrival('arrival'),
  note('note'),
  voiceNote('voice_note'),
  giftReveal('gift_reveal'),
  whyChosen('why_chosen'),
  finale('finale');

  final String value;
  const GiftStorySlideType(this.value);
}

class GiftStorySlide {
  final GiftStorySlideType type;
  final String eyebrow;
  final String headline;
  final String body;
  final String? mediaUrl;
  final int durationMs;

  const GiftStorySlide({
    required this.type,
    required this.eyebrow,
    required this.headline,
    required this.body,
    this.mediaUrl,
    this.durationMs = 5200,
  });

  Map<String, Object?> toMap() => {
        'type': type.value,
        'eyebrow': eyebrow,
        'headline': headline,
        'body': body,
        if (mediaUrl != null && mediaUrl!.trim().isNotEmpty)
          'mediaUrl': mediaUrl,
        'durationMs': durationMs,
      };
}

class GiftStoryStudioPolicy {
  static const supportedSkins = [
    'iridescent',
    'pink',
    'blue',
    'classic_dark',
  ];

  static String sourceMediaPath(String giftId, String fileName) =>
      'gifts/$giftId/$giftStorySourcePath/$fileName';

  static String thumbnailPath(String giftId, String fileName) =>
      'gifts/$giftId/$giftStoryThumbPath/$fileName';

  static String silentExportPath(String giftId, String fileName) =>
      'gifts/$giftId/$giftStorySilentExportPath/$fileName';

  static String soundExportPath(String giftId, String fileName) =>
      'gifts/$giftId/$giftStorySoundExportPath/$fileName';

  static List<GiftStorySlide> buildSlides({
    required String recipientName,
    required String senderName,
    required String senderNote,
    String? senderVoiceNoteUrl,
    required Iterable<Map<String, Object?>> giftItems,
    bool canRevealSender = true,
  }) {
    final safeRecipient =
        recipientName.trim().isEmpty ? 'there' : recipientName.trim();
    final safeSender = canRevealSender && senderName.trim().isNotEmpty
        ? senderName.trim()
        : 'Someone special';
    final slides = <GiftStorySlide>[
      GiftStorySlide(
        type: GiftStorySlideType.arrival,
        eyebrow: 'GIFTS BY CIRCUM',
        headline: 'Your gift has arrived, $safeRecipient.',
        body: 'A small story before the reveal.',
      ),
      if ((senderVoiceNoteUrl ?? '').trim().isNotEmpty)
        GiftStorySlide(
          type: GiftStorySlideType.voiceNote,
          eyebrow: 'A voice note',
          headline: 'A message was left for you.',
          body: 'Tap sound to hear the note when this story plays.',
          mediaUrl: senderVoiceNoteUrl,
        )
      else
        GiftStorySlide(
          type: GiftStorySlideType.note,
          eyebrow: 'A note',
          headline: senderNote.trim().isEmpty
              ? 'This was chosen with care.'
              : senderNote.trim(),
          body: 'From $safeSender',
        ),
    ];

    for (final item in giftItems) {
      if (slides.length >= giftStoryMaxSlides - 1) break;
      final name = '${item['name'] ?? item['title'] ?? 'Your gift'}'.trim();
      final why = '${item['why'] ?? item['whyChosen'] ?? ''}'.trim();
      final mediaUrl = '${item['mediaUrl'] ?? item['imageUrl'] ?? ''}'.trim();
      slides.add(GiftStorySlide(
        type: GiftStorySlideType.giftReveal,
        eyebrow: 'The reveal',
        headline: name.isEmpty ? 'Your gift' : name,
        body: 'Chosen, prepared, and delivered for this moment.',
        mediaUrl: mediaUrl.isEmpty ? null : mediaUrl,
      ));
      if (slides.length >= giftStoryMaxSlides - 1) break;
      slides.add(GiftStorySlide(
        type: GiftStorySlideType.whyChosen,
        eyebrow: 'Why we chose it',
        headline: why.isEmpty ? 'Because it felt like you.' : why,
        body:
            'The Gifts Team shaped this around the intention behind the gift.',
      ));
    }

    slides.add(const GiftStorySlide(
      type: GiftStorySlideType.finale,
      eyebrow: 'Finale',
      headline: 'Tell sender thank you',
      body:
          'Replay story. Keep this story in the Circum app. Download Circum to save your gift story, replay it anytime, and keep thank-you messages in one place.',
    ));
    return slides.take(giftStoryMaxSlides).toList(growable: false);
  }

  static Map<String, Object?> studioPatch({
    required String giftId,
    required GiftStorySkin skin,
    required Iterable<GiftStorySlide> slides,
    bool silentVersion = true,
    bool soundVersion = false,
    String? silentVersionUrl,
    String? soundVersionUrl,
    String? musicVideoStatus,
    String? musicVideoPath,
    Object? updatedAt,
  }) {
    final capped = slides.take(giftStoryMaxSlides).map((s) => s.toMap());
    return {
      'giftStorySkin': skin.value,
      'giftStorySlides': capped.toList(growable: false),
      'giftStorySilentVersionUrl': silentVersion ? silentVersionUrl : null,
      'giftStorySoundVersionUrl': soundVersion ? soundVersionUrl : null,
      'giftStoryMusicVideoStatus': musicVideoStatus ?? 'not_requested',
      'giftStoryMusicVideoPath': musicVideoPath,
      'giftStoryStoragePaths': {
        'source': 'gifts/$giftId/$giftStorySourcePath/',
        'silent': 'gifts/$giftId/$giftStorySilentExportPath/',
        'sound': 'gifts/$giftId/$giftStorySoundExportPath/',
        'thumbs': 'gifts/$giftId/$giftStoryThumbPath/',
      },
      if (updatedAt != null) 'giftStoryUpdatedAt': updatedAt,
    };
  }

  static bool canRevealSender(Map<String, dynamic> gift) =>
      GiftsSocialPolicy.canRevealSender(gift);
}
