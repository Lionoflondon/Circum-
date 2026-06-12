const fs = require('fs');
const path = require('path');

const outputDir = path.join(__dirname, '..', 'data', 'gifts');
fs.mkdirSync(outputDir, { recursive: true });

const slug = (value) => value.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
const write = (name, value) => {
  fs.writeFileSync(path.join(outputDir, name), `${JSON.stringify(value, null, 2)}\n`);
};

const retailerGroups = {
  'Gift Specialists': {
    prefixes: ['Thoughtful', 'Wrapped', 'Bright', 'Kindred', 'Joyful', 'Golden', 'Little', 'Perfect', 'Happy', 'Curated'],
    suffixes: ['Gift House', 'Present Co', 'Parcel Studio', 'Occasion Shop', 'Gifting Room'],
    budget: [10, 250], uniqueness: 72, reliability: 88, difficulty: 1,
  },
  'Independent Makers': {
    prefixes: ['Oak &', 'Copper &', 'Willow &', 'North &', 'Thistle &', 'Linen &', 'Clay &', 'Foundry &', 'Meadow &', 'Harbour &'],
    suffixes: ['Thread', 'Stone', 'Pine', 'Bloom', 'Craft'],
    budget: [15, 400], uniqueness: 91, reliability: 80, difficulty: 2,
  },
  Experiences: {
    prefixes: ['London', 'British', 'Weekend', 'Signature', 'Discovery', 'Adventure', 'City', 'Escape', 'Moment', 'Journey'],
    suffixes: ['Experiences', 'Days Out', 'Moments', 'Escapes', 'Adventures'],
    budget: [25, 1000], uniqueness: 86, reliability: 84, difficulty: 2,
  },
  'Luxury & Specialist': {
    prefixes: ['Aurelia', 'Maison', 'Regent', 'Mayfair', 'Sterling', 'Belgravia', 'Kensington', 'Savile', 'Claridge', 'Burlington'],
    suffixes: ['Atelier', 'Collection', 'Gallery', 'Reserve', 'House'],
    budget: [50, 5000], uniqueness: 94, reliability: 90, difficulty: 3,
  },
};

const retailers = [];
for (const [category, config] of Object.entries(retailerGroups)) {
  for (const prefix of config.prefixes) {
    for (const suffix of config.suffixes) {
      const index = retailers.length + 1;
      retailers.push({
        id: `retailer_${String(index).padStart(3, '0')}`,
        name: `${prefix} ${suffix}`,
        category,
        uk_delivery: true,
        gift_uniqueness_score: Math.min(100, config.uniqueness + (index % 7)),
        reliability_score: Math.min(100, config.reliability + (index % 6)),
        procurement_difficulty: config.difficulty + (index % 5 === 0 ? 1 : 0),
        budget_min: config.budget[0],
        budget_max: config.budget[1],
        active: true,
      });
    }
  }
}

const occasions = [
  ['birthday', 'Birthday'], ['christmas', 'Christmas'], ['anniversary', 'Anniversary'],
  ['graduation', 'Graduation'], ['promotion', 'Promotion'], ['retirement', 'Retirement'],
  ['wedding', 'Wedding'], ['new_baby', 'New Baby'], ['mothers_day', "Mother's Day"],
  ['fathers_day', "Father's Day"], ['valentines_day', "Valentine's Day"], ['eid', 'Eid'],
  ['easter', 'Easter'], ['new_year', 'New Year'],
].map(([id, name], index) => ({
  id: `occasion_${id}`,
  name,
  seasonality: ['christmas', 'mothers_day', 'fathers_day', 'valentines_day', 'eid', 'easter', 'new_year'].includes(id),
  default_tone: ['anniversary', 'wedding', 'valentines_day'].includes(id) ? 'romantic' : 'celebratory',
  priority: index + 1,
  active: true,
}));

const relationships = [
  'Partner', 'Husband', 'Wife', 'Mother', 'Father', 'Son', 'Daughter',
  'Brother', 'Sister', 'Friend', 'Colleague', 'Mentor', 'Client', 'Teacher',
].map((name, index) => ({
  id: `relationship_${slug(name)}`,
  name,
  intimacy_level: index < 9 ? 'close' : index === 9 ? 'personal' : 'professional',
  safe_gift_tone: index < 9 ? ['personal', 'thoughtful'] : ['appropriate', 'useful'],
  active: true,
}));

