import KeyboardCore
import KeyboardUI
import UIKit

final class SettingsViewController: UITableViewController {
    private enum Row {
        case toggle(String, WritableKeyPath<KeyboardSettings, Bool>)
        case oneHanded
        case reset
    }

    private struct Section {
        var title: String?
        var footer: String?
        var rows: [Row]
    }

    private let sections = [
        Section(rows: [.oneHanded]),
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
        Section(footer: "Removes the words and typing habits Hex has learned from you.", rows: [.reset]),
    ]

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
        if case .oneHanded = row(at: indexPath) {
            return navigationController?.pushViewController(OneHandedViewController(), animated: true) ?? ()
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
            content.secondaryText = OneHandedViewController.title(of: settings.oneHanded)
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

    private func row(at indexPath: IndexPath) -> Row {
        sections[indexPath.section].rows[indexPath.row]
    }
}
