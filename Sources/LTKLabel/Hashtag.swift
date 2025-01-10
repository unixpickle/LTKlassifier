public struct Hashtag {
  public static let values: [String] = [
    "#ltkstyletip", "#ltkseasonal", "#ltkholiday", "#ltkgiftguide", "#ltkhome", "#ltksalealert",
    "#ltkfindsunder50", "#ltkfindsunder100", "#ltkbeauty", "#ltkkids", "#ltkfamily", "#liketkit",
    "#ltkshoecrush", "#ltkcyberweek", "#ltktravel", "#ltkunder50", "#ltkover40", "#ltkmidsize",
    "#ltkworkwear", "#ltkbaby", "#ltkparties", "#ltkactive", "#ltkvideo", "#ltkunder100",
    "#ltkwatchnow", "#ltkfitness", "#ltkeurope", "#ltku", "#ltkitbag", "#ltkfind", "#ltkwedding",
    "#ltkbump", "#ltkplussize", "#ltkswim", "#ltkfit", "#ltkuk", "#ltkfallsale", "#ltkmens",
    "#ltkautumn", "#ad", "#ltkbacktoschool", "#ltkwinter", "#ltkcurves", "#ootd", "#ltkhalloween",
    "#ltksale", "#ltksummersales", "#ltkcanada", "#ltksummer", "#amazonfinds", "#target",
    "#ltkspringsale", "#amazon", "#homedecor", "#ltkaustralia", "#ltkbrasil", "#ltkxnsale",
    "#stayhomewithltk", "#ltkmostloved", "#ltkpartywear", "#amazonfashion", "#ltkxprimeday",
    "#fallfashion", "#christmas", "#giftguide", "#walmart", "#founditonamazon", "#targetstyle",
    "#ltkrefresh", "#targetpartner", "#fall", "#fashion", "#walmartpartner", "#ltkholidaysale",
    "#ltkspring", "#ltkdeutschland", "#makeup", "#sale", "#amazonhome", "#outfitinspo",
    "#ltkfestival", "#christmasdecor", "#targetfinds", "#ltkbeleza", "#giftideas", "#home", "#ltk",
    "#fallstyle", "#walmartfashion", "#falloutfits", "#skincare", "#wayfair", "#abercrombie",
    "#winterfashion", "#ltkluxury", "#boots", "#walmartfinds", "#blackfriday", "#summerstyle",
    "#outfitideas", "#summer", "#ltkgiftspo", "#giftsforher", "#nordstrom", "#amazonholiday",
    "#ltkxsephora", "#holiday", "#ltknyfw", "#holidayoutfit", "#interiordesign", "#bohodecor",
    "#decor", "#ltkshoes", "#style", "#ltkfall", "#comfystyle", "#aestheticstyle", "#gifts",
    "#nsale", "#blazers", "#dress", "#workwear", "#holidaydecor", "#itksalealert", "#ltkxtarget",
    "#falloutfit", "#ltkmodest", "#holidaystyle",
  ]

  public static let count: Int = values.count

  public static func label(_ x: String) -> Int? { values.firstIndex(of: x) }
}
