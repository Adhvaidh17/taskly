import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentInteractionControllerDelegate {
  private var documentController: UIDocumentInteractionController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TasklyMediaBridge") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "taskly/media",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "TASKLY_MEDIA", message: "Media bridge unavailable", details: nil))
        return
      }
      do {
        switch call.method {
        case "prepareOutgoing":
          result(try self.prepareOutgoing(call))
        case "saveIncoming":
          result(try self.saveIncoming(call))
        case "prepareTaskAttachmentOutgoing":
          result(try self.prepareTaskAttachmentOutgoing(call))
        case "saveTaskAttachmentIncoming":
          result(try self.saveTaskAttachmentIncoming(call))
        case "openFile":
          try self.openLocalFile(call)
          result(nil)
        case "mediaRoot":
          result(try self.mediaRoot().path)
        case "cacheRoot":
          result(try self.cacheRoot().path)
        case "deleteLocalFile":
          try self.deleteLocalFile(call)
          result(nil)
        case "clearMedia":
          let media = try self.mediaRoot()
          let tasklyRoot = media.deletingLastPathComponent()
          if FileManager.default.fileExists(atPath: tasklyRoot.path) {
            try FileManager.default.removeItem(at: tasklyRoot)
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "TASKLY_MEDIA", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func mediaRoot() throws -> URL {
    let documents = try FileManager.default.url(
      for: .documentDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let root = documents.appendingPathComponent("Taskly/Media", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func cacheRoot() throws -> URL {
    let tasklyRoot = try mediaRoot().deletingLastPathComponent()
    let root = tasklyRoot.appendingPathComponent(".cache", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func category(for mimeType: String) -> String {
    if mimeType.hasPrefix("image/") { return "Taskly Images" }
    if mimeType.hasPrefix("video/") { return "Taskly Video" }
    if mimeType.hasPrefix("audio/") { return "Taskly Audio" }
    return "Taskly Documents"
  }

  private func destinationDirectory(mimeType: String, sent: Bool) throws -> URL {
    var directory = try mediaRoot().appendingPathComponent(category(for: mimeType), isDirectory: true)
    if sent { directory = directory.appendingPathComponent("Sent", isDirectory: true) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func safeName(_ value: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
    let cleaned = value.components(separatedBy: invalid).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "Taskly_\(Int(Date().timeIntervalSince1970 * 1000))" : cleaned
  }

  private func uniqueURL(directory: URL, name: String) -> URL {
    let requested = safeName(name)
    var candidate = directory.appendingPathComponent(requested)
    if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
    let ns = requested as NSString
    let stem = ns.deletingPathExtension
    let ext = ns.pathExtension
    let suffix = Int(Date().timeIntervalSince1970 * 1000)
    let resolved = ext.isEmpty ? "\(stem)_\(suffix)" : "\(stem)_\(suffix).\(ext)"
    candidate = directory.appendingPathComponent(resolved)
    return candidate
  }

  private func prepareOutgoing(_ call: FlutterMethodCall) throws -> [String: Any] {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      throw NSError(domain: "TasklyMedia", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing media path"])
    }
    let mime = (args["mimeType"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "application/octet-stream"
    let maxDimension = CGFloat(args["maxDimension"] as? Int ?? 1600)
    let quality = CGFloat(args["jpegQuality"] as? Int ?? 78) / 100.0
    let source = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw NSError(domain: "TasklyMedia", code: 2, userInfo: [NSLocalizedDescriptionKey: "Source file is unavailable"])
    }
    let directory = try destinationDirectory(mimeType: mime, sent: true)

    if mime.hasPrefix("image/"), mime.lowercased() != "image/gif", let image = UIImage(contentsOfFile: source.path) {
      let scaled = scaledImage(image, maxDimension: maxDimension)
      if let data = scaled.jpegData(compressionQuality: min(max(quality, 0.55), 0.92)) {
        let output = uniqueURL(directory: directory, name: source.deletingPathExtension().lastPathComponent + ".jpg")
        try data.write(to: output, options: .atomic)
        return [
          "path": output.path,
          "name": output.lastPathComponent,
          "mimeType": "image/jpeg",
          "sizeBytes": data.count,
        ]
      }
    }

    let output = uniqueURL(directory: directory, name: source.lastPathComponent)
    try FileManager.default.copyItem(at: source, to: output)
    let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    return ["path": output.path, "name": output.lastPathComponent, "mimeType": mime, "sizeBytes": size]
  }

  private func taskAttachmentDirectory(sent: Bool) throws -> URL {
    var directory = try mediaRoot().deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true)
    if sent { directory = directory.appendingPathComponent("Sent", isDirectory: true) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func prepareTaskAttachmentOutgoing(_ call: FlutterMethodCall) throws -> [String: Any] {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      throw NSError(domain: "TasklyMedia", code: 11, userInfo: [NSLocalizedDescriptionKey: "Missing attachment path"])
    }
    let mime = (args["mimeType"] as? String) ?? "application/octet-stream"
    let source = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw NSError(domain: "TasklyMedia", code: 12, userInfo: [NSLocalizedDescriptionKey: "Source file is unavailable"])
    }
    let output = uniqueURL(directory: try taskAttachmentDirectory(sent: true), name: source.lastPathComponent)
    try FileManager.default.copyItem(at: source, to: output)
    let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    return ["path": output.path, "name": output.lastPathComponent, "mimeType": mime, "sizeBytes": size]
  }

  private func saveTaskAttachmentIncoming(_ call: FlutterMethodCall) throws -> [String: Any] {
    guard let args = call.arguments as? [String: Any],
          let typedData = args["bytes"] as? FlutterStandardTypedData else {
      throw NSError(domain: "TasklyMedia", code: 13, userInfo: [NSLocalizedDescriptionKey: "Missing attachment bytes"])
    }
    let name = (args["name"] as? String) ?? "Taskly_\(Int(Date().timeIntervalSince1970 * 1000))"
    let mime = (args["mimeType"] as? String) ?? "application/octet-stream"
    let output = uniqueURL(directory: try taskAttachmentDirectory(sent: false), name: name)
    try typedData.data.write(to: output, options: .atomic)
    return ["path": output.path, "name": output.lastPathComponent, "mimeType": mime, "sizeBytes": typedData.data.count]
  }

  private func saveIncoming(_ call: FlutterMethodCall) throws -> [String: Any] {
    guard let args = call.arguments as? [String: Any],
          let typedData = args["bytes"] as? FlutterStandardTypedData else {
      throw NSError(domain: "TasklyMedia", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing media bytes"])
    }
    let name = (args["name"] as? String) ?? "Taskly_\(Int(Date().timeIntervalSince1970 * 1000))"
    let mime = (args["mimeType"] as? String) ?? "application/octet-stream"
    let sent = (args["sent"] as? Bool) ?? false
    let directory = try destinationDirectory(mimeType: mime, sent: sent)
    let output = uniqueURL(directory: directory, name: name)
    try typedData.data.write(to: output, options: .atomic)
    return ["path": output.path, "name": output.lastPathComponent, "mimeType": mime, "sizeBytes": typedData.data.count]
  }

  private func scaledImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
    let largest = max(image.size.width, image.size.height)
    guard largest > maxDimension, largest > 0 else { return image }
    let ratio = maxDimension / largest
    let size = CGSize(width: max(1, image.size.width * ratio), height: max(1, image.size.height * ratio))
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
  }

  private func deleteLocalFile(_ call: FlutterMethodCall) throws {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String, !path.isEmpty else { return }
    let target = URL(fileURLWithPath: path).standardizedFileURL
    let tasklyRoot = try mediaRoot().deletingLastPathComponent().standardizedFileURL
    guard target.path.hasPrefix(tasklyRoot.path + "/") else {
      throw NSError(domain: "TasklyMedia", code: 20, userInfo: [NSLocalizedDescriptionKey: "Refusing to delete a file outside Taskly storage"])
    }
    if FileManager.default.fileExists(atPath: target.path) {
      try FileManager.default.removeItem(at: target)
    }
  }

  private func openLocalFile(_ call: FlutterMethodCall) throws {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          FileManager.default.fileExists(atPath: path) else {
      throw NSError(domain: "TasklyMedia", code: 4, userInfo: [NSLocalizedDescriptionKey: "File is not available on this device"])
    }
    let controller = UIDocumentInteractionController(url: URL(fileURLWithPath: path))
    controller.delegate = self
    documentController = controller
    guard let view = window?.rootViewController?.view else { return }
    controller.presentOptionsMenu(from: view.bounds, in: view, animated: true)
  }

  func documentInteractionControllerViewControllerForPreview(
    _ controller: UIDocumentInteractionController
  ) -> UIViewController {
    return window?.rootViewController ?? UIViewController()
  }
}
