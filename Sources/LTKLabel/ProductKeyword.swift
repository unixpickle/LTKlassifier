public struct ProductKeyword {
  public static let items = [
    "women's", "women", "dress", "set", "gold", "long", "sleeve", "bag", "black", "christmas",
    "mini", "sweater", "high", "leather", "top", "white", "faux", "earrings", "knit", "neck",
    "womens", "boots", "wide", "jacket", "jeans", "casual", "pants", "necklace", "oversized",
    "shoulder", "coat", "bow", "soft", "skirt", "holiday", "leg", "maxi", "pullover", "tree",
    "cotton", "hair", "classic", "size", "vintage", "lip", "light", "ankle", "baby", "chunky",
    "pillow", "large", "red", "short", "toe", "fall", "winter", "cream", "midi", "small", "boot",
    "gift", "shoes", "sequin", "table", "tote", "tops", "satin", "pink", "pack", "ribbed", "glass",
    "cardigan", "velvet", "green", "sizes", "silver", "square", "bracelet", "brown", "blue",
    "sweatshirt", "piece", "suede", "home", "party", "crew", "fashion", "waist", "fur", "rise",
    "wood", "fleece", "(women)", "kids", "shirt", "storage", "wall", "natural", "round", "solid",
    "toddler", "travel", "double", "plated", "heel", "candle", "wool", "14k", "sunglasses",
    "cropped", "throw", "denim", "print", "belt", "platform", "floral", "heels", "jean", "button",
    "tank", "stainless", "cozy", "steel", "women,", "crossbody", "socks", "metal", "trendy", "ring",
    "crewneck", "set,", "zip", "shorts", "plus", "front", "turtleneck", "ladies", "decorative",
    "warm", "lightweight", "woven", "open", "hoop", "ceramic", "straight", "fit", "purse", "chain",
    "cover", "coffee", "sandals", "crop", "clear", "body", "beauty", "artificial", "leggings",
    "sneaker", "sleeveless", "waisted", "slim", "t-shirt", "pointed", "linen", "face", "rhinestone",
    "plaid", "men", "lace", "summer", "color", "medium", "modern", "gown", "makeup", "pant", "rug",
    "men's", "retro", "wedding", "strap", "loose", "pendant", "low", "handbag", "women’s",
    "sneakers", "cute", "clutch", "stretch", "pearl", "tee", "girls", "slippers", "water", "mesh",
    "quilted", "crystal", "ultra", "beige", "bags", "hat", "foam", "heart", "down", "adjustable",
    "pajama", "outfits", "wooden", "drop", "blanket", "dark", "cable", "sexy", "sweaters", "full",
    "skin", "yoga", "blazer", "knee", "holder", "slingback", "sets", "puffer", "portable", "vest",
    "slip", "wrap", "kitchen", "lounge", "bra", "gifts", "back", "pairs", "lamp", "high-rise",
    "toy", "cashmere", "bed", "workout", "tall", "eye", "box", "case", "frame", "organizer",
    "pleated", "memory", "graphic", "tie", "barrel", "decor", "matte", "ribbon", "flats", "house",
    "oil", "jewelry", "glasses", "mirror", "premium", "shirts", "flat", "mid", "collar", "block",
    "brass", "glow", "hot", "flower", "side", "bodycon", "stud", "ruffle", "striped", "silk",
    "glitter", "star", "ivory", "tumbler", "handle", "rose", "blush", "indoor", "air", "scoop",
    "beaded", "mug", "metallic", "hand", "pine", "wild", "bodysuit", "embroidered", "waterproof",
    "hoodie", "outdoor", "jumpsuit", "pumps", "seamless", "lined", "wine", "straw", "thick",
    "brush", "mock", "flare", "strapless", "girl", "chair", "real", "pocket", "stand", "relaxed",
    "sheer", "buckle", "zipper", "ball", "plush", "plastic", "dream", "paper", "balm", "western",
    "control", "watch", "liquid", "parfum", "long-sleeve", "wide-leg", "sandal", "18k", "ruched",
    "lights", "shoe", "area", "v-neck", "vegan", "cloud", "deep", "marble", "baggy", "cocktail",
    "waffle", "bottle", "knitted", "spray", "oval", "canvas", "cap", "ballet", "organic", "pump",
    "ornament", "board", "slipper", "handmade", "upholstered", "running", "fuzzy", "sherpa",
    "diamond", "serum", "vase", "basic", "elegant", "beach", "toys", "garland", "grey", "elastic",
    "band", "dresses", "dainty", "printed", "night", "powder", "pockets", "unisex", "stripe",
    "style", "leopard", "rib", "day", "textured", "basket", "insole", "little", "scarf", "olive",
    "hydrating", "skinny", "tray", "kitten", "slide", "silicone", "tennis", "crate", "high-waisted",
    "tights", "dry", "heeled", "statement", "luxury", "nail", "hem", "lid", "sparkly", "gray",
    "premium-quality", "sleep", "bridesmaid", "dreamy", "square-neck", "orange", "genuine",
    "charcuterie", "no-slip", "lace-up", "racerback", "panties", "royal", "airbrush", "patterned",
    "pencil", "outfit", "capri", "teardrop", "indigo", "trim", "trays", "seam", "bangles",
    "trainers", "cross", "nude", "reusable", "soap", "curly", "bride", "thong", "authentic",
    "cotton-blend", "bottoms", "solid-color", "totebags", "ruffs", "bean", "hexagon", "plum",
    "ziplocked", "purple", "ornate", "muffin", "narrow", "rustic", "kettle", "perfumed", "buttered",
    "bronze", "walnut", "beveled", "scalloped", "neutral", "coral", "tassled", "studded",
    "sparkling", "glimmery", "pearlized", "streamlined", "synchronized", "skating", "grip-tied",
    "portable-storage", "ergonomic", "micro-comedonal", "cable-knit", "leatherette", "polyurethane",
    "nylon-belt", "sterling-silver", "huggies", "timber", "skater", "waterline", "timeless",
    "escutcheon", "needle", "mohair", "parchment", "chambray", "wide-spaced", "rosette", "coated",
    "magnetic", "reversable", "rugged", "well-heeled", "glazed", "blueberry", "cloud-colored",
    "unbreakable", "fragranced", "sustainable", "versatile", "aubergine", "kaleidoscope", "crimped",
    "beater", "tailored", "yellow",
  ]

  public static let mapping = Dictionary(
    uniqueKeysWithValues: items.enumerated().map { ($0.1, $0.0) }
  )

  public static let count: Int = items.count

  public static func label(_ x: String) -> Int? { mapping[x.lowercased()] }
}