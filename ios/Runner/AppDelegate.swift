import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PokerFectionHost") {
      HostChannels.register(messenger: registrar.messenger())
    }
  }
}

/// What the app asks of the host: where to keep its settings file, and
/// playing its sound effects (short WAV files it makes itself).
enum HostChannels {
  /// Players still sounding (they stop if released early).
  static var players: [AVAudioPlayer] = []

  static func register(messenger: FlutterBinaryMessenger) {
    // Game sounds mix with other audio and follow the silent switch.
    try? AVAudioSession.sharedInstance().setCategory(.ambient)

    FlutterMethodChannel(name: "pokerfection/platform", binaryMessenger: messenger).setMethodCallHandler {
      call, result in
      if call.method == "dataFolder",
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      {
        result(folder.path)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterMethodChannel(name: "pokerfection/sound", binaryMessenger: messenger).setMethodCallHandler {
      call, result in
      guard call.method == "play" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if let data = call.arguments as? FlutterStandardTypedData,
        let player = try? AVAudioPlayer(data: data.data)
      {
        players.removeAll { !$0.isPlaying }
        players.append(player)
        player.play()
      }
      result(nil)
    }
  }
}
