import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = NSImage(size: NSSize(width: 1024, height: 1024))

iconset.lockFocus()
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 800)
]
let str = "📝" as NSString
let strSize = str.size(withAttributes: attrs)
let point = NSPoint(x: (1024 - strSize.width) / 2, y: (1024 - strSize.height) / 2)
str.draw(at: point, withAttributes: attrs)
iconset.unlockFocus()

// Create iconset directory
let fm = FileManager.default
let iconsetDir = "/private/tmp/claude-501/Waxpad.iconset"
try? fm.removeItem(atPath: iconsetDir)
try! fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for size in sizes {
    for scale in [1, 2] {
        let pixelSize = size * scale
        if pixelSize > 1024 { continue }
        let resized = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
        resized.lockFocus()
        iconset.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { continue }

        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try! png.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name)"))
    }
}

print("Iconset created at \(iconsetDir)")
