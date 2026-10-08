import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Kept alive for as long as the window: see TabletStream.
  private let tablet = TabletStream()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    FlutterEventChannel(
      name: "bruig/tablet",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setStreamHandler(tablet)

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
