class GiftRepositoryItem {
  final String id;
  final String name;
  final String category;
  final String subcategory;
  final String description;
  final int estimatedPriceMin;
  final int estimatedPriceMax;
  final String priceBand;
  final List<String> suitableBudgets;
  final List<String> interests;
  final List<String> occasions;
  final List<String> relationships;
  final List<String> genderFit;
  final List<String> ageRanges;
  final List<String> styleTags;
  final List<String> allergyFlags;
  final List<String> medicalWarnings;
  final List<String> religiousConsiderations;
  final List<String> avoidIf;
  final List<String> goodFor;
  final int luxuryScore;
  final int sentimentScore;
  final int recoveryScore;
  final int romanceScore;
  final int practicalityScore;
  final int surpriseScore;
  final String supplierType;
  final String procurementDifficulty;
  final String? linkedBrandPartnerName;
  final String? supplierStatus;
  final String? wholesalePrice;
  final String? estimatedRrp;
  final String? marginProfile;
  final List<String> pairings;
  final List<String> phraseTriggers;
  final List<String> seasonalWeighting;
  final List<String> supplierRestrictions;
  final int recommendationScore;
  final int priceEfficiencyScore;
  final int packagingQualityScore;
  final int emotionalVersatilityScore;
  final int corporateSuitabilityScore;
  final int repeatPurchasePotentialScore;
  final bool active;
  final bool internalOnly;

  const GiftRepositoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.subcategory,
    required this.description,
    required this.estimatedPriceMin,
    required this.estimatedPriceMax,
    required this.priceBand,
    required this.suitableBudgets,
    required this.interests,
    required this.occasions,
    required this.relationships,
    required this.genderFit,
    required this.ageRanges,
    required this.styleTags,
    required this.allergyFlags,
    required this.medicalWarnings,
    required this.religiousConsiderations,
    required this.avoidIf,
    required this.goodFor,
    required this.luxuryScore,
    required this.sentimentScore,
    required this.recoveryScore,
    required this.romanceScore,
    required this.practicalityScore,
    required this.surpriseScore,
    required this.supplierType,
    required this.procurementDifficulty,
    this.linkedBrandPartnerName,
    this.supplierStatus,
    this.wholesalePrice,
    this.estimatedRrp,
    this.marginProfile,
    this.pairings = const [],
    this.phraseTriggers = const [],
    this.seasonalWeighting = const [],
    this.supplierRestrictions = const [],
    this.recommendationScore = 0,
    this.priceEfficiencyScore = 0,
    this.packagingQualityScore = 0,
    this.emotionalVersatilityScore = 0,
    this.corporateSuitabilityScore = 0,
    this.repeatPurchasePotentialScore = 0,
    this.active = true,
    this.internalOnly = true,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'subcategory': subcategory,
        'description': description,
        'estimatedPriceMin': estimatedPriceMin,
        'estimatedPriceMax': estimatedPriceMax,
        'priceBand': priceBand,
        'suitableBudgets': suitableBudgets,
        'interests': interests,
        'occasions': occasions,
        'relationships': relationships,
        'genderFit': genderFit,
        'ageRanges': ageRanges,
        'styleTags': styleTags,
        'allergyFlags': allergyFlags,
        'medicalWarnings': medicalWarnings,
        'religiousConsiderations': religiousConsiderations,
        'avoidIf': avoidIf,
        'goodFor': goodFor,
        'luxuryScore': luxuryScore,
        'sentimentScore': sentimentScore,
        'recoveryScore': recoveryScore,
        'romanceScore': romanceScore,
        'practicalityScore': practicalityScore,
        'surpriseScore': surpriseScore,
        'supplierType': supplierType,
        'procurementDifficulty': procurementDifficulty,
        if (linkedBrandPartnerName != null)
          'linkedBrandPartnerName': linkedBrandPartnerName,
        if (supplierStatus != null) 'supplierStatus': supplierStatus,
        if (wholesalePrice != null) 'wholesalePrice': wholesalePrice,
        if (estimatedRrp != null) 'estimatedRRP': estimatedRrp,
        if (marginProfile != null) 'marginProfile': marginProfile,
        'pairings': pairings,
        'phraseTriggers': phraseTriggers,
        'seasonalWeighting': seasonalWeighting,
        'supplierRestrictions': supplierRestrictions,
        'recommendationScore': recommendationScore,
        'priceEfficiencyScore': priceEfficiencyScore,
        'packagingQualityScore': packagingQualityScore,
        'emotionalVersatilityScore': emotionalVersatilityScore,
        'corporateSuitabilityScore': corporateSuitabilityScore,
        'repeatPurchasePotentialScore': repeatPurchasePotentialScore,
        'active': active,
        'internalOnly': internalOnly,
      };
}

class GiftRecommendationCandidate {
  final GiftRepositoryItem item;
  final int score;
  final List<String> reasons;
  final List<String> riskWarnings;

  const GiftRecommendationCandidate({
    required this.item,
    required this.score,
    required this.reasons,
    required this.riskWarnings,
  });

