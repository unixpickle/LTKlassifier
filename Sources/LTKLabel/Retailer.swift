public struct Retailer {
  public static let mapping: [String: String] = [
    "Amazon (US)": "Amazon", "Target": "Target", "Walmart (US)": "Walmart",
    "Nordstrom": "Nordstrom", "Revolve Clothing (Global)": "Revolve Clothing",
    "Abercrombie & Fitch (US)": "Abercrombie & Fitch", "Sephora (US)": "Sephora",
    "Anthropologie (US)": "Anthropologie", "Etsy (US)": "Etsy", "Wayfair North America": "Wayfair",
    "Old Navy (US)": "Old Navy", "Lululemon (US)": "Lululemon", "ASOS (Global)": "ASOS",
    "Free People (Global - UK&FR Excluded)": "Free People", "H&M (US + CA)": "H&M",
    "Shopbop": "Shopbop", "Saks Fifth Avenue": "Saks Fifth Avenue", "SHEIN": "SHEIN",
    "Pottery Barn (US)": "Pottery Barn", "Ulta": "Ulta",
    "American Eagle Outfitters (US & CA)": "American Eagle Outfitters", "Aritzia": "Aritzia",
    "Macy's": "Macy's", "Bloomingdale's (US)": "Bloomingdale's", "J. Crew US": "J. Crew",
    "H&M (UK, MY, IN, SG, PH, TW, HK)": "H&M", "Lulus": "Lulus", "Aerie": "Aerie",
    "Madewell": "Madewell", "LOFT": "LOFT", "Gap (US)": "Gap", "Kohl's": "Kohl's",
    "Crate & Barrel": "Crate & Barrel", "VICI Collection": "VICI Collection",
    "Neiman Marcus": "Neiman Marcus", "Altar'd State": "Altar'd State",
    "Tuckernuck (US)": "Tuckernuck", "Nordstrom Rack": "Nordstrom Rack", "Quince": "Quince",
    "J.Crew Factory": "J.Crew Factory", "Spanx": "Spanx", "CB2": "CB2", "Dillard's": "Dillard's",
    "TJ Maxx": "TJ Maxx", "BaubleBar (US)": "BaubleBar", "Express": "Express",
    "adidas (US)": "adidas", "DSW": "DSW", "The Home Depot": "The Home Depot", "Nike (US)": "Nike",
    "NET-A-PORTER (US)": "NET-A-PORTER", "West Elm (US)": "West Elm", "Amazon (CA)": "Amazon",
    "FASHIONPHILE (US)": "FASHIONPHILE", "Serena and Lily": "Serena and Lily",
    "Alo Yoga (US)": "Alo Yoga", "eBay US": "eBay", "Kendra Scott": "Kendra Scott",
    "H&M (DE, AT, CH, NL, FI)": "H&M", "Mango (US/MX/AU)": "Mango",
    "The Willow Tree Boutique": "The Willow Tree Boutique", "MANGO (UK)": "MANGO",
    "Farfetch Global": "Farfetch Global", "Confête": "Confête",
    "H&M (DE, AT, DK, NL, NO, FI)": "H&M", "Pottery Barn Kids": "Pottery Barn Kids",
    "Marks & Spencer (UK)": "Marks & Spencer", "Dick's Sporting Goods": "Dick's Sporting Goods",
    "UGG (US)": "UGG", "World Market": "World Market", "SKIMS (US)": "SKIMS", "Lowe's": "Lowe's",
    "Urban Outfitters (US and RoW)": "Urban Outfitters", "Michaels Stores": "Michaels Stores",
    "Evereve": "Evereve", "DolceVita.com": "DolceVita.com", "MESHKI US": "MESHKI",
    "Zappos": "Zappos", "Gucci (US)": "Gucci", "MANGO (US)": "MANGO", "Ana Luisa": "Ana Luisa",
    "Arhaus": "Arhaus", "tarte cosmetics (US)": "tarte cosmetics", "Pink Lily": "Pink Lily",
    "Steve Madden (US)": "Steve Madden", "Amazon (UK)": "Amazon", "Ann Taylor (US)": "Ann Taylor",
    "Alo Yoga": "Alo Yoga", "Stanley PMI US": "Stanley PMI", "Best Buy U.S.": "Best Buy",
    "Mytheresa (US/CA)": "Mytheresa", "McGee & Co. (US)": "McGee & Co.",
    "Lulu and Georgia ": "Lulu and Georgia", "Carter's Inc": "Carter's Inc",
    "NET-A-PORTER (UK & EU)": "NET-A-PORTER", "Massimo Dutti UK": "Massimo Dutti",
    "Mark and Graham": "Mark and Graham", "Dress Up": "Dress Up", "Forever 21": "Forever 21",
    "24S US": "24S", "PrettyLittleThing US": "PrettyLittleThing", "Marshalls": "Marshalls",
    "Williams-Sonoma": "Williams-Sonoma", "Princess Polly US": "Princess Polly",
    "Dynamite Clothing": "Dynamite Clothing", "Avara": "Avara", "Sam Edelman": "Sam Edelman",
    "& Other Stories (EU + UK)": "& Other Stories", "Everlane": "Everlane", "H&M (US)": "H&M",
    "New Balance Athletics, Inc.": "New Balance Athletics, Inc.",
    "Melinda Maria Jewelry": "Melinda Maria Jewelry", "Cupshe US": "Cupshe",
    "Sezane Paris - US": "Sezane Paris", "Banana Republic Factory": "Banana Republic Factory",
    "Maison Blonde": "Maison Blonde", "Poshmark": "Poshmark",
    "Pottery Barn Teen": "Pottery Barn Teen", "J.Crew US": "J.Crew", "H&M (FR & IT & ES)": "H&M",
    "Belk": "Belk", "SSENSE": "SSENSE", "Maurices": "Maurices",
    "Banana Republic (US)": "Banana Republic", "DIBS Beauty": "DIBS Beauty",
    "Vuori Clothing (US & Canada)": "Vuori Clothing", "The RealReal": "The RealReal",
    "McGee & Co.": "McGee & Co.",
  ]

  public static let canonicalNames: [String] = Set(mapping.values).sorted()
  public static let count: Int = canonicalNames.count + 1

  public static func label(_ x: String) -> Int {
    if let canon = mapping[x], let index = canonicalNames.firstIndex(of: canon) {
      return index + 1
    } else {
      return 0
    }
  }
}
