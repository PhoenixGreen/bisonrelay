import Cocoa
import CoreImage
import FlutterMacOS
import ImageIO
import Vision

class MainFlutterWindow: NSWindow {
  // Kept alive for as long as the window: see TabletStream.
  private let tablet = TabletStream()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // No shorter than the app can be laid out in: shrunk past this, the main
    // navigation and the canvas's timeline ran out of room. As narrow as a
    // phone, though: narrow windows have a layout of their own, and the app
    // is tried out at a phone's width.
    self.contentMinSize = NSSize(width: 360, height: 560)

    RegisterGeneratedPlugins(registry: flutterViewController)

    FlutterEventChannel(
      name: "bruig/tablet",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setStreamHandler(tablet)

    let vision = FlutterMethodChannel(
      name: "bruig/vision",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    vision.setMethodCallHandler(VisionBridge.handle)

    super.awakeFromNib()
  }
}

// TabletStream passes a drawing tablet's pen on to the app: how hard it
// presses, how far it tilts, its buttons, and which end of it is near the
// tablet. Flutter's macOS embedder gives the app the pen's position and
// clicks but none of these, so the canvas's pencil reads them from here.
//
// Each reading is a map: "pressure" (0 to 1), "tiltX" and "tiltY" (-1 to 1),
// "rotation" (degrees), "buttons" (the button mask) and "time" (seconds
// since boot, as the event's own timestamp). The pen coming near or going
// away sends "proximity" (true or false) and "eraser" (whether it is the
// pen's eraser end). Nothing is read or sent while nothing is listening.
class TabletStream: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var monitor: Any?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    let mask: NSEvent.EventTypeMask = [
      .tabletPoint, .tabletProximity,
      .leftMouseDown, .leftMouseDragged, .leftMouseUp,
      .rightMouseDown, .rightMouseDragged, .rightMouseUp,
      .otherMouseDown, .otherMouseDragged, .otherMouseUp,
      .mouseMoved,
    ]
    monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
      self?.read(event)
      return event
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let m = monitor { NSEvent.removeMonitor(m) }
    monitor = nil
    sink = nil
    return nil
  }

  private func read(_ event: NSEvent) {
    guard let sink = sink else { return }
    switch event.type {
    case .tabletProximity:
      sink([
        "proximity": event.isEnteringProximity,
        "eraser": event.pointingDeviceType == .eraser,
      ])
    case .tabletPoint:
      sink(point(event))
    default:
      // A mouse event a tablet sent carries the pen's reading with it; one
      // from a mouse does not, and is left alone. Only mouse events have a
      // subtype, and these are all mouse events.
      if event.subtype == .tabletPoint { sink(point(event)) }
    }
  }

  private func point(_ event: NSEvent) -> [String: Any] {
    return [
      "pressure": Double(event.pressure),
      "tiltX": Double(event.tilt.x),
      "tiltY": Double(event.tilt.y),
      "rotation": Double(event.rotation),
      "buttons": Int(event.buttonMask.rawValue),
      "time": event.timestamp,
    ]
  }
}

// VisionBridge finds the subject of a picture with the operating system's
// own model -- the one behind lifting a subject out of a photograph in Photos
// -- for the canvas's Select subject tool. On this machine, with nothing
// uploaded and nothing to download: it is part of macOS 14 and later.
//
// "available" answers whether it can. "subject" takes "path", the picture's
// file, and optionally "x" and "y", fractions of the picture across and down
// from its top left; it answers with "instances", how many subjects the
// picture has, and -- where there was one, or one at x and y -- "mask", a
// grey PNG the size of the picture, white what is the subject.
enum VisionBridge {
  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "available":
      if #available(macOS 14.0, *) { result(true) } else { result(false) }
    case "subject":
      guard #available(macOS 14.0, *) else {
        result(FlutterError(code: "unavailable",
                            message: "Finding a subject needs macOS 14 or later",
                            details: nil))
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      guard let path = args["path"] as? String else {
        result(FlutterError(code: "args", message: "No picture given", details: nil))
        return
      }
      var at: CGPoint? = nil
      if let x = args["x"] as? Double, let y = args["y"] as? Double {
        at = CGPoint(x: x, y: y)
      }
      // Off the main thread: the first request of a run loads the model,
      // which takes a second or two, and the window must not stop for it.
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          var found = try SubjectFinder.find(path: path, at: at)
          if let png = found["mask"] as? Data {
            found["mask"] = FlutterStandardTypedData(bytes: png)
          }
          DispatchQueue.main.async { result(found) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "failed",
                                message: error.localizedDescription, details: nil))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// SubjectFinder is the part of VisionBridge that does the work, kept free of
// Flutter so it can be tried from the command line.
enum SubjectFinder {
  /// orientedImage is the picture at [path] the right way up, as the app's
  /// own decoder shows it: a phone's photograph carries its turn in its
  /// metadata, and a mask found on the unturned pixels would lie sideways
  /// across the picture.
  static func orientedImage(_ path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
    guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
    let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
    let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(w, h, 1),
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  /// find returns the subject of the picture at [path] as a grey PNG the
  /// size of the picture -- every subject, or, given [at] (fractions of the
  /// picture across and down from its top left), only the one there -- with
  /// how many subjects there were. Nil mask where there is no subject, or
  /// none at [at].
  @available(macOS 14.0, *)
  static func find(path: String, at: CGPoint?) throws -> [String: Any] {
    guard let image = orientedImage(path) else {
      throw NSError(domain: "bruig.vision", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The picture could not be read"])
    }
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([request])
    guard let observation = request.results?.first else {
      return ["instances": 0]
    }
    var instances = observation.allInstances
    if let at = at {
      let labels = observation.instanceMask
      CVPixelBufferLockBaseAddress(labels, .readOnly)
      defer { CVPixelBufferUnlockBaseAddress(labels, .readOnly) }
      let lw = CVPixelBufferGetWidth(labels), lh = CVPixelBufferGetHeight(labels)
      let row = CVPixelBufferGetBytesPerRow(labels)
      let x = min(lw - 1, max(0, Int(at.x * CGFloat(lw))))
      let y = min(lh - 1, max(0, Int(at.y * CGFloat(lh))))
      let base = CVPixelBufferGetBaseAddress(labels)!.assumingMemoryBound(to: UInt8.self)
      let label = Int(base[y * row + x])
      if label == 0 { return ["instances": instances.count] }
      instances = IndexSet(integer: label)
    }
    let mask = try observation.generateScaledMaskForImage(forInstances: instances, from: handler)
    let ci = CIImage(cvPixelBuffer: mask)
    guard let png = CIContext().pngRepresentation(
      of: ci, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
    else { return ["instances": observation.allInstances.count] }
    return [
      "instances": observation.allInstances.count,
      "mask": png,
      "width": CVPixelBufferGetWidth(mask),
      "height": CVPixelBufferGetHeight(mask),
    ]
  }
}