  Map<String, dynamic> toMap() => {
        'item': item.toMap(),
        'score': score,
        'reasons': reasons,
        'riskWarnings': riskWarnings,
      };
}

class GiftRecommendationResult {
  final String experienceSummary;
  final Map<String, num> budgetAllocation;
  final List<GiftRecommendationCandidate> topCandidates;
  final List<String> riskWarnings;
  final List<String> procurementNotes;

  const GiftRecommendationResult({
    required this.experienceSummary,
    required this.budgetAllocation,
    required this.topCandidates,
    required this.riskWarnings,
    required this.procurementNotes,
  });

  Map<String, dynamic> toMap() => {
        'experienceSummary': experienceSummary,
        'budgetAllocation': budgetAllocation,
        'topCandidates':
            topCandidates.map((candidate) => candidate.toMap()).toList(),
        'riskWarnings': riskWarnings,
        'procurementNotes': procurementNotes,
      };
}

const giftsExistingInterests = <String>{
  'Fashion',
  'Beauty',
  'Makeup',
  'Skincare',
  'Tech',
  'Gaming',
  'Gym',
  'Travel',
  'Books',
  'Food',
  'Cooking',
  'Coffee',
  'Tea',
  'Christian',
  'Muslim',
  'Jewish',
  'Spiritual',
  'Luxury',
  'Minimalist',
  'Home Decor',
  'Fragrance',
  'Charity',
  'Aviation',
  'Music',
  'Theatre',
  'Sports',
  'Football',
  'Running',
  'Cycling',
  'Swimming',
  'Art',
  'Design',
  'Architecture',
  'Photography',
  'Cars',
  'Motorcycles',
  'Gardening',
  'Film',
  'Jewellery',
  'Watches',
  'Writing',
  'Animals',
  'Nature',
  'Sustainability',
  'Collectibles',
};

const giftsExpandedInterests = <String>{
  ...giftsExistingInterests,
  'Restaurants',
  'Fine Dining',
  'Michelin Dining',
  'Street Food',
  'Brunch',
  'Afternoon Tea',
  'Luxury Travel',
  'City Breaks',
  'Adventure Travel',
  'Cruises',
  'Hotels',
  'Spa Experiences',
  'Wellness Retreats',
  'Luxury Fashion',
  'Streetwear',
  'Handbags',
  'Sneakers',
  'Interior Design',
  'Home Fragrance',
  'Musicals',
  'Opera',
  'Live Music',
  'Festivals',
  'Cinema',
  'TV & Streaming',
  'Business',
  'Entrepreneurship',
  'Investing',
  'Startups',
  'Personal Development',
  'Leadership',
  'Wine Appreciation',
  'Whisky Appreciation',
  'Craft Beverages',
  'Comfort',
  'Warmth',
  'Calm',
  'Relaxation',
  'Appreciation',
  'Birthday',
  'Thank You',
  'New Home',
  'Thinking of You',
  'Get Well Soon',
  'Anxiety Relief',
  'Self Care',
  'Mindfulness',
  'Burnout Recovery',
  'Exam Stress',
  'Mental Wellness',
  'Sympathy',
  'Recovery',
  'Wellness',
  'Celebration',
  'Romance',
  'Anniversary',
  'Congratulations',
  'Treat',
  'Indulgence',
  'Chocolate',
  'Cosy Evening',
  'Family',
  'Housewarming',
  'Retirement',
  'Grandparent Gift',
  'Biscuits',
  'Everyday Luxury',
  'Book Lover',
  'Office Worker',
  'Coffee Alternative',
  'Teacher Gift',
  'Mother’s Day',
  'Father’s Day',
  'Reading',
  'Autumn',
  'Christmas',
  'Winter',
  'Cosy',
  'Fireside',
  'Hygge',
  'Productivity',
  'Fitness',
  'New Job',
  'Promotion',
  'Entrepreneur',
  'Student',
  'Healthy Living',
  'Morning Routine',
  'Matcha Lover',
  'Matcha',
  'Premium Upgrade',
  'Tea Ritual',
  'Home Comfort',
  'Slow Morning',
};

const _occasions = <String>[
  'Birthday',
  'Christmas',
  'Anniversary',
  'Graduation',
  'Thank You',
  'New Baby',
  'Wedding',
  'Promotion',
  'Retirement',
  'Get Well Soon',
  'Just Because',
  'Apology',
];

const _relationships = <String>[
  'Partner',
  'Husband',
  'Wife',
  'Mother',
  'Father',
  'Son',
  'Daughter',
  'Brother',
  'Sister',
  'Friend',
  'Colleague',
  'Mentor',
  'Client',
  'Teacher',
];

