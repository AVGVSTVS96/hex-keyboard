import KeyboardCore
import KeyboardUI
import UIKit

final class SettingsViewController: UITableViewController {
    private enum Row {
        case toggle(String, WritableKeyPath<KeyboardSettings, Bool>)
        case oneHanded
        case menuPick
        case keepMicOn
        case reset
    }

    private struct Section {
        var title: String?
        var footer: String?
        var rows: [Row]
    }

    private let sections = [
        Section(footer: SettingsViewController.menuPickFooter, rows: [.oneHanded, .menuPick]),
        Section(footer: "Haptic Feedback needs Allow Full Access in Settings › General › Keyboard › Keyboards › Hex.", rows: [
            .toggle("Character Preview", \.characterPreview),
            .toggle("Haptic Feedback", \.haptics),
            .toggle("Sound", \.sound),
        ]),
        Section(title: "All Keyboards", footer: "Double tapping the space bar will insert a period followed by a space.", rows: [
            .toggle("Auto-Capitalization", \.autoCapitalization),
            .toggle("Auto-Correction", \.autoCorrection),
            .toggle("Enable Caps Lock", \.capsLock),
            .toggle("Smart Punctuation", \.smartPunctuation),
            .toggle("“.” Shortcut", \.periodShortcut),
        ]),
        Section(title: "English", footer: "Hex expands your Text Replacements from Settings › General › Keyboard › Text Replacement.", rows: [
            .toggle("Predictive Text", \.predictiveText),
        ]),
        Section(title: "Voice", footer: SettingsViewController.keepMicOnFooter, rows: [.keepMicOn]),
        Section(footer: "Removes the words and typing habits Hex has learned from you.", rows: [.reset]),
    ]

    private static let keepMicOnFooter = "After you dictate, the mic stays on this long, and the mic beside the suggestions starts and stops dictating without opening Hex. Nothing is heard until you tap it. Hold it to turn the mic off."

    private static let menuPickFooter = "Holding 123 opens a menu above it. Let go right away to pick what Hold 123 says, or slide to the others."

    private var settings = SettingsStore.load()

    init() {
        super.init(style: .insetGrouped)
        title = "Keyboard"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        settings = SettingsStore.load()
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        if case .toggle = row(at: indexPath) { false } else { true }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch row(at: indexPath) {
        case .oneHanded:
            let choices = OneHanded.allCases.map { (value: $0, title: Self.title(of: $0)) }
            return show(ChoiceViewController(title: "One-Handed Keyboard", footer: "The keys move toward your thumb on an upright iPhone. Tap the arrow beside them to bring back the full keyboard.", choices: choices, choice: settings.oneHanded) {
                SettingsStore.set($0)
            }, sender: self)
        case .menuPick:
            let choices = [MenuItem.emoji, .voice].map { (value: $0, title: Self.title(of: $0)) }
            return show(ChoiceViewController(title: "Hold 123", footer: Self.menuPickFooter, choices: choices, choice: settings.menuPick) {
                SettingsStore.set(menuPick: $0)
            }, sender: self)
        case .keepMicOn:
            let choices = Dictation.micChoices.map { (value: $0, title: Dictation.title(keepingMicOn: $0)) }
            return show(ChoiceViewController(title: "Keep Mic On", footer: Self.keepMicOnFooter, choices: choices, choice: SettingsStore.keepMicOn) {
                SettingsStore.keepMicOn = $0
                Listener.shared.keepMicOn()
            }, sender: self)
        default:
            break
        }
        tableView.deselectRow(at: indexPath, animated: true)
        let alert = UIAlertController(title: nil, message: "This will delete all custom words you’ve typed and how Hex learned your taps.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Reset Dictionary", style: .destructive) { _ in MemoryStore.reset() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.valueCell()
        cell.accessoryType = .none
        switch row(at: indexPath) {
        case .toggle(let title, let path):
            content.text = title
            let toggle = UISwitch()
            toggle.isOn = settings[keyPath: path]
            toggle.accessibilityIdentifier = title
            toggle.addAction(UIAction { [unowned self, unowned toggle] _ in
                settings[keyPath: path] = toggle.isOn
                SettingsStore.set(toggle.isOn, for: path)
            }, for: .valueChanged)
            cell.accessoryView = toggle
        case .oneHanded:
            content.text = "One-Handed Keyboard"
            content.secondaryText = Self.title(of: settings.oneHanded)
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        case .menuPick:
            content.text = "Hold 123"
            content.secondaryText = Self.title(of: settings.menuPick)
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        case .keepMicOn:
            content.text = "Keep Mic On"
            content.secondaryText = Dictation.title(keepingMicOn: SettingsStore.keepMicOn)
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        case .reset:
            content.text = "Reset Keyboard Dictionary"
            content.textProperties.color = .tintColor
            cell.accessoryView = nil
        }
        cell.contentConfiguration = content
        return cell
    }

    private static func title(of hand: OneHanded) -> String {
        switch hand {
        case .off: "Off"
        case .left: "Left"
        case .right: "Right"
        }
    }

    private static func title(of pick: MenuItem) -> String {
        pick == .voice ? "Voice" : "Emoji"
    }

    private func row(at indexPath: IndexPath) -> Row {
        sections[indexPath.section].rows[indexPath.row]
    }
}
