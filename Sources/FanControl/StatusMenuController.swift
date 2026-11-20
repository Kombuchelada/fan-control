import AppKit
import FanKit

/// Owns the menu bar item and its menu.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private var cpuRow: MenuReadingView?
    private var gpuRow: MenuReadingView?
    private var fanRows: [Int: MenuReadingView] = [:]
    private var profileItems: [FanProfile: NSMenuItem] = [:]
    private var builtFanCount = -1

    var openSettings: (() -> Void)?

    #if DEBUG
    func runDebugSnapshotIfRequested() {
        DebugSnapshot.runIfRequested(statusItemMenu: menu, button: statusItem.button) { [weak self] in self?.openSettings?() }
    }
    #endif

    init(model: AppModel) {
        self.model = model
        super.init()
        statusItem.behavior = []
        statusItem.autosaveName = "FanControlStatusItem"
        statusItem.button?.setAccessibilityTitle("Fan Control")
        menu.delegate = self
        menu.autoenablesItems = true
        statusItem.menu = menu
        rebuildMenu()
        update()
    }

    // MARK: Building

    private func rebuildMenu() {
        menu.removeAllItems()
        fanRows.removeAll()
        profileItems.removeAll()
        let snapshot = model.snapshot
        builtFanCount = snapshot.fans.count

        menu.addItem(.sectionHeader(title: "Temperatures"))
        cpuRow = addReading("CPU", symbol: "cpu")
        gpuRow = snapshot.gpu == nil ? nil : addReading("Graphics", symbol: "display")

        if !snapshot.fans.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Fans"))
            for fan in snapshot.fans {
                fanRows[fan.index] = addReading(fan.name, symbol: "fan")
            }
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Fan Curve"))
        for profile in FanProfile.allCases {
            let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.rawValue
            item.image = NSImage(systemSymbolName: profile.symbol, accessibilityDescription: nil)
            if #available(macOS 14.4, *) { item.subtitle = profile.subtitle }
            menu.addItem(item)
            profileItems[profile] = item
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settings)
        let about = NSMenuItem(title: "About Fan Control", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Fan Control", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addReading(_ title: String, symbol: String) -> MenuReadingView {
        let view = MenuReadingView(title: title, symbol: symbol)
        let item = NSMenuItem()
        item.view = view
        menu.addItem(item)
        return view
    }

    // MARK: Updating

    func update() {
        let snapshot = model.snapshot
        if snapshot.fans.count != builtFanCount || (gpuRow == nil) != (snapshot.gpu == nil) {
            rebuildMenu()
        }

        cpuRow?.value = model.isSMCAvailable ? Format.temperature(snapshot.cpu) : "Unavailable"
        gpuRow?.value = Format.temperature(snapshot.gpu)
        for fan in snapshot.fans {
            fanRows[fan.index]?.value = Format.rpm(fan.rpm)
        }
        for (profile, item) in profileItems {
            item.state = profile == model.profile ? .on : .off
        }
        updateButton()
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let symbol = model.profile == .automatic ? "fan" : "fan.fill"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Fan Control")
        image?.isTemplate = true
        button.image = image

        if model.showsTemperatureInMenuBar {
            let font = NSFont.menuBarFont(ofSize: 0)
            button.attributedTitle = NSAttributedString(
                string: Format.shortTemperature(model.snapshot.controlTemperature),
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)])
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
        button.toolTip = "Fan Control — \(model.profile.name)"
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        model.setRefreshRate(fast: true)
    }

    func menuDidClose(_ menu: NSMenu) {
        model.setRefreshRate(fast: false)
    }

    // MARK: Actions

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let profile = FanProfile(rawValue: raw) else { return }
        model.select(profile)
    }

    @objc private func showSettings() {
        openSettings?()
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Quiet, balanced and performance fan curves for your Mac.",
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                             .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }
}

extension StatusMenuController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(selectProfile(_:)) {
            return model.isSMCAvailable && !model.isApplying && !model.snapshot.fans.isEmpty
        }
        return true
    }
}