const _categories = <_GiftCategorySeed>[
  _GiftCategorySeed(
      'Fragrance', 'Signature scent', ['Fragrance', 'Luxury'], 'brand'),
  _GiftCategorySeed(
      'Beauty', 'Beauty ritual', ['Beauty', 'Makeup'], 'retailer'),
  _GiftCategorySeed('Skincare', 'Sensitive skincare',
      ['Skincare', 'Wellness Retreats'], 'brand'),
  _GiftCategorySeed(
      'Makeup', 'Makeup edit', ['Makeup', 'Luxury Fashion'], 'retailer'),
  _GiftCategorySeed(
      'Jewellery', 'Jewellery keepsake', ['Jewellery', 'Luxury'], 'artisan'),
  _GiftCategorySeed(
      'Watches', 'Watch accessory', ['Watches', 'Luxury'], 'retailer'),
  _GiftCategorySeed('Fashion', 'Fashion styling piece',
      ['Fashion', 'Luxury Fashion'], 'brand'),
  _GiftCategorySeed(
      'Shoes', 'Footwear experience', ['Sneakers', 'Fashion'], 'retailer'),
  _GiftCategorySeed(
      'Bags', 'Bag and carry edit', ['Handbags', 'Fashion'], 'brand'),
  _GiftCategorySeed(
      'Tech', 'Smart technology', ['Tech', 'Business'], 'retailer'),
  _GiftCategorySeed('Gaming', 'Gaming upgrade', ['Gaming', 'Tech'], 'retailer'),
  _GiftCategorySeed(
      'Books', 'Curated reading', ['Books', 'Writing'], 'retailer'),
  _GiftCategorySeed('Architecture books', 'Architecture library',
      ['Architecture', 'Design'], 'retailer'),
  _GiftCategorySeed(
      'Art/design items', 'Design object', ['Art', 'Design'], 'artisan'),
  _GiftCategorySeed('Home decor', 'Home styling',
      ['Home Decor', 'Interior Design'], 'retailer'),
  _GiftCategorySeed('Home fragrance', 'Home fragrance',
      ['Home Fragrance', 'Fragrance'], 'brand'),
  _GiftCategorySeed('Wellness', 'Wellness care',
      ['Wellness Retreats', 'Spa Experiences'], 'experience'),
  _GiftCategorySeed(
      'Fitness/gym', 'Training support', ['Fitness', 'Gym'], 'retailer'),
  _GiftCategorySeed(
      'Sports', 'Sports experience', ['Sports', 'Football'], 'experience'),
  _GiftCategorySeed(
      'Football', 'Football moment', ['Football', 'Sports'], 'event'),
  _GiftCategorySeed('Running/cycling/swimming', 'Endurance kit',
      ['Running', 'Cycling', 'Swimming'], 'retailer'),
  _GiftCategorySeed(
      'Travel', 'Travel companion', ['Travel', 'City Breaks'], 'retailer'),
  _GiftCategorySeed('Luxury travel', 'Luxury travel moment',
      ['Luxury Travel', 'Hotels'], 'hotel'),
  _GiftCategorySeed(
      'Hotels', 'Hotel experience', ['Hotels', 'Luxury Travel'], 'hotel'),
  _GiftCategorySeed('Spa experiences', 'Spa day',
      ['Spa Experiences', 'Wellness Retreats'], 'experience'),
  _GiftCategorySeed('Restaurants', 'Restaurant experience',
      ['Restaurants', 'Food'], 'restaurant'),
  _GiftCategorySeed('Fine dining', 'Fine dining',
      ['Fine Dining', 'Restaurants'], 'restaurant'),
  _GiftCategorySeed('Michelin dining', 'Michelin dining',
      ['Michelin Dining', 'Fine Dining'], 'restaurant'),
  _GiftCategorySeed(
      'Afternoon tea', 'Afternoon tea', ['Afternoon Tea', 'Tea'], 'restaurant'),
  _GiftCategorySeed('Food/drink', 'Food and drink hamper',
      ['Food', 'Craft Beverages'], 'retailer'),
  _GiftCategorySeed(
      'Tea/coffee', 'Tea and coffee set', ['Tea', 'Coffee'], 'retailer'),
  _GiftCategorySeed('Wine appreciation', 'Wine appreciation',
      ['Wine Appreciation', 'Food'], 'retailer'),
  _GiftCategorySeed('Whisky appreciation', 'Whisky appreciation',
      ['Whisky Appreciation', 'Craft Beverages'], 'retailer'),
  _GiftCategorySeed(
      'Aviation', 'Aviation experience', ['Aviation', 'Travel'], 'experience'),
  _GiftCategorySeed('Cars/motorcycles', 'Motoring experience',
      ['Cars', 'Motorcycles'], 'experience'),
  _GiftCategorySeed('Music', 'Music gift', ['Music', 'Live Music'], 'event'),
  _GiftCategorySeed('Live music', 'Live music experience',
      ['Live Music', 'Festivals'], 'event'),
  _GiftCategorySeed(
      'Film/theatre', 'Screen and stage', ['Film', 'Theatre'], 'event'),
  _GiftCategorySeed('Musicals/opera', 'Musical or opera night',
      ['Musicals', 'Opera'], 'event'),
  _GiftCategorySeed('Business/entrepreneurship', 'Founder toolkit',
      ['Business', 'Entrepreneurship'], 'retailer'),
  _GiftCategorySeed('Investing/startups', 'Investor learning',
      ['Investing', 'Startups'], 'retailer'),
  _GiftCategorySeed('Personal development', 'Personal development',
      ['Personal Development', 'Leadership'], 'retailer'),
  _GiftCategorySeed('Gardening/nature', 'Garden and nature',
      ['Gardening', 'Nature'], 'retailer'),
  _GiftCategorySeed('Pet/animal gifts', 'Pet-friendly gift',
      ['Animals', 'Nature'], 'retailer'),
  _GiftCategorySeed('Faith-sensitive gifts', 'Faith-aware gift',
      ['Christian', 'Muslim', 'Jewish'], 'retailer'),
  _GiftCategorySeed('Charity/donation experiences', 'Donation experience',
      ['Charity', 'Sustainability'], 'charity'),
  _GiftCategorySeed('Sustainable gifts', 'Sustainable gift',
      ['Sustainability', 'Nature'], 'artisan'),
  _GiftCategorySeed(
      'Collectibles', 'Collectible piece', ['Collectibles', 'Art'], 'retailer'),
  _GiftCategorySeed('Luxury experiences', 'Luxury experience',
      ['Luxury', 'Fine Dining'], 'experience'),
  _GiftCategorySeed('Recovery/get-well gifts', 'Recovery care',
      ['Wellness Retreats', 'Books'], 'retailer'),
];

