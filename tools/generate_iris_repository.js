const fs = require('fs');
const path = require('path');

const categories = [
  {name:'Documents', count:70, base:[['Passport',0.05,0.03,0.08,'Feather','small',true],['Legal papers',0.25,0.1,0.7,'Feather','small',true],['Contracts folder',0.35,0.15,0.9,'Feather','small',true],['Birth certificate',0.04,0.02,0.08,'Feather','small',true],['Driving licence',0.03,0.01,0.05,'Feather','small',true],['Document wallet',0.45,0.2,1.0,'Feather','small',true],['Office file box',3.0,1.5,5.0,'Light','medium',false]], variants:['single','sealed','folder','small bundle','large bundle','archive','padded envelope','courier pack','presentation pack','document box']},
  {name:'Electronics', count:150, base:[['iPhone',0.2,0.15,0.3,'Feather','small',true],['Samsung Galaxy phone',0.22,0.16,0.32,'Feather','small',true],['iPad',0.55,0.45,0.8,'Feather','small',true],['MacBook Air',1.24,1.1,1.5,'Light','medium',true],['MacBook Pro',2.1,1.8,2.5,'Light','medium',true],['Standard laptop',2.0,1.4,2.8,'Light','medium',true],['Monitor',5.5,3.5,9.0,'Medium','large',true],['Camera lens',0.8,0.3,2.0,'Feather','small',true],['PlayStation 5',4.5,4.0,5.5,'Light','medium',true],['Xbox console',4.0,3.2,5.0,'Light','medium',true],['Nintendo Switch',0.7,0.4,1.2,'Feather','small',true],['Drone',1.5,0.5,4.0,'Light','medium',true],['Graphics card',1.2,0.6,2.2,'Light','small',true],['Television',12,6,25,'Medium','large',true]], variants:['boxed','with charger','sealed retail box','used','with accessories','protective case','gift wrapped','padded box','repair return','trade-in']},
  {name:'Fashion', count:90, base:[['Trainers',1.0,0.6,1.8,'Light','small',false],['Designer handbag',1.2,0.5,2.5,'Light','small',true],['Designer shoes',1.2,0.7,2.2,'Light','small',true],['Jacket',1.0,0.4,2.0,'Light','small',false],['Coat',1.6,0.8,3.0,'Light','medium',false],['Dress',0.7,0.2,1.5,'Feather','small',false],['Jewellery box',0.35,0.05,1.2,'Feather','small',true],['Luxury watch',0.25,0.05,0.8,'Feather','small',true],['Sunglasses',0.15,0.05,0.5,'Feather','small',true]], variants:['new','boxed','gift bag','returns parcel','small parcel','large parcel','premium','folded','wardrobe bag','sealed']},
  {name:'Household', count:120, base:[['Cookware set',5.0,2.5,10,'Medium','medium',false],['Kitchen utensils',1.5,0.5,3.5,'Light','small',false],['Bedding set',3.0,1.0,6.0,'Light','medium',false],['Duvet',2.2,1.0,4.5,'Light','medium',false],['Decor vase',1.5,0.5,4.0,'Light','small',true],['Cleaning products',4.0,1.5,8.0,'Light','medium',false],['Microwave',12,8,18,'Medium','large',true],['Vacuum cleaner',6.5,4.0,10,'Medium','medium',false],['Coffee machine',5.5,3.0,10,'Medium','medium',true],['Office chair',15,10,20,'Medium','large',false],['Small side table',8,4,14,'Medium','large',false],['Lamp',2.0,0.8,5.0,'Light','medium',true]], variants:['boxed','wrapped','assembled','flat packed','small','large','fragile','bundle','replacement','return']},
  {name:'Business', count:80, base:[['Printer',9.0,5.0,15,'Medium','large',true],['Stationery box',4.0,1.5,8.0,'Light','medium',false],['Office supplies',5.0,2.0,10,'Medium','medium',false],['Presentation equipment',4.0,1.5,8.0,'Light','medium',true],['Secure documents',0.5,0.1,1.5,'Feather','small',true],['Company laptop',2.0,1.2,3.0,'Light','medium',true],['Marketing materials',6.0,2.0,12,'Medium','medium',false],['Card reader terminal',0.6,0.2,1.2,'Feather','small',true]], variants:['urgent','sealed','office move','courier bag','small box','large box','confidential','branch transfer','client delivery','return']},
  {name:'Groceries', count:90, base:[['Food package',3.0,1.0,6.0,'Light','medium',false],['Drinks crate',12,6,20,'Medium','medium',false],['Household shopping',8,3,15,'Medium','medium',false],['Fresh produce bag',4,1,8,'Light','medium',false],['Frozen food pack',5,2,10,'Medium','medium',false],['Cake box',1.5,0.5,4,'Light','small',true],['Meal kit',3,1,6,'Light','medium',false],['Wine bottles',5,1.5,12,'Medium','medium',true],['Water bottles',10,4,18,'Medium','medium',false]], variants:['small','medium','large','fragile','sealed','weekly shop','single bag','two bags','crate','cool bag']},
  {name:'Health+', count:70, base:[['Permitted medication',0.3,0.05,1.0,'Feather','small',true],['Prescription bag',0.25,0.05,0.8,'Feather','small',true],['Medical device',2.0,0.5,8.0,'Light','medium',true],['Healthcare supplies',3.0,0.5,8.0,'Light','medium',false],['Blood pressure monitor',0.8,0.4,1.5,'Feather','small',true],['Mobility aid',5.0,1.0,15,'Medium','large',false],['Sealed pharmacy package',0.4,0.05,1.5,'Feather','small',true]], variants:['sealed','NHS','private','repeat','urgent','small bag','pharmacy bag','boxed','patient pack','monthly']},
  {name:'Airport', count:70, base:[['Cabin suitcase',8,4,12,'Medium','large',false],['Large suitcase',18,10,28,'Medium','large',false],['Travel backpack',6,2,12,'Medium','medium',false],['Duty free bag',2,0.5,5,'Light','small',true],['Travel documents',0.2,0.05,0.8,'Feather','small',true],['Golf travel bag',18,10,30,'Medium','large',false],['Pushchair travel bag',10,6,18,'Medium','large',false]], variants:['Heathrow','Gatwick','airport','terminal transfer','lost property','checked luggage','carry on','fragile','oversized','urgent']},
  {name:'Gifts', count:80, base:[['Flowers',1.5,0.5,3.0,'Light','medium',true],['Cake',1.5,0.5,4.0,'Light','small',true],['Gift hamper',4.0,1.5,8.0,'Light','medium',true],['Celebration gift',2.0,0.5,5.0,'Light','small',true],['Gift box',1.5,0.3,4.0,'Light','small',true],['Perfume collection',1.0,0.2,3.0,'Light','small',true],['Art print',1.0,0.2,3.0,'Light','medium',true],['Wine gift set',4.0,1.5,8.0,'Light','medium',true]], variants:['birthday','anniversary','wrapped','premium','surprise','same day','small','large','fragile','card included']},
  {name:'DIY', count:100, base:[['Toolbox',12,5,20,'Medium','medium',false],['Drill',2.0,1.0,4.0,'Light','small',false],['Hardware pack',4.0,1.0,8.0,'Light','small',false],['Electrical supplies',3.0,0.8,8.0,'Light','small',false],['Paint tin',5.0,2.5,10,'Medium','medium',false],['Ladder',12,5,25,'Medium','large',false],['Power tool set',8.0,3.0,15,'Medium','medium',false],['Tile box',18,10,25,'Medium','medium',false],['Flat pack shelf',15,7,25,'Medium','large',false],['Garden tool',6,2,14,'Medium','large',false]], variants:['small','medium','large','boxed','bundle','trade','replacement','fragile','long item','return']},
  {name:'Sports', count:90, base:[['Football kit',1.5,0.5,3.0,'Light','small',false],['Gym equipment',15,5,30,'Medium','large',false],['Dumbbell set',20,10,40,'Heavy','medium',false],['Yoga mat',1.2,0.6,2.5,'Light','medium',false],['Golf clubs',12,6,18,'Medium','large',false],['Racing bicycle',9,6,13,'Medium','large',true],['E-bike',24,18,35,'Heavy','large',true],['Tennis racket',1.0,0.4,2.0,'Light','medium',false],['Fishing rod',2.0,0.5,5.0,'Light','large',true]], variants:['boxed','bagged','club delivery','event','repair','premium','oversized','fragile','small','large']},
  {name:'Education', count:60, base:[['Books',8,2,15,'Medium','medium',false],['Study materials',3,0.5,8,'Light','small',false],['Learning kit',4,1,8,'Light','medium',false],['School bag',5,2,10,'Medium','medium',false],['Art supplies',3,1,7,'Light','small',true],['Textbook box',12,5,20,'Medium','medium',false]], variants:['primary','secondary','university','course','library','boxed','folder','bundle','return','urgent']},
  {name:'Baby', count:80, base:[['Nappies',4,1,8,'Light','medium',false],['Baby formula',3,1,8,'Light','small',false],['Baby supplies',5,1,12,'Medium','medium',false],['Stroller',10,6,18,'Medium','large',false],['Car seat',7,4,12,'Medium','large',false],['Baby clothes',2,0.5,5,'Light','small',false],['Cot mattress',5,2,10,'Medium','large',false],['Baby monitor',0.8,0.3,1.5,'Feather','small',true]], variants:['small','medium','large','boxed','urgent','weekly','newborn','sealed','fragile','family']},
];

