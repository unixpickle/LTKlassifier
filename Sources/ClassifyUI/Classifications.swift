import Charts
import LTKLabel
import SwiftUI

struct Classifications: View {
  struct TableField: Identifiable {
    var id: String { "\(field)" }

    var field: Field
  }

  struct BarValue: Identifiable {
    var id: String { "\(name)" }

    var name: String
    var value: Float
  }

  var modelOutput: [Field: [Float]]
  @Binding var selectedField: Set<String>

  var body: some View {
    let allFields = LabelDescriptor.allLabels.keys.map { TableField(field: $0) }.sorted {
      $0.id < $1.id
    }
    HStack {
      Table(allFields, selection: $selectedField) { TableColumn("field", value: \.id) }.frame(
        width: 150.0
      )
      if selectedField.count == 1 {
        let selectedID = Array(selectedField).first!
        let field = allFields.filter { $0.id == selectedID }.first!
        if let values = modelOutput[field.field] {
          let bars = zip(field.field.valueNames(), values).map { (name, value) in
            BarValue(name: name, value: value)
          }
          ScrollView(.horizontal) {
            Chart {
              ForEach(bars) { bar in
                BarMark(x: .value("Value", bar.name), y: .value("Probability", bar.value))
              }
            }.frame(width: max(200.0, 50 * CGFloat(bars.count)))
          }
        }
      }
    }
  }
}