const _birdBlendRestrictions = <String>[
  'Do not list as standalone marketplace products.',
  'Do not expose wholesale pricing to customers.',
  'Use only inside curated gift experiences.',
];

const _birdBlendPairings = <String>[
  'Luxury candles',
  'Books',
  'Chocolate',
  'Biscuits',
  'Honey',
  'Mugs',
  'Blankets',
  'Flowers',
  'Journals',
  'Bath products',
  'Spa products',
  'Cookies',
  'Brownies',
  'Scent diffusers',
  'Personalised notes',
  'Gift Stories',
  'Handwritten cards',
];

const _birdBlendPhraseTriggers = <String>[
  'she loves tea',
  'he loves tea',
  'they love tea',
  'she drinks matcha',
  'he works from home',
  'she works from home',
  'she deserves a relaxing evening',
  'he deserves a relaxing evening',
  'she has been stressed',
  'he has been stressed',
  'she loves reading',
  'he loves reading',
  'she is into wellness',
  'he is into fitness',
  'they just moved house',
  'i want something comforting',
  'i want something thoughtful',
  'i want something cosy',
  'something relaxing',
  'something warm',
  'a self-care gift',
];

const _birdBlendSeasonal = <String>[
  'Christmas',
  'Autumn',
  'Winter',
  'Mother’s Day',
  'Father’s Day',
  'Valentine’s Day',
  'Exam Season',
  'Flu Season',
  'New Year wellness period',
  'Teacher appreciation period',
];

