import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
let lines = ["pant", "size"]
/// Metronome と同じ条件（98.5% 幅）で metro/nome に合わせた字号（行間は lineGapRatio）
let referenceLines = ["metro", "nome"]
let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png"

let targetWidth = canvas * 0.985
let lineGapRatio: CGFloat = -0.4

func preferredFont(size: CGFloat) -> NSFont {
    let names = [
        "HelveticaNeue-CondensedBlack",
        "Arial-Black",
        "HelveticaNeue-Bold",
        "Arial-BoldMT",
        "Helvetica-Bold",
    ]
    for name in names {
        if let f = NSFont(name: name, size: size) { return f }
    }
    return NSFont.boldSystemFont(ofSize: size)
}

func textBlockSize(lines: [String], font: NSFont, lineGapRatio: CGFloat) -> (maxWidth: CGFloat, totalHeight: CGFloat) {
    var maxW: CGFloat = 0
    var totalH: CGFloat = 0
    for (i, line) in lines.enumerated() {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let s = NSAttributedString(string: line, attributes: attrs)
        let rect = s.boundingRect(
            with: NSSize(width: 4000, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        maxW = max(maxW, ceil(rect.width))
        totalH += ceil(rect.height)
        if i == 0 { totalH += font.pointSize * lineGapRatio }
    }
    return (maxW, totalH)
}

func fittedFontSize(for referenceLines: [String]) -> CGFloat {
    var fontSize: CGFloat = 200
    var lo: CGFloat = 60
    var hi: CGFloat = 700
    while lo <= hi {
        let mid = (lo + hi) / 2
        let font = preferredFont(size: mid)
        let (w, _) = textBlockSize(lines: referenceLines, font: font, lineGapRatio: lineGapRatio)
        if w <= targetWidth {
            fontSize = mid
            lo = mid + 0.5
        } else {
            hi = mid - 0.5
        }
    }
    return fontSize
}

let fontSize = fittedFontSize(for: referenceLines)
let font = preferredFont(size: fontSize)
let (_, blockH) = textBlockSize(lines: lines, font: font, lineGapRatio: lineGapRatio)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create context\n", stderr)
    exit(1)
}

ctx.setFillColor(NSColor.white.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

var y = (canvas + blockH) / 2
for (i, line) in lines.enumerated() {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.black,
    ]
    let s = NSAttributedString(string: line, attributes: attrs)
    let rect = s.boundingRect(
        with: NSSize(width: 4000, height: 4000),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let w = ceil(rect.width)
    let h = ceil(rect.height)
    y -= h
    let x = (canvas - w) / 2
    s.draw(
        with: NSRect(x: x, y: y, width: w, height: h),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    if i == 0 { y -= font.pointSize * lineGapRatio }
}

NSGraphicsContext.restoreGraphicsState()

guard let cgImage = ctx.makeImage() else {
    fputs("Failed to make image\n", stderr)
    exit(1)
}

let rep = NSBitmapImageRep(cgImage: cgImage)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to export PNG\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: outPath)
try png.write(to: url)
fputs(
    "Wrote \(url.path) fontSize=\(fontSize) (metronome reference) font=\(font.fontName)\n",
    stderr
)
