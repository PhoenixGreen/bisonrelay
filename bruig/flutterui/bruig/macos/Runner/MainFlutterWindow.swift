import AVFoundation
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

    let capture = FlutterMethodChannel(
      name: "bruig/capture",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    capture.setMethodCallHandler(CaptureRecorder.shared.handle)

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
    case "bodyPose3D":
      guard #available(macOS 14.0, *) else {
        result(FlutterError(code: "unavailable",
                            message: "Motion from a video needs macOS 14 or later",
                            details: nil))
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      guard let path = args["path"] as? String else {
        result(FlutterError(code: "args", message: "No video given", details: nil))
        return
      }
      let fps = args["fps"] as? Double ?? 24
      let longest = args["seconds"] as? Double ?? 120
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let found = try BodyPoseReader.read(path: path, fps: fps, longest: longest)
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

// BodyPoseReader finds a person's body in 3D on each frame of a video, for
// the canvas's characters to move as they do. Each frame's answer is the
// seventeen joints Vision knows, in metres from the hips, y up; a frame
// with nobody found holds the last one found.
//
// It answers "names", the joints in Mixamo's names (which the app's
// retargeting knows), "frames", every frame's joints as x, y and z one
// after another, "frameTime", and "found", how many frames had a person.
@available(macOS 14.0, *)
enum BodyPoseReader {
  static let joints: [(VNHumanBodyPose3DObservation.JointName, String)] = [
    (.root, "hips"), (.spine, "spine"), (.centerShoulder, "neck"),
    (.centerHead, "head"), (.topHead, "headtop_end"),
    (.leftShoulder, "leftarm"), (.leftElbow, "leftforearm"), (.leftWrist, "lefthand"),
    (.rightShoulder, "rightarm"), (.rightElbow, "rightforearm"), (.rightWrist, "righthand"),
    (.leftHip, "leftupleg"), (.leftKnee, "leftleg"), (.leftAnkle, "leftfoot"),
    (.rightHip, "rightupleg"), (.rightKnee, "rightleg"), (.rightAnkle, "rightfoot"),
  ]

  static func read(path: String, fps: Double, longest: Double) throws -> [String: Any] {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let seconds = min(CMTimeGetSeconds(asset.duration), longest)
    guard seconds > 0 else {
      throw NSError(domain: "bruig.vision", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "The video could not be read"])
    }
    let images = AVAssetImageGenerator(asset: asset)
    images.appliesPreferredTrackTransform = true
    images.requestedTimeToleranceBefore = .zero
    images.requestedTimeToleranceAfter = .zero
    images.maximumSize = CGSize(width: 1280, height: 1280)

    let count = max(1, Int((seconds * fps).rounded()))
    var frames: [Double] = []
    frames.reserveCapacity(count * joints.count * 3)
    var last: [Double]? = nil
    var found = 0
    for f in 0..<count {
      let time = CMTime(seconds: Double(f) / fps, preferredTimescale: 600)
      var row: [Double]? = nil
      if let image = try? images.copyCGImage(at: time, actualTime: nil) {
        let request = VNDetectHumanBodyPose3DRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        if (try? handler.perform([request])) != nil,
           let body = request.results?.first {
          var r: [Double] = []
          for (joint, _) in joints {
            if let p = try? body.recognizedPoint(joint) {
              let c = p.position.columns.3
              r += [Double(c.x), Double(c.y), Double(c.z)]
            } else {
              r += [0, 0, 0]
            }
          }
          row = r
          found += 1
        }
      }
      if let r = row { last = r }
      // Before anyone is found, nothing is held yet: those frames are
      // filled from the first that has someone, below.
      frames += last ?? Array(repeating: Double.nan, count: joints.count * 3)
    }
    if found == 0 {
      return ["found": 0, "names": joints.map { $0.1 }, "frames": [Double](), "frameTime": 1 / fps]
    }
    if let first = frames.firstIndex(where: { !$0.isNaN }) {
      let fill = Array(frames[first..<(first + joints.count * 3)])
      for i in stride(from: 0, to: first, by: joints.count * 3) {
        frames.replaceSubrange(i..<(i + joints.count * 3), with: fill)
      }
    }
    return [
      "found": found,
      "names": joints.map { $0.1 },
      "frames": FlutterStandardTypedData(float64: Data(bytes: frames, count: frames.count * 8)),
      "frameTime": 1 / fps,
    ]
  }
}

