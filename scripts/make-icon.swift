import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let inset = NSRect(origin: .zero, size: size).insetBy(dx: 100, dy: 100)
let background = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
NSGradient(
    starting: NSColor(calibratedRed: 0.86, green: 0.47, blue: 0.33, alpha: 1),
    ending: NSColor(calibratedRed: 0.55, green: 0.24, blue: 0.17, alpha: 1)
)?.draw(in: background, angle: -90)
let configuration = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(configuration) {
    let symbolSize = symbol.size
    let origin = NSPoint(x: (size.width - symbolSize.width) / 2, y: (size.height - symbolSize.height) / 2)
    symbol.draw(in: NSRect(origin: origin, size: symbolSize))
}
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
