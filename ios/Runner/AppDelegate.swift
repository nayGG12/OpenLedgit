import Flutter
import UIKit
import SwiftUI

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let glassRegistrar = registrar(forPlugin: "NativeLiquidGlassButton")
    glassRegistrar.register(
      NativeLiquidGlassButtonFactory(messenger: glassRegistrar.messenger()),
      withId: "open_ledger/native_liquid_glass_button"
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private struct NativeLiquidGlassButtonContent: View {
  let title: String
  let systemImage: String?
  let prominent: Bool
  let enabled: Bool
  let onPressed: () -> Void

  var body: some View {
    Button(action: onPressed) {
      if let systemImage {
        Label(title, systemImage: systemImage)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Text(title)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .buttonStyle(prominent ? .glassProminent : .glass)
    .disabled(!enabled)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private final class NativeLiquidGlassButtonFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeLiquidGlassButton(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      arguments: args as? [String: Any] ?? [:]
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class NativeLiquidGlassButton: NSObject, FlutterPlatformView {
  private let host: UIHostingController<NativeLiquidGlassButtonContent>
  private let channel: FlutterMethodChannel
  private var title: String
  private var systemImage: String?
  private var prominent: Bool
  private var enabled: Bool

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    arguments: [String: Any]
  ) {
    title = arguments["title"] as? String ?? ""
    systemImage = arguments["systemImage"] as? String
    prominent = arguments["prominent"] as? Bool ?? false
    enabled = arguments["enabled"] as? Bool ?? true
    channel = FlutterMethodChannel(
      name: "open_ledger/native_liquid_glass_button/\(viewId)",
      binaryMessenger: messenger
    )
    host = UIHostingController(
      rootView: NativeLiquidGlassButtonContent(
        title: title,
        systemImage: systemImage,
        prominent: prominent,
        enabled: enabled,
        onPressed: {}
      )
    )
    super.init()
    host.view.backgroundColor = .clear
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "button_unavailable", message: nil, details: nil))
        return
      }
      guard call.method == "update",
            let values = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.update(values)
      result(nil)
    }
    update(arguments)
  }

  func view() -> UIView {
    host.view
  }

  private func update(_ values: [String: Any]) {
    if let title = values["title"] as? String { self.title = title }
    if let rawSystemImage = values["systemImage"] {
      self.systemImage = rawSystemImage is NSNull
        ? nil
        : rawSystemImage as? String
    }
    if let prominent = values["prominent"] as? Bool { self.prominent = prominent }
    if let enabled = values["enabled"] as? Bool { self.enabled = enabled }

    host.rootView = NativeLiquidGlassButtonContent(
      title: title,
      systemImage: systemImage,
      prominent: prominent,
      enabled: enabled,
      onPressed: { [weak channel] in
        channel?.invokeMethod("pressed", arguments: nil)
      }
    )
  }
}
