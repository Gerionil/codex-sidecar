import AppKit
import Foundation

@MainActor
enum SidecarBrand {
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
