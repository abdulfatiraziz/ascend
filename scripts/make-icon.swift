import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes = [(16,"icon_16x16.png"),(32,"icon_16x16@2x.png"),(32,"icon_32x32.png"),(64,"icon_32x32@2x.png"),
             (128,"icon_128x128.png"),(256,"icon_128x128@2x.png"),(256,"icon_256x256.png"),(512,"icon_256x256@2x.png"),
             (512,"icon_512x512.png"),(1024,"icon_512x512@2x.png")]
for (pixels,name) in sizes {
    let image = NSImage(size: NSSize(width: pixels,height: pixels), flipped: false) { rect in
        let scale = CGFloat(pixels)/1024
        NSGraphicsContext.current?.cgContext.scaleBy(x: scale,y: scale)
        let background = NSBezierPath(roundedRect: NSRect(x: 30,y:30,width:964,height:964),xRadius:210,yRadius:210)
        NSColor(red:0.055,green:0.047,blue:0.075,alpha:1).setFill(); background.fill()
        NSColor(red:0.2,green:0.16,blue:0.3,alpha:1).setStroke(); background.lineWidth=6;background.stroke()
        let a: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:640,weight:.bold),.foregroundColor:NSColor(white:0.95,alpha:1)]
        ("A" as NSString).draw(at:NSPoint(x:210,y:110),withAttributes:a)
        let arrow: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:300,weight:.medium),.foregroundColor:NSColor(red:0.64,green:0.54,blue:1,alpha:1)]
        ("↗" as NSString).draw(at:NSPoint(x:610,y:480),withAttributes:arrow)
        return true
    }
    guard let tiff=image.tiffRepresentation, let rep=NSBitmapImageRep(data:tiff), let data=rep.representation(using:.png,properties:[:]) else { fatalError("Icon render failed") }
    try data.write(to:output.appendingPathComponent(name))
}
