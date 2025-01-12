import HCBacktrace
import Honeycrisp
import ImageUtils
import LTKLabel
import LTKModel
import SwiftUI

enum ImageError: Error { case failedToDecodeImage }

@main struct ClassifyUI: App {
  struct ModelState: Codable { var model: Trainable.State }

  init() {
    do { Backend.defaultBackend = try MPSBackend() } catch {
      print("[ERROR] failed to create MPSBackend")
    }
    DispatchQueue.main.async {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
  }

  @State var pickingModel = false
  @State var loadingModel = false
  @State var modelLoadError: String? = nil
  @State var model: Model? = nil

  @State var pickingImage = false
  @State var classifyingImage = false
  @State var classifyError: String? = nil
  @State var image: Image? = nil

  @State var modelOutput: [Field: [Float]]? = nil
  @State var selectedField: Set<String> = Set(["\(Field.ltkTotalDollars)"])

  var body: some Scene {
    WindowGroup {
      VStack {
        VStack {
          Button {
            pickingModel = true
          } label: {
            Text("Pick Model")
          }.disabled(loadingModel).fileImporter(
            isPresented: $pickingModel,
            allowedContentTypes: [.propertyList],
            allowsMultipleSelection: false,
            onCompletion: { results in
              switch results {
              case .success(let fileURLs):
                #alwaysAssert(fileURLs.count == 1)
                let url = fileURLs.first!
                Task { await self.loadModel(url) }
              case .failure(let error): modelLoadError = "Failed to load model: \(error)"
              }
            }
          )

          if loadingModel { ProgressView() }
          if let err = modelLoadError { Text(err).foregroundStyle(.red) }

          if model != nil {
            Button {
              pickingImage = true
            } label: {
              Text("Classify Image")
            }.disabled(classifyingImage).fileImporter(
              isPresented: $pickingImage,
              allowedContentTypes: [.image],
              allowsMultipleSelection: false,
              onCompletion: { results in
                switch results {
                case .success(let fileURLs):
                  #alwaysAssert(fileURLs.count == 1)
                  let url = fileURLs.first!
                  Task { await self.classifyImage(url) }
                case .failure(let error): classifyError = "Failed to load model: \(error)"
                }
              }
            )

            if classifyingImage { ProgressView() }
            if let err = classifyError { Text(err).foregroundStyle(.red) }
            if let image = image { image.resizable().frame(maxWidth: 128, maxHeight: 128) }
            if let modelOutput = modelOutput {
              Classifications(modelOutput: modelOutput, selectedField: $selectedField)
            }
          }
        }
      }.padding(10.0)
    }
  }

  func loadModel(_ url: URL) async {
    defer { loadingModel = false }
    loadingModel = true
    do {
      let decoded = try await withUnsafeThrowingContinuation { continuation in
        do {
          let data = try Data(contentsOf: url)
          let decoder = PropertyListDecoder()
          continuation.resume(returning: try decoder.decode(ModelState.self, from: data))
        } catch { continuation.resume(throwing: error) }
      }
      let m = Model(labels: LabelDescriptor.allLabels)
      try m.loadState(decoded.model)
      print("model has been loaded")
      model = m
    } catch { modelLoadError = "Failed to load model: \(error)" }
  }

  func classifyImage(_ url: URL) async {
    defer { classifyingImage = false }
    classifyingImage = true
    do {
      let imageTensor: Tensor = try await withUnsafeThrowingContinuation { continuation in
        do {
          let data = try Data(contentsOf: url)
          if let tensor = loadImage(data, imageSize: 224, augment: false) {
            continuation.resume(returning: tensor)
          } else {
            continuation.resume(throwing: ImageError.failedToDecodeImage)
          }
        } catch { continuation.resume(throwing: error) }
      }
      image = Image(nsImage: NSImage(byReferencing: url))
      if let model = model {
        let output = model(imageTensor[NewAxis()])
        var outs: [Field: [Float]] = [:]
        for (k, v) in output {
          if case .categorical = LabelDescriptor.allLabels[k]! {
            outs[k] = try await v.softmax().floats()
          } else {
            outs[k] = try await v.sigmoid().floats()
          }
        }
        modelOutput = outs
      }
    } catch { classifyError = "Failed to load model: \(error)" }
  }
}
