import AppKit
import Foundation

@MainActor
enum SidecarBrand {
    static let dockImage: NSImage = {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns", subdirectory: "Icons"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing bundled Dock icon")
        }
        image.isTemplate = false
        return image
    }()

    static let menuBarImage: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        for name in ["MenuBarIcon", "MenuBarIcon@2x"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Icons"),
                  let data = try? Data(contentsOf: url),
                  let representation = NSBitmapImageRep(data: data) else {
                preconditionFailure("Missing bundled menu-bar icon: \(name)")
            }
            representation.size = size
            image.addRepresentation(representation)
        }
        image.isTemplate = true
        return image
    }()
}