const interestThemes = [
  'Technology', 'Gaming', 'Travel', 'Aviation', 'Football', 'Running', 'Cycling', 'Fitness',
  'Books', 'History', 'Science', 'Luxury', 'Home Design', 'Cooking', 'Coffee', 'Tea', 'Chocolate',
  'Experiences', 'Pets', 'Automotive', 'Fashion', 'Beauty', 'Collectibles', 'Photography', 'Music',
];
const interestFacets = [
  'Beginner', 'Enthusiast', 'Expert', 'Premium', 'Practical', 'Sustainable', 'Personalised', 'Classic',
  'Modern', 'British', 'Independent', 'Portable', 'Home', 'Outdoor', 'Family', 'Social', 'Creative',
  'Wellness', 'Collector', 'Adventure',
];
const interests = [];
for (const theme of interestThemes) {
  for (const facet of interestFacets) {
    const index = interests.length + 1;
    interests.push({
      id: `interest_${String(index).padStart(3, '0')}`,
      name: `${facet} ${theme}`,
      theme,
      facet,
      keywords: [slug(theme), slug(facet), slug(`${facet} ${theme}`)],
      active: true,
    });
  }
}

const productTemplates = {
  Technology: ['Wireless Charging Stand', 'Smart Home Starter Kit', 'Portable Speaker', 'Digital Notebook', 'Tech Organiser'],
  Gaming: ['Gaming Headset', 'Controller Dock', 'Desk Mat', 'Retro Game Collection', 'Gaming Light Set'],
  Travel: ['Cabin Organiser', 'Travel Journal', 'Packing Cube Set', 'Weekend Bag', 'Passport Wallet'],
  Aviation: ['Aircraft Model', 'Pilot Logbook', 'Airport Print', 'Aviation History Book', 'Flight Experience Voucher'],
  Sports: ['Team Scarf', 'Training Ball', 'Sports Bottle', 'Matchday Experience', 'Recovery Kit'],
  Fitness: ['Resistance Band Set', 'Fitness Tracker Strap', 'Yoga Set', 'Massage Tool', 'Gym Bag'],
  Books: ['Illustrated Hardback', 'Signed Edition', 'Book Subscription', 'Reading Light', 'Personalised Bookmark'],
  Luxury: ['Leather Card Holder', 'Silk Accessory', 'Premium Pen', 'Luxury Candle', 'Presentation Gift Box'],
  Home: ['Ceramic Vase', 'Throw Blanket', 'Serving Board', 'Indoor Plant Set', 'Home Fragrance Set'],
  Food: ['Artisan Chocolate Box', 'Cheese Selection', 'Coffee Tasting Set', 'Tea Collection', 'Gourmet Hamper'],
  Experiences: ['Afternoon Tea', 'Driving Experience', 'Spa Day', 'Creative Workshop', 'Dining Experience'],
  Pets: ['Personalised Pet Bowl', 'Pet Treat Box', 'Walking Set', 'Pet Portrait Voucher', 'Comfort Bed'],
  Automotive: ['Car Care Kit', 'Driving Gloves', 'Vehicle Organiser', 'Track Day Voucher', 'Detailing Set'],
  Fashion: ['Designer Scarf', 'Everyday Tote', 'Personalised Cap', 'Premium Socks Set', 'Statement Accessory'],
  Beauty: ['Skincare Set', 'Fragrance Discovery Set', 'Beauty Tool Kit', 'Bath Collection', 'Wellness Gift Box'],
  Collectibles: ['Display Case', 'Limited Print', 'Collector Album', 'Commemorative Coin', 'Memorabilia Frame'],
};
const itemCategories = Object.keys(productTemplates);
const variants = ['Essential', 'Signature', 'Premium', 'Personalised', 'Discovery', 'Classic', 'Modern', 'Deluxe', 'Compact', 'Celebration', 'Curated', 'Limited', 'Weekend'];
const items = [];
for (let index = 0; index < 1000; index += 1) {
  const category = itemCategories[index % itemCategories.length];
  const templates = productTemplates[category];
  const template = templates[Math.floor(index / itemCategories.length) % templates.length];
  const variant = variants[Math.floor(index / (itemCategories.length * templates.length)) % variants.length];
  const retailer = retailers[(index * 7 + itemCategories.indexOf(category)) % retailers.length];
  const basePrice = 12 + itemCategories.indexOf(category) * 4 + (index % 9) * 7;
  const interestStart = (itemCategories.indexOf(category) * 31 + index) % interests.length;
  const occasionStart = index % occasions.length;
  const relationshipStart = index % relationships.length;
  items.push({
    id: `gift_item_${String(index + 1).padStart(4, '0')}`,
    name: `${variant} ${template}`,
    category,
    retailer_id: retailer.id,
    description: `${variant} ${template.toLowerCase()} selected for thoughtful ${category.toLowerCase()} gifting.`,
    price_gbp: basePrice,
    budget_band: basePrice < 30 ? 'under_30' : basePrice < 75 ? '30_to_74' : basePrice < 150 ? '75_to_149' : '150_plus',
    interest_ids: [interests[interestStart].id, interests[(interestStart + 25) % interests.length].id],
    occasion_ids: [occasions[occasionStart].id, occasions[(occasionStart + 3) % occasions.length].id],
    relationship_ids: [relationships[relationshipStart].id, relationships[(relationshipStart + 5) % relationships.length].id],
    age_min: index % 11 === 0 ? 8 : 18,
    age_max: 100,
    gender_affinity: 'any',
    delivery_lead_days: 1 + (index % 7),
    personalised: ['Personalised', 'Signature'].includes(variant),
    uniqueness_score: 60 + (index % 41),
    reliability_score: retailer.reliability_score,
    learning: { impressions: 0, shortlisted: 0, approved: 0, purchased: 0, success_score: null },
    active: true,
  });
}