final List<GiftRepositoryItem> _birdBlendRepositoryItems = [
  _birdBlendItem(
    id: 'bird_blend_tea_gift_cubes',
    name: 'Bird & Blend Tea Gift Cubes',
    description:
        'Internal curated tea cube option for comfort, warmth, appreciation and thoughtful low-cost/high-perceived-value gift builds.',
    wholesalePrice: '£6.75',
    estimatedRrp: '£11.00',
    marginProfile: 'high',
    min: 50,
    max: 90,
    interests: const [
      'Tea',
      'Comfort',
      'Warmth',
      'Calm',
      'Relaxation',
      'Appreciation',
      'New Home',
      'Thinking of You',
      'Get Well Soon',
      'Birthday',
      'Thank You',
    ],
    occasions: const ['Birthday', 'Thank You', 'Get Well Soon', 'New Home'],
  ),
  _birdBlendItem(
    id: 'bird_blend_moment_of_calm_cube',
    name: 'Bird & Blend Moment of Calm Cube',
    description:
        'Internal calm and self-care option for stress, recovery, sympathy, burnout and mindful gifting.',
    wholesalePrice: '£6.75',
    estimatedRrp: '£11.00',
    marginProfile: 'high',
    min: 50,
    max: 90,
    interests: const [
      'Anxiety Relief',
      'Self Care',
      'Mindfulness',
      'Burnout Recovery',
      'Exam Stress',
      'Mental Wellness',
      'Sympathy',
      'Recovery',
      'Relaxation',
      'Wellness',
    ],
    occasions: const ['Get Well Soon', 'Thank You', 'Just Because'],
  ),
  _birdBlendItem(
    id: 'bird_blend_luxury_chocolate_cube',
    name: 'Bird & Blend Luxury Chocolate Gift Cube',
    description:
        'Internal celebratory tea-and-treat option for romance, birthdays, congratulations and indulgent thank-you gifts.',
    wholesalePrice: '£6.75',
    estimatedRrp: '£11.00',
    marginProfile: 'high',
    min: 50,
    max: 100,
    interests: const [
      'Celebration',
      'Romance',
      'Anniversary',
      'Birthday',
      'Congratulations',
      'Thank You',
      'Treat',
      'Indulgence',
      'Chocolate',
      'Tea',
    ],
    occasions: const [
      'Birthday',
      'Anniversary',
      'Congratulations',
      'Thank You'
    ],
  ),
  _birdBlendItem(
    id: 'bird_blend_tea_biscuits_cube',
    name: 'Bird & Blend Tea & Biscuits Cube',
    description:
        'Internal cosy evening and home-comfort option for housewarming, family, retirement and grandparent gift builds.',
    wholesalePrice: '£6.75',
    estimatedRrp: '£11.00',
    marginProfile: 'high',
    min: 50,
    max: 100,
    interests: const [
      'Cosy Evening',
      'Family',
      'Housewarming',
      'Retirement',
      'New Home',
      'Comfort',
      'Afternoon Tea',
      'Grandparent Gift',
      'Tea',
      'Biscuits',
    ],
    occasions: const ['New Home', 'Retirement', 'Thank You', 'Just Because'],
  ),
  _birdBlendItem(
    id: 'bird_blend_15_tea_bag_gift_packs',
    name: 'Bird & Blend 15 Tea Bag Gift Packs',
    description:
        'Internal everyday luxury option with excellent low wholesale / high perceived value fit.',
    wholesalePrice: '£2.83-£4.65',
    estimatedRrp: '£5.50-£9.45',
    marginProfile: 'excellent',
    min: 40,
    max: 90,
    interests: const [
      'Everyday Luxury',
      'Book Lover',
      'Office Worker',
      'Coffee Alternative',
      'Teacher Gift',
      'Mother’s Day',
      'Father’s Day',
      'Thank You',
      'Tea',
      'Reading',
    ],
    occasions: const ['Thank You', 'Birthday', 'Mother’s Day', 'Father’s Day'],
    recommendationScore: 98,
    priceEfficiencyScore: 100,
  ),
  _birdBlendItem(
    id: 'bird_blend_sticky_chai_collection',
    name: 'Bird & Blend Sticky Chai Collection',
    description:
        'Internal seasonal cosy and indulgent option for winter, Christmas, romance and comfort-led experiences.',
    wholesalePrice: '£7.80',
    estimatedRrp: '£15.00',
    marginProfile: 'excellent',
    min: 60,
    max: 120,
    interests: const [
      'Autumn',
      'Christmas',
      'Winter',
      'Cosy',
      'Luxury',
      'Fireside',
      'Hygge',
      'Comfort',
      'Indulgence',
      'Tea',
    ],
    occasions: const ['Christmas', 'Anniversary', 'Birthday', 'Just Because'],
  ),
  _birdBlendItem(
    id: 'bird_blend_matcha_collection',
    name: 'Bird & Blend Matcha Collection',
    description:
        'Internal premium wellness and productivity option for matcha lovers, fitness, new jobs, students and entrepreneurs.',
    wholesalePrice: '£14.00-£35.00',
    estimatedRrp: '£22.00-£58.00',
    marginProfile: 'premium',
    min: 75,
    max: 180,
    interests: const [
      'Productivity',
      'Fitness',
      'Wellness',
      'New Job',
      'Promotion',
      'Entrepreneur',
      'Student',
      'Healthy Living',
      'Morning Routine',
      'Matcha Lover',
      'Matcha',
    ],
    occasions: const ['Promotion', 'Graduation', 'Thank You', 'Just Because'],
    recommendationScore: 97,
  ),
  _birdBlendItem(
    id: 'bird_blend_tea_tools',
    name: 'Bird & Blend Tea Tools',
    description:
        'Internal premium upgrade option for tea ritual, slow mornings, new home and wellness-focused gift builds.',
    wholesalePrice: 'varies',
    estimatedRrp: 'varies',
    marginProfile: 'premium upgrade',
    min: 75,
    max: 200,
    interests: const [
      'Premium Upgrade',
      'Tea Ritual',
      'Home Comfort',
      'New Home',
      'Self Care',
      'Wellness',
      'Slow Morning',
      'Tea',
    ],
    occasions: const ['New Home', 'Birthday', 'Thank You', 'Just Because'],
  ),
];

