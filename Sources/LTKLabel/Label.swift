public enum LabelDescriptor: Sendable {
  public static let allLabels = [
    "kind": LabelDescriptor.categorical(ImageKind.count),
    "product_price": LabelDescriptor.categorical(PriceRange.count),
  ]

  case categorical(Int)
  case bitset(Int)

  public var channelCount: Int {
    switch self {
    case .categorical(let count): count
    case .bitset(let count): count
    }
  }
}

public enum Label: Sendable {
  case categorical(count: Int, label: Int)
  case bitset([Bool])

  public var descriptor: LabelDescriptor {
    switch self {
    case .categorical(let count, _): .categorical(count)
    case .bitset(let bits): .bitset(bits.count)
    }
  }
}

public enum ImageKind: Int, CustomStringConvertible {
  public static let fieldName = "kind"
  public static let count = 2

  case product = 0
  case ltk = 1

  public var description: String {
    switch self {
    case .product: "product"
    case .ltk: "ltk"
    }
  }
}

public enum PriceRange: Int, CustomStringConvertible {
  public static let count = 16

  case lessThan1 = 0
  case lessThan5 = 1
  case lessThan10 = 2
  case lessThan20 = 3
  case lessThan50 = 4
  case lessThan100 = 5
  case lessThan250 = 6
  case lessThan500 = 7
  case lessThan1000 = 8
  case lessThan2000 = 9
  case lessThan5000 = 10
  case lessThan10000 = 11
  case lessThan25000 = 12
  case lessThan50000 = 13
  case lessThan100000 = 14
  case atLeast100000 = 15

  public var description: String {
    switch self {
    case .lessThan1: "<$1"
    case .lessThan5: "$1-5"
    case .lessThan10: "$5-10"
    case .lessThan20: "$10-20"
    case .lessThan50: "$20-50"
    case .lessThan100: "$50-100"
    case .lessThan250: "$100-250"
    case .lessThan500: "$250-500"
    case .lessThan1000: "$500-1000"
    case .lessThan2000: "$1000-2000"
    case .lessThan5000: "$2000-5000"
    case .lessThan10000: "$5000-10000"
    case .lessThan25000: "$10000-25000"
    case .lessThan50000: "$25000-50000"
    case .lessThan100000: "$50000-100000"
    case .atLeast100000: ">$100000"
    }
  }

  public static func from(price: Double) -> Self {
    switch price {
    case ..<1: .lessThan1
    case 1..<5: .lessThan5
    case 5..<10: .lessThan10
    case 10..<20: .lessThan20
    case 20..<50: .lessThan50
    case 50..<100: .lessThan100
    case 100..<250: .lessThan250
    case 250..<500: .lessThan500
    case 500..<1000: .lessThan1000
    case 1000..<2000: .lessThan2000
    case 2000..<5000: .lessThan5000
    case 5000..<10000: .lessThan10000
    case 10000..<25000: .lessThan25000
    case 25000..<50000: .lessThan50000
    case 50000..<100000: .lessThan100000
    default: .atLeast100000
    }
  }
}
