import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: root.appendingPathComponent("MacGuardian.iconset"), withIntermediateDirectories: true)
func logo(_ rect: NSRect) {
    let base = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.23, yRadius: rect.height * 0.23)
    NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.32, blue: 0.71, alpha: 1), ending: NSColor(calibratedRed: 0.20, green: 0.86, blue: 0.71, alpha: 1))!.draw(in: base, angle: 65)
    let x = rect.minX, y = rect.minY, s = rect.width
    let shield = NSBezierPath(); shield.move(to: NSPoint(x:x+s*0.5,y:y+s*0.18)); shield.curve(to: NSPoint(x:x+s*0.78,y:y+s*0.68), controlPoint1: NSPoint(x:x+s*0.80,y:y+s*0.35), controlPoint2: NSPoint(x:x+s*0.78,y:y+s*0.53)); shield.line(to: NSPoint(x:x+s*0.5,y:y+s*0.82)); shield.line(to: NSPoint(x:x+s*0.22,y:y+s*0.68)); shield.curve(to: NSPoint(x:x+s*0.5,y:y+s*0.18), controlPoint1: NSPoint(x:x+s*0.22,y:y+s*0.53), controlPoint2: NSPoint(x:x+s*0.20,y:y+s*0.35)); shield.close()
    NSColor.white.withAlphaComponent(0.96).setStroke(); shield.lineWidth=s*0.042; shield.stroke()
    let check = NSBezierPath(); check.move(to:NSPoint(x:x+s*0.36,y:y+s*0.50)); check.line(to:NSPoint(x:x+s*0.46,y:y+s*0.40)); check.line(to:NSPoint(x:x+s*0.65,y:y+s*0.61)); check.lineWidth=s*0.055; check.lineCapStyle = .round; check.lineJoinStyle = .round; check.stroke()
    NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x:x+s*0.81,y:y+s*0.81,width:s*0.065,height:s*0.065)).fill()
}
func png(_ width: Int, _ height: Int, draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep); draw(); NSGraphicsContext.restoreGraphicsState(); return rep.representation(using:.png,properties:[:])!
}
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let n=size*scale; let data=png(n,n) { logo(NSRect(x:Double(n)*0.06,y:Double(n)*0.06,width:Double(n)*0.88,height:Double(n)*0.88)) }
        try data.write(to:root.appendingPathComponent("MacGuardian.iconset/icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
let bg=png(790,528) {
    NSColor(calibratedRed:0.035,green:0.055,blue:0.09,alpha:1).setFill(); NSRect(x:0,y:0,width:790,height:528).fill()
    NSGraphicsContext.current!.cgContext.translateBy(x:0,y:48)
    logo(NSRect(x:58,y:360,width:66,height:66))
    ("MacGuardian" as NSString).draw(at:NSPoint(x:144,y:392),withAttributes:[.font:NSFont.systemFont(ofSize:31,weight:.semibold),.foregroundColor:NSColor.white])
    ("Espacio para lo importante." as NSString).draw(at:NSPoint(x:146,y:365),withAttributes:[.font:NSFont.systemFont(ofSize:16),.foregroundColor:NSColor.lightGray])
    ("Arrastra MacGuardian a Aplicaciones" as NSString).draw(at:NSPoint(x:180,y:310),withAttributes:[.font:NSFont.systemFont(ofSize:20,weight:.medium),.foregroundColor:NSColor.white])
    ("→" as NSString).draw(at:NSPoint(x:350,y:180),withAttributes:[.font:NSFont.systemFont(ofSize:48,weight:.light),.foregroundColor:NSColor.systemMint])
    NSColor(calibratedRed:0.78,green:0.91,blue:0.94,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:144,y:155,width:132,height:27),xRadius:8,yRadius:8).fill()
    NSBezierPath(roundedRect:NSRect(x:478,y:155,width:136,height:27),xRadius:8,yRadius:8).fill()
    NSBezierPath(roundedRect:NSRect(x:624,y:42,width:112,height:26),xRadius:7,yRadius:7).fill()
    ("Local · Privado · Sin suscripciones" as NSString).draw(at:NSPoint(x:240,y:70),withAttributes:[.font:NSFont.systemFont(ofSize:15),.foregroundColor:NSColor.lightGray])
    ("Edición personal 0.2.1 · Apple Silicon · macOS 14 o posterior" as NSString).draw(at:NSPoint(x:195,y:35),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.gray])
}
try bg.write(to:root.appendingPathComponent("InstallerBackground.png"))