// CaptureRecorder records from the camera or the microphone to a file, for
// the canvas: a movement for a character to copy, or a voice-over for it to
// lip sync to. Only when asked -- the app's setting for it is off until it
// is switched on -- and only ever to a file on this computer.
//
// "start" takes "kind", "camera" or "microphone", and answers once
// recording has begun (macOS asks the person first, the first time);
// "stop" answers with "path", the file recorded.
final class CaptureRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
  static let shared = CaptureRecorder()

  private var session: AVCaptureSession?
  private var movie: AVCaptureMovieFileOutput?
  private var audio: AVAudioRecorder?
  private var stopped: ((String?, Error?) -> Void)?

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "start":
      let kind = args["kind"] as? String ?? "camera"
      let media: AVMediaType = kind == "camera" ? .video : .audio
      AVCaptureDevice.requestAccess(for: media) { granted in
        DispatchQueue.main.async {
          guard granted else {
            result(FlutterError(code: "denied",
              message: kind == "camera"
                ? "The camera is not allowed. Allow it in System Settings, Privacy & Security, Camera."
                : "The microphone is not allowed. Allow it in System Settings, Privacy & Security, Microphone.",
              details: nil))
            return
          }
          do {
            if kind == "camera" { try self.startCamera() } else { try self.startMicrophone() }
            result(true)
          } catch {
            result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "stop":
      stop { path, error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
          } else {
            result(["path": path ?? ""])
          }
        }
      }
    case "cancel":
      stop { path, _ in
        if let path = path { try? FileManager.default.removeItem(atPath: path) }
      }
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func scratch(_ ext: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("canvas-capture-\(UUID().uuidString).\(ext)")
  }

  private func startCamera() throws {
    guard movie == nil, audio == nil else { throw failure("Already recording") }
    guard let camera = AVCaptureDevice.default(for: .video) else {
      throw failure("No camera was found")
    }
    let session = AVCaptureSession()
    session.sessionPreset = .high
    let input = try AVCaptureDeviceInput(device: camera)
    guard session.canAddInput(input) else { throw failure("The camera could not be used") }
    session.addInput(input)
    let output = AVCaptureMovieFileOutput()
    guard session.canAddOutput(output) else { throw failure("The camera could not record") }
    session.addOutput(output)
    session.startRunning()
    output.startRecording(to: scratch("mov"), recordingDelegate: self)
    self.session = session
    self.movie = output
  }

  private func startMicrophone() throws {
    guard movie == nil, audio == nil else { throw failure("Already recording") }
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 48000,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
    let recorder = try AVAudioRecorder(url: scratch("m4a"), settings: settings)
    guard recorder.record() else { throw failure("The microphone could not record") }
    audio = recorder
  }

  private func stop(_ done: @escaping (String?, Error?) -> Void) {
    if let recorder = audio {
      recorder.stop()
      audio = nil
      done(recorder.url.path, nil)
      return
    }
    guard let output = movie, output.isRecording else {
      done(nil, nil)
      return
    }
    stopped = done
    output.stopRecording()
  }

  func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                  from connections: [AVCaptureConnection], error: Error?) {
    session?.stopRunning()
    session = nil
    movie = nil
    let done = stopped
    stopped = nil
    // A recording stopped on purpose can still report an error that only
    // says it stopped; the file is fine whenever it is there.
    let kept = FileManager.default.fileExists(atPath: url.path)
    done?(kept ? url.path : nil, kept ? nil : error)
  }

  private func failure(_ message: String) -> NSError {
    NSError(domain: "bruig.capture", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
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
