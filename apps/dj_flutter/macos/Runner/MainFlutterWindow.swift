import Cocoa
import FlutterMacOS

private enum UnlockMusicChannel {
  static let name = "dj_flutter/unlock_music"
  static let pickTargetsMethod = "pickUnlockTargets"
}

private enum ShellGlassLayout {
  static let defaultWindowSize = NSSize(width: 1440, height: 968)
  static let minimumWindowSize = NSSize(width: 1280, height: 888)
  static let frameAutosaveName = "DjFlutterMainWindowFrame"
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()

    self.isOpaque = false
    self.backgroundColor = NSColor(
      calibratedRed: 11.0 / 255.0,
      green: 16.0 / 255.0,
      blue: 30.0 / 255.0,
      alpha: 0.92,
    )
    self.hasShadow = true
    self.styleMask.insert(.fullSizeContentView)
    self.collectionBehavior = [.fullScreenPrimary]
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.toolbar = nil
    self.isMovableByWindowBackground = false
    self.minSize = ShellGlassLayout.minimumWindowSize
    self.contentMinSize = ShellGlassLayout.minimumWindowSize
    self.contentResizeIncrements = NSSize(width: 1, height: 1)
    self.contentViewController = flutterViewController

    let restoredFrame = self.setFrameUsingName(ShellGlassLayout.frameAutosaveName)
    if !restoredFrame {
      self.setContentSize(ShellGlassLayout.defaultWindowSize)
      self.center()
    } else {
      self.setContentSize(self.frame.size)
    }
    self.setFrameAutosaveName(ShellGlassLayout.frameAutosaveName)

    let channel = FlutterMethodChannel(
      name: UnlockMusicChannel.name,
      binaryMessenger: flutterViewController.engine.binaryMessenger,
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "WINDOW_UNAVAILABLE", message: "窗口不可用", details: nil))
        return
      }
      switch call.method {
      case UnlockMusicChannel.pickTargetsMethod:
        self.presentUnlockTargetsPanel(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  private func presentUnlockTargetsPanel(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.canCreateDirectories = false
    panel.prompt = "导入"
    panel.message = "选择要导入的文件或文件夹"

    panel.beginSheetModal(for: self) { response in
      guard response == .OK else {
        result([String]())
        return
      }
      result(panel.urls.map(\.path))
    }
  }
}