GiftRepositoryItem _birdBlendItem({
  required String id,
  required String name,
  required String description,
  required String wholesalePrice,
  required String estimatedRrp,
  required String marginProfile,
  required int min,
  required int max,
  required List<String> interests,
  required List<String> occasions,
  int recommendationScore = 96,
  int priceEfficiencyScore = 98,
}) {
  return GiftRepositoryItem(
    id: id,
    name: name,
    category: 'Premium Tea & Wellness',
    subcategory: name.replaceFirst('Bird & Blend ', ''),
    description: description,
    estimatedPriceMin: min,
    estimatedPriceMax: max,
    priceBand: max <= 100 ? 'thoughtful' : 'premium',
    suitableBudgets: ['£$min-£$max'],
    interests: interests,
    occasions: occasions,
    relationships: const [
      'Friend',
      'Partner',
      'Mother',
      'Father',
      'Colleague',
      'Teacher',
      'Client'
    ],
    genderFit: const ['all'],
    ageRanges: const ['18-24', '25-34', '35-44', '45-64', '65+'],
    styleTags: const ['comfort', 'calm', 'wellness', 'curated gifts only'],
    allergyFlags: const ['food allergy review', 'caffeine suitability review'],
    medicalWarnings: const ['caffeine and medication suitability review'],
    religiousConsiderations: const ['dietary suitability review'],
    avoidIf: const ['allergy', 'caffeine sensitivity'],
    goodFor: interests.take(6).toList(),
    luxuryScore: 76,
    sentimentScore: 88,
    recoveryScore:
        interests.contains('Recovery') || interests.contains('Self Care')
            ? 92
            : 74,
    romanceScore: interests.contains('Romance') ? 86 : 54,
    practicalityScore: 82,
    surpriseScore: 78,
    supplierType: 'approved_wholesale_partner',
    procurementDifficulty: 'easy',
    linkedBrandPartnerName: 'Bird & Blend Tea Co.',
    supplierStatus: 'Approved Wholesale Partner',
    wholesalePrice: wholesalePrice,
    estimatedRrp: estimatedRrp,
    marginProfile: marginProfile,
    pairings: _birdBlendPairings,
    phraseTriggers: _birdBlendPhraseTriggers,
    seasonalWeighting: _birdBlendSeasonal,
    supplierRestrictions: _birdBlendRestrictions,
    recommendationScore: recommendationScore,
    priceEfficiencyScore: priceEfficiencyScore,
    packagingQualityScore: 95,
    emotionalVersatilityScore: 100,
    corporateSuitabilityScore: 95,
    repeatPurchasePotentialScore: 98,
  );
}

final List<GiftRepositoryItem> internalGiftRepository =
    List<GiftRepositoryItem>.unmodifiable(_buildRepository());

List<GiftRepositoryItem> _buildRepository() {
  final items = <GiftRepositoryItem>[..._birdBlendRepositoryItems];
  for (var i = 0; i < 1000 - _birdBlendRepositoryItems.length; i++) {
    final seed = _categories[i % _categories.length];
    final tier = i % 5;
    final min =
        switch (tier) { 0 => 50, 1 => 100, 2 => 250, 3 => 500, _ => 1000 };
    final max =
        switch (tier) { 0 => 100, 1 => 250, 2 => 500, 3 => 1000, _ => 1500 };
    final priceBand = switch (tier) {
      0 => 'budget',
      1 => 'standard',
      2 => 'premium',
      3 => 'luxury',
      _ => 'ultra_luxury',
    };
    final occasion = _occasions[i % _occasions.length];
    final relationship = _relationships[i % _relationships.length];
    final interestSet = {
      ...seed.interests,
      if (i.isEven) 'Luxury',
      if (i % 3 == 0) 'Personal Development',
    }.where(giftsExpandedInterests.contains).toList();
    items.add(GiftRepositoryItem(
      id: 'gift_repo_${(i + 1).toString().padLeft(4, '0')}',
      name: '${seed.name} ${_descriptorFor(i)}',
      category: seed.category,
      subcategory: seed.name,
      description:
          'Internal ${seed.name.toLowerCase()} option for $occasion gifting with a $priceBand budget.',
      estimatedPriceMin: min,
      estimatedPriceMax: max,
      priceBand: priceBand,
      suitableBudgets: [priceBand, '£$min-£$max'],
      interests: interestSet,
      occasions: [
        occasion,
        'Birthday',
        if (occasion != 'Thank You') 'Thank You'
      ],
      relationships: [relationship, 'Friend', 'Partner'],
      genderFit: const ['all'],
      ageRanges: const ['18-24', '25-34', '35-44', '45-64'],
      styleTags: [_styleFor(i), priceBand, seed.category.toLowerCase()],
      allergyFlags: _allergyFlags(seed.category),
      medicalWarnings: _medicalWarnings(seed.category),
      religiousConsiderations: _religiousConsiderations(seed.category),
      avoidIf: _avoidIf(seed.category),
      goodFor: [occasion, relationship, ...interestSet.take(2)],
      luxuryScore: 40 + (tier * 12) + (i % 8),
      sentimentScore: 50 + (i % 40),
      recoveryScore: seed.category.contains('Recovery') ? 90 : 35 + (i % 30),
      romanceScore: relationship == 'Partner' ||
              relationship == 'Wife' ||
              relationship == 'Husband'
          ? 82
          : 30 + (i % 25),
      practicalityScore: 45 + (i % 45),
      surpriseScore: 50 + ((i * 7) % 45),
      supplierType: seed.supplierType,
      procurementDifficulty: switch (tier) {
        0 || 1 => 'easy',
        2 || 3 => 'medium',
        _ => 'hard',
      },
    ));
  }
  return items;
}

class GiftsRecommendationEngine {
  const GiftsRecommendationEngine();

