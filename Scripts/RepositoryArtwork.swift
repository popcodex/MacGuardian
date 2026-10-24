import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1])
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

let card = png(1280, 640) {
    let rect = NSRect(x:0,y:0,width:1280,height:640)
    NSGradient(starting:NSColor(calibratedRed:0.04,green:0.075,blue:0.13,alpha:1),ending:NSColor(calibratedRed:0.06,green:0.17,blue:0.22,alpha:1))!.draw(in:rect,angle:0)
    logo(NSRect(x:72,y:210,width:218,height:218))
    let mint=NSColor(calibratedRed:0.39,green:0.88,blue:0.79,alpha:1)
    ("ESPACIO PARA LO IMPORTANTE" as NSString).draw(at:NSPoint(x:340,y:454),withAttributes:[.font:NSFont.systemFont(ofSize:17,weight:.semibold),.foregroundColor:mint,.kern:3])
    ("MacGuardian" as NSString).draw(at:NSPoint(x:332,y:334),withAttributes:[.font:NSFont.systemFont(ofSize:88,weight:.bold),.foregroundColor:NSColor.white,.kern:-3])
    ("Tu Mac, con claridad." as NSString).draw(at:NSPoint(x:340,y:281),withAttributes:[.font:NSFont.systemFont(ofSize:33,weight:.medium),.foregroundColor:NSColor(calibratedWhite:0.89,alpha:1)])
    ("Tú conservas el control." as NSString).draw(at:NSPoint(x:340,y:235),withAttributes:[.font:NSFont.systemFont(ofSize:28),.foregroundColor:NSColor(calibratedWhite:0.69,alpha:1)])
    let labels=[("Nativo para macOS",340.0,198.0),("Privacidad local",556.0,177.0),("En español",751.0,143.0)]
    for (label,x,width) in labels {
        NSColor(calibratedRed:0.075,green:0.18,blue:0.22,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:x,y:143,width:width,height:43),xRadius:21,yRadius:21).fill()
        (label as NSString).draw(at:NSPoint(x:x+22,y:155),withAttributes:[.font:NSFont.systemFont(ofSize:16,weight:.medium),.foregroundColor:NSColor(calibratedRed:0.80,green:0.91,blue:0.90,alpha:1)])
    }
    ("PRELIMINAR 0.1.0  ·  github.com/popcodex/MacGuardian" as NSString).draw(at:NSPoint(x:340,y:80),withAttributes:[.font:NSFont.systemFont(ofSize:16),.foregroundColor:NSColor(calibratedRed:0.48,green:0.61,blue:0.68,alpha:1)])
}
try card.write(to:output)
