public enum Currency {
  case usd
  case eur
  case gbp
  case php
  case aud
  case sgd
  case cad
  case nok
  case brl
  case chf
  case clp
  case mxn
  case vnd
  case hkd
  case sek
  case uah
  case ils
  case tryy
  case aed

  static func parse(_ x: String) -> Self? {
    switch x {
    case "USD": .usd
    case "EUR": .eur
    case "GBP": .gbp
    case "PHP": .php
    case "AUD": .aud
    case "SGD": .sgd
    case "CAD": .cad
    case "NOK": .nok
    case "BRL": .brl
    case "CHF": .chf
    case "CLP": .clp
    case "MXN": .mxn
    case "VND": .vnd
    case "HKD": .hkd
    case "SEK": .sek
    case "UAH": .uah
    case "ILS": .ils
    case "TRY": .tryy
    case "AED": .aed
    default: nil
    }
  }

  /// Unit conversion based on exchange rates on Dec 29, 2024.
  func intoDollars(_ x: Double) -> Double {
    switch self {
    case .usd: x
    case .eur: x / 0.9589
    case .gbp: x / 0.7951
    case .php: x / 57.899
    case .aud: x / 1.6068
    case .sgd: x / 1.3581
    case .cad: x / 1.4405
    case .nok: x / 11.0019
    case .brl: x / 5.0
    case .chf: x / 0.9017
    case .clp: x / 900.0
    case .mxn: x / 20.333
    case .vnd: x / 23000.0
    case .hkd: x / 7.7656
    case .sek: x / 10.5
    case .uah: x / 27.0
    case .ils: x / 3.5
    case .tryy: x / 25.0
    case .aed: x / 3.6725
    }
  }
}
