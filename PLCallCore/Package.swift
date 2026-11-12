// swift-tools-version:6.0
import PackageDescription

// The plain logic of the Call app: no UIKit, no audio, no network. It compiles and is tested on Linux
// in CI (logic.yml) so mistakes surface in a minute without a Mac; the app target compiles the same files.
let package = Package(
    name: "PLCallCore",
    products: [.library(name: "PLCallCore", targets: ["PLCallCore"])],
    targets: [
        .target(name: "PLCallCore"),
        .testTarget(name: "PLCallCoreTests", dependencies: ["PLCallCore"]),
    ]
)