const rules = {
  version: 1,
  currency: 'GBP',
  strategy: 'weighted_filter_then_rank',
  hard_filters: {
    active_item: true,
    active_retailer: true,
    uk_delivery_required: true,
    budget_must_cover_item_price: true,
    delivery_lead_days_must_fit_deadline: true,
    age_must_be_within_item_range: true,
  },
  scoring_weights: {
    interests: 0.30,
    occasion: 0.20,
    relationship: 0.18,
    budget_fit: 0.12,
    retailer_reliability: 0.08,
    uniqueness: 0.07,
    delivery_confidence: 0.05,
  },
  optional_inputs: ['gender'],
  required_inputs: ['budget', 'relationship', 'occasion', 'interests', 'age', 'delivery_deadline'],
  fallback_order: ['interest_and_occasion', 'occasion_and_relationship', 'interest_and_budget', 'reliable_budget_fit'],
  budget_rules: {
    reserve_delivery_cost: true,
    maximum_item_price_ratio: 0.85,
    minimum_remaining_buffer_gbp: 5,
  },
  deadline_rules: {
    same_day_max_lead_days: 0,
    next_day_max_lead_days: 1,
    exclude_late_items: true,
  },
  learning_rules: {
    record_impression: true,
    record_shortlist: true,
    record_admin_approval: true,
    record_purchase: true,
    record_recipient_feedback: true,
    minimum_outcomes_before_personalisation: 20,
    never_override_hard_filters: true,
  },
  governance: {
    recommendations_require_active_inventory: true,
    no_exact_item_promise_before_procurement: true,
    admin_approval_workflow_unchanged: true,
    stripe_logic_unchanged: true,
    circum_gift_card_logic_unchanged: true,
  },
};

write('retailers.json', { version: 1, count: retailers.length, retailers });
write('gift_items.json', { version: 1, count: items.length, items });
write('gift_interests.json', { version: 1, count: interests.length, interests });
write('gift_occasions.json', { version: 1, count: occasions.length, occasions });
write('gift_relationships.json', { version: 1, count: relationships.length, relationships });
write('gift_rules.json', rules);

const retailerIds = new Set(retailers.map((entry) => entry.id));
const interestIds = new Set(interests.map((entry) => entry.id));
const occasionIds = new Set(occasions.map((entry) => entry.id));
const relationshipIds = new Set(relationships.map((entry) => entry.id));
if (retailers.length !== 200 || items.length !== 1000 || interests.length !== 500) {
  throw new Error('Repository counts do not match the Gifts Repository v1 contract.');
}
for (const item of items) {
  if (!retailerIds.has(item.retailer_id) ||
      item.interest_ids.some((id) => !interestIds.has(id)) ||
      item.occasion_ids.some((id) => !occasionIds.has(id)) ||
      item.relationship_ids.some((id) => !relationshipIds.has(id))) {
    throw new Error(`Broken repository reference in ${item.id}`);
  }
}

console.log(`Generated ${retailers.length} retailers, ${items.length} gift items, and ${interests.length} interests.`);