  GiftRecommendationResult recommend({
    required double budget,
    required String relationship,
    required String occasion,
    required Iterable<String> interests,
    String? ageRange,
    String? gender,
    DateTime? deliveryDate,
    String? notes,
    Iterable<GiftRepositoryItem>? repository,
    int maxResults = 5,
  }) {
    final sourceRepository = repository ?? internalGiftRepository;
    final selectedInterests = interests.map(_normalise).toSet();
    final promptText = _normalise(
        '${interests.join(' ')} $relationship $occasion ${notes ?? ''}');
    final riskTerms = _riskTerms(notes ?? '', selectedInterests);
    final spendableBudget = budget * 0.82;
    final urgent = deliveryDate != null &&
        deliveryDate.difference(DateTime.now()).inDays <= 3;
    final candidates = sourceRepository
        .where((item) => item.active && item.internalOnly)
        .where((item) => item.estimatedPriceMin <= spendableBudget)
        .where((item) {
      if (ageRange != null &&
          ageRange.trim().isNotEmpty &&
          !item.ageRanges.contains(ageRange)) {
        return false;
      }
      for (final avoid in item.avoidIf) {
        if (riskTerms.contains(_normalise(avoid))) return false;
      }
      return true;
    }).map((item) {
      var score = 0;
      final reasons = <String>[];
      final warnings = <String>[];

      if (budget >= item.estimatedPriceMin &&
          budget <= item.estimatedPriceMax * 1.4) {
        score += 22;
        reasons.add('Fits the stated budget range.');
      } else if (budget >= item.estimatedPriceMin * 0.8) {
        score += 8;
      } else {
        score -= 20;
      }
      if (item.relationships
          .map(_normalise)
          .contains(_normalise(relationship))) {
        score += 12;
        reasons.add('Suitable for $relationship.');
      }
      if (item.occasions.map(_normalise).contains(_normalise(occasion))) {
        score += 18;
        reasons.add('Strong occasion match.');
      }
      final itemInterests = item.interests.map(_normalise).toSet();
      final matchedInterests = itemInterests.intersection(selectedInterests);
      if (matchedInterests.isNotEmpty) {
        score += matchedInterests.length * 15;
        reasons.add(
            'Matches ${matchedInterests.length} selected interest${matchedInterests.length == 1 ? '' : 's'}.');
      }
      if (ageRange != null && item.ageRanges.contains(ageRange)) {
        score += 4;
      }
      if (gender != null &&
          item.genderFit.map(_normalise).contains(_normalise(gender))) {
        score += 4;
      }
      if (urgent && item.procurementDifficulty == 'easy') {
        score += 8;
        reasons.add('Practical for a shorter delivery window.');
      } else if (urgent && item.procurementDifficulty == 'hard') {
        score -= 10;
        warnings.add('Hard procurement may be risky for the requested date.');
      }
      if (item.linkedBrandPartnerName == 'Bird & Blend Tea Co.') {
        final triggerHits = {
          ...item.phraseTriggers.map(_normalise),
          ...item.interests.map(_normalise),
        }.where(
            (trigger) => trigger.isNotEmpty && promptText.contains(trigger));
        if (triggerHits.isNotEmpty) {
          score += 22 + triggerHits.take(4).length * 6;
          reasons.add(
              'Chosen because the recipient appears drawn to comfort, calm, tea, wellness or thoughtful self-care.');
        } else {
          score -= 18;
        }
        if (item.seasonalWeighting
            .map(_normalise)
            .any((season) => promptText.contains(season))) {
          score += 10;
          reasons.add('Seasonal fit for a warm curated gift build.');
        }
      }

      for (final avoid in item.avoidIf) {
        if (riskTerms.contains(_normalise(avoid))) {
          score -= 40;
          warnings.add('Avoid or review: $avoid.');
        }
      }
      for (final warning in [
        ...item.allergyFlags,
        ...item.medicalWarnings,
        ...item.religiousConsiderations,
      ]) {
        if (riskTerms.any((term) => _normalise(warning).contains(term))) {
          warnings.add(warning);
        }
      }

      score +=
          (item.luxuryScore + item.sentimentScore + item.surpriseScore) ~/ 30;
      return GiftRecommendationCandidate(
        item: item,
        score: score,
        reasons: reasons.isEmpty ? ['General fit for the request.'] : reasons,
        riskWarnings: warnings,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final top = candidates.take(maxResults.clamp(3, 5)).toList();
    final warningSet = <String>{
      for (final candidate in top) ...candidate.riskWarnings,
      ..._globalRiskWarnings(notes ?? '', selectedInterests),
    }.toList();
    final netGift = (budget * 0.72).round();
    final packaging = (budget * 0.08).round();
    final delivery = (budget * 0.10).round();
    final reserve = budget.round() - netGift - packaging - delivery;
    return GiftRecommendationResult(
      experienceSummary:
          'Recommended Experience: Curated $occasion gift experience for a $relationship. Focus areas: ${selectedInterests.take(5).join(', ')}. Budget tier: ${_budgetTier(budget)}. Surprise factor: ${top.isNotEmpty && top.first.item.surpriseScore > 75 ? 'high' : 'balanced'}.',
      budgetAllocation: {
        'giftProcurement': netGift,
        'packagingAndPresentation': packaging,
        'deliveryAndOperations': delivery,
        'contingencyAndMargin': reserve,
      },
      topCandidates: top,
      riskWarnings: warningSet,
      procurementNotes: [
        'Do not reveal candidate item names to the sender before delivery.',
        'Review allergy, medical, religious and sensitivity notes before procurement.',
        if (top.isNotEmpty)
          'Start procurement review with ${top.first.item.category} / ${top.first.item.subcategory}.',
      ],
    );
  }
}

class _GiftCategorySeed {
  final String category;
  final String name;
  final List<String> interests;
  final String supplierType;

  const _GiftCategorySeed(
      this.category, this.name, this.interests, this.supplierType);
}

String _descriptorFor(int i) {
  const descriptors = [
    'Edit',
    'Experience',
    'Bundle',
    'Moment',
    'Selection',
    'Set',
    'Plan',
    'Concierge Option'
  ];
  return descriptors[i % descriptors.length];
}

String _styleFor(int i) {
  const styles = [
    'classic',
    'modern',
    'premium',
    'minimalist',
    'personal',
    'celebratory'
  ];
  return styles[i % styles.length];
}

List<String> _allergyFlags(String category) {
  final lower = category.toLowerCase();
  if (lower.contains('food') ||
      lower.contains('restaurant') ||
      lower.contains('tea') ||
      lower.contains('coffee')) {
    return const ['food allergy review', 'nuts and dairy risk'];
  }
  if (lower.contains('fragrance') ||
      lower.contains('beauty') ||
      lower.contains('skincare')) {
    return const ['skin sensitivity review', 'fragrance sensitivity risk'];
  }
  if (lower.contains('pet')) return const ['pet allergy review'];
  return const [];
}

List<String> _medicalWarnings(String category) {
  final lower = category.toLowerCase();
  if (lower.contains('food') ||
      lower.contains('wine') ||
      lower.contains('whisky')) {
    return const ['diabetes and medication suitability review'];
  }
  if (lower.contains('fitness') || lower.contains('sports')) {
    return const ['mobility suitability review'];
  }
  return const [];
}

List<String> _religiousConsiderations(String category) {
  final lower = category.toLowerCase();
  if (lower.contains('wine') || lower.contains('whisky')) {
    return const ['alcohol may conflict with faith or age suitability'];
  }
  if (lower.contains('food') || lower.contains('restaurant')) {
    return const ['halal/kosher/vegetarian suitability review'];
  }
  if (lower.contains('spiritual')) return const ['faith suitability review'];
  return const [];
}

List<String> _avoidIf(String category) {
  final lower = category.toLowerCase();
  return [
    if (lower.contains('food') || lower.contains('restaurant')) 'allergy',
    if (lower.contains('food') || lower.contains('restaurant')) 'diabetes',
    if (lower.contains('wine') || lower.contains('whisky')) 'alcohol',
    if (lower.contains('fragrance') ||
        lower.contains('beauty') ||
        lower.contains('skincare'))
      'sensitivity',
    if (lower.contains('pet')) 'pet allergy',
  ];
}

Set<String> _riskTerms(String notes, Set<String> interests) {
  final lower = notes.toLowerCase();
  return {
    for (final interest in interests) _normalise(interest),
    if (lower.contains('diabetes') || lower.contains('diabetic')) 'diabetes',
    if (lower.contains('allergy') || lower.contains('allergic')) 'allergy',
    if (lower.contains('nut')) 'allergy',
    if (lower.contains('muslim') || lower.contains('halal')) 'muslim',
    if (lower.contains('jewish') || lower.contains('kosher')) 'jewish',
    if (lower.contains('christian')) 'christian',
    if (lower.contains('alcohol')) 'alcohol',
    if (lower.contains('sensitive') || lower.contains('sensitivity'))
      'sensitivity',
  };
}

List<String> _globalRiskWarnings(String notes, Set<String> interests) {
  final risks = _riskTerms(notes, interests);
  return [
    if (risks.contains('diabetes'))
      'Avoid sugary hampers or chocolate-heavy gifts unless explicitly approved.',
    if (risks.contains('allergy'))
      'Review allergies before food, fragrance, skincare, flowers, nuts, latex, wool or pet-related gifts.',
    if (risks.contains('muslim'))
      'Flag alcohol, pork-derived items and non-halal food risks.',
    if (risks.contains('jewish')) 'Flag non-kosher food risks.',
    if (risks.contains('christian') && risks.contains('spiritual'))
      'Review spiritual/occult-adjacent items carefully.',
    if (risks.contains('wine appreciation') ||
        risks.contains('whisky appreciation') ||
        risks.contains('alcohol'))
      'Alcohol interests are optional and must be suppressed if medical, religious, age or notes suggest risk.',
  ];
}

String _budgetTier(double budget) {
  if (budget >= 1000) return 'ultra-premium';
  if (budget >= 500) return 'luxury';
  if (budget >= 250) return 'premium';
  if (budget >= 100) return 'standard';
  return 'thoughtful';
}

String _normalise(String value) => value.trim().toLowerCase();
