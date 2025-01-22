import SwiftUI

struct BarGraph: View {
  struct Item: Identifiable {
    var name: String
    var value: Double

    var id: String { name }
  }

  var values: [Item]
  var sort: Bool

  var body: some View {
    let maxValue = values.reduce(0.0) { x, y in max(x, y.value) }
    VStack {
      ForEach(!sort ? values : values.sorted { $0.value > $1.value }) { x in
        let fraction = x.value / maxValue
        VStack(spacing: 0) {
          HStack {
            Text(x.name).frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.2f%%", x.value * 100)).frame(alignment: .trailing)
              .foregroundColor(Color(.systemGray))
          }
          HStack {
            GeometryReader { geometry in
              ZStack(alignment: .leading) {
                Rectangle().fill(Color.gray.opacity(0.5)).frame(height: 10)
                Rectangle().fill(Color.blue).frame(
                  width: geometry.size.width * fraction,
                  height: 10
                )
              }.cornerRadius(5)
            }
          }
        }
      }
    }
  }
}