function slug(s){return s.toLowerCase().replace(/[^a-z0-9]+/g,'_').replace(/^_|_$/g,'');}
function weightClass(w){ if(w<=1) return 'Feather'; if(w<=5) return 'Light'; if(w<=20) return 'Medium'; if(w<=50) return 'Heavy'; if(w<=100) return 'Extra Heavy'; if(w<=500) return 'Commercial'; return 'Industrial';}
function vehicleFor(w,size){ if(size==='large' || w>20) return 'Van'; if(w>5) return 'Car'; return 'Bike'; }
function dimsFor(w,size){ if(size==='large') return [100,50,40]; if(size==='medium') return [45,35,25]; return [25,18,8]; }
function entry(base, variant, category, index){
  const [name, est, min, max, cls, size, fragile] = base;
  const itemName = `${variant} ${name}`.replace(/\s+/g,' ').trim();
  const id = `${slug(category)}_${slug(itemName)}_${index}`;
  const highValue = /iphone|macbook|laptop|camera|playstation|xbox|nintendo|designer|jewellery|watch|secure|passport|diamond|luxury|art|e-bike|racing bicycle|company laptop/i.test(itemName);
  const requiresVanguard = highValue || /documents|passport|legal|contract|certificate|licence|prescription|medication/i.test(itemName);
  const [l,w,h]=dimsFor(est,size);
  return {id,itemName,aliases:[name.toLowerCase(), variant.toLowerCase(), `${name.toLowerCase()} parcel`, `${variant.toLowerCase()} ${name.toLowerCase()}`],category,estimatedWeightKg:est,minimumWeightKg:min,maximumWeightKg:max,weightClass:cls||weightClass(est),sizeClass:size,fragile,highValue,requiresVanguard,requiresIRISReview:max>=50 || /unknown|hazard|restricted/i.test(itemName),deliveryNotes:`${category} item. ${fragile?'Protect from impact.':'Standard handling.'} Recommended vehicle: ${vehicleFor(est,size)}.`,confidenceBaseline:highValue?0.9:0.78,typicalDimensionsCm:{length:l,width:w,height:h},vehicleSuitability:vehicleFor(est,size),stackable:!fragile && size!=='large'};
}
const items=[];
let idx=1;
for(const cat of categories){
  outer: for(const base of cat.base){
    for(const variant of cat.variants){
      if(items.length>=1000) break outer;
      if(items.filter(i=>i.category===cat.name).length>=cat.count) break outer;
      items.push(entry(base,variant,cat.name,idx++));
    }
  }
}
while(items.length<1000){
  const n=items.length+1;
  items.push({id:`general_delivery_item_${n}`,itemName:`General parcel type ${n}`,aliases:['parcel','package','delivery item'],category:'Other',estimatedWeightKg:2,minimumWeightKg:0.5,maximumWeightKg:5,weightClass:'Light',sizeClass:'small',fragile:false,highValue:false,requiresVanguard:false,requiresIRISReview:true,deliveryNotes:'Generic fallback item. Confirm details before dispatch.',confidenceBaseline:0.45,typicalDimensionsCm:{length:35,width:25,height:15},vehicleSuitability:'Bike',stackable:true});
}
if(items.length!==1000) throw new Error(`Expected 1000 items, got ${items.length}`);
const seen=new Set();
for(const item of items){ if(seen.has(item.itemName)) throw new Error(`Duplicate ${item.itemName}`); seen.add(item.itemName); }
function dartString(s){return JSON.stringify(String(s));}
const lines=[];
lines.push('// Generated by tools/generate_iris_repository.js.');
lines.push('// Keep this repository at exactly 1,000 non-duplicate entries.');
lines.push('class IrisRepositoryDimensions {');
lines.push('  final double lengthCm; final double widthCm; final double heightCm;');
lines.push('  const IrisRepositoryDimensions({required this.lengthCm, required this.widthCm, required this.heightCm});');
lines.push('}');
lines.push('class IrisRepositoryItem {');
lines.push('  final String id; final String itemName; final List<String> aliases; final String category; final double estimatedWeightKg; final double minimumWeightKg; final double maximumWeightKg; final String weightClass; final String sizeClass; final bool fragile; final bool highValue; final bool requiresVanguard; final bool requiresIRISReview; final String deliveryNotes; final double confidenceBaseline; final IrisRepositoryDimensions typicalDimensionsCm; final String vehicleSuitability; final bool stackable;');
lines.push('  const IrisRepositoryItem({required this.id, required this.itemName, required this.aliases, required this.category, required this.estimatedWeightKg, required this.minimumWeightKg, required this.maximumWeightKg, required this.weightClass, required this.sizeClass, required this.fragile, required this.highValue, required this.requiresVanguard, required this.requiresIRISReview, required this.deliveryNotes, required this.confidenceBaseline, required this.typicalDimensionsCm, required this.vehicleSuitability, required this.stackable});');
lines.push('}');
lines.push('class IrisItemRepository {');
lines.push('  static const int expectedItemCount = 1000;');
lines.push('  static const List<IrisRepositoryItem> items = [');
for(const item of items){
  lines.push('    IrisRepositoryItem(');
  lines.push(`      id: ${dartString(item.id)},`);
  lines.push(`      itemName: ${dartString(item.itemName)},`);
  lines.push(`      aliases: [${item.aliases.map(dartString).join(', ')}],`);
  lines.push(`      category: ${dartString(item.category)},`);
  lines.push(`      estimatedWeightKg: ${item.estimatedWeightKg},`);
  lines.push(`      minimumWeightKg: ${item.minimumWeightKg},`);
  lines.push(`      maximumWeightKg: ${item.maximumWeightKg},`);
  lines.push(`      weightClass: ${dartString(item.weightClass)},`);
  lines.push(`      sizeClass: ${dartString(item.sizeClass)},`);
  lines.push(`      fragile: ${item.fragile}, highValue: ${item.highValue}, requiresVanguard: ${item.requiresVanguard}, requiresIRISReview: ${item.requiresIRISReview},`);
  lines.push(`      deliveryNotes: ${dartString(item.deliveryNotes)},`);
  lines.push(`      confidenceBaseline: ${item.confidenceBaseline},`);
  lines.push(`      typicalDimensionsCm: IrisRepositoryDimensions(lengthCm: ${item.typicalDimensionsCm.length}, widthCm: ${item.typicalDimensionsCm.width}, heightCm: ${item.typicalDimensionsCm.height}),`);
  lines.push(`      vehicleSuitability: ${dartString(item.vehicleSuitability)}, stackable: ${item.stackable},`);
  lines.push('    ),');
}
lines.push('  ];');
lines.push('  static IrisRepositoryItem? match(String description) {');
lines.push('    final text = description.trim().toLowerCase();');
lines.push('    if (text.isEmpty) return null;');
lines.push('    IrisRepositoryItem? best; int bestScore = 0;');
lines.push('    for (final item in items) {');
lines.push('      final terms = [item.itemName.toLowerCase(), ...item.aliases.map((alias) => alias.toLowerCase())];');
lines.push('      for (final term in terms) {');
lines.push('        if (term.isEmpty) continue;');
lines.push('        final score = text == term ? term.length + 100 : text.contains(term) ? term.length : 0;');
lines.push('        if (score > bestScore) { best = item; bestScore = score; }');
lines.push('      }');
lines.push('    }');
lines.push('    return best;');
lines.push('  }');
lines.push('}');
fs.writeFileSync(path.join('lib','app','iris','iris_item_repository.dart'), lines.join('\n'));
console.log(`Generated ${items.length} IRIS items`);
