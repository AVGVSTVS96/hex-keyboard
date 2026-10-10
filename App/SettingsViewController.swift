import KeyboardCore
import KeyboardUI
import UIKit

final class SettingsViewController: UITableViewController {
    private struct Section {
        var title: String?
        var footer: String?
        var rows: [(title: String, path: WritableKeyPath<KeyboardSettings, Bool>)]
    }

    private let sections = [
        Section(rows: [("Character Preview", \.characterPreview), ("Sound", \.sound)]),
        Section(title: "All Keyboards", footer: "Double tapping the space bar will insert a period followed by a space.", rows: [
            ("Auto-Capitalization", \.autoCapitalization),
            ("Auto-Correction", \.autoCorrection),
            ("Enable Caps Lock", \.capsLock),
            ("Smart Punctuation", \.smartPunctuation),
            ("“.” Shortcut", \.periodShortcut),
        ]),
        Section(title: "English", footer: "Hex expands your Text Replacements from Settings › General › Keyboard › Text Replacement.", rows: [
            ("Predictive Text", \.predictiveText),
        ]),
    ]

    private var settings = SettingsStore.load()

    init() {
        super.init(style: .insetGrouped)
        title = "Keyboard"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "toggle")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "reset")
    }

    private var resetSection: Int { sections.count }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count + 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == resetSection ? 1 : sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == resetSection ? nil : sections[section].title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == resetSection ? "Removes the words and typing habits Hex has learned from you." : sections[section].footer
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == resetSection
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let alert = UIAlertController(title: nil, message: "This will delete all custom words you’ve typed and how Hex learned your taps.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Reset Dictionary", style: .destructive) { _ in MemoryStore.reset() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == resetSection {
            let cell = tableView.dequeueReusableCell(withIdentifier: "reset", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Reset Keyboard Dictionary"
            content.textProperties.color = .tintColor
            cell.contentConfiguration = content
            return cell
        }
        let row = sections[indexPath.section].rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "toggle", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = row.title
        cell.contentConfiguration = content
        let toggle = UISwitch()
        toggle.isOn = settings[keyPath: row.path]
        toggle.accessibilityIdentifier = row.title
        toggle.addAction(UIAction { [unowned self, unowned toggle] _ in
            settings[keyPath: row.path] = toggle.isOn
            SettingsStore.set(toggle.isOn, for: row.path)
        }, for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }
}
