import ArgumentParser

@main struct BrowseCommand: AsyncParsableCommand {

  @ArgumentParser.Option(name: .shortAndLong, help: "Port to listen on.") var port: Int
  @ArgumentParser.Option(name: .long, help: "Path to database.") var dbPath: String
  @ArgumentParser.Option(name: .long, help: "Path to load the model from.") var modelPath: String =
    "model_state.plist"
  @ArgumentParser.Option(name: .long, help: "Directory to load shards from.") var featureDir:
    String = "features"
  @ArgumentParser.Option(name: .long, help: "Path to save clusters.") var clusterPath: String =
    "clusters.plist"
  @ArgumentParser.Flag(name: .long, help: "Only show products with prices.") var priceOnly: Bool =
    false

  // Rate limiting
  @ArgumentParser.Option(
    name: .long,
    help: "Number of reverse proxies that this server sits behind."
  ) var proxyCount: Int = 0
  @ArgumentParser.Option(
    name: .long,
    help: "Maximum number of calls to the neighbors endpoint in an hour."
  ) var maxNeighborsPerHour: Int = 1000
  @ArgumentParser.Option(
    name: .long,
    help: "Maximum number of calls to the encode endpoint in an hour."
  ) var maxEncodesPerHour: Int = 1000

  mutating func run() async {
    do {
      let server = try await Server(
        port: port,
        dbPath: dbPath,
        modelPath: modelPath,
        featureDir: featureDir,
        clusterPath: clusterPath,
        priceOnly: priceOnly,
        proxyCount: proxyCount,
        maxNeighborsPerHour: maxNeighborsPerHour,
        maxEncodesPerHour: maxEncodesPerHour
      )
      try await server.app.execute()
    } catch { print("fatal error: \(error)") }
  }

}
