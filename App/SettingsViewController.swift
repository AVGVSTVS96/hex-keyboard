import KeyboardCore
import KeyboardUI
import UIKit

final class SettingsViewController: UITableViewController {
    private enum Row {
        case toggle(String, WritableKeyPath<KeyboardSettings, Bool>)
        case oneHanded
        case keepMicOn
        case voiceModel
        case source(Source)
        case addSource
        case reset
    }

    private struct Section {
        var title: String?
        var footer: String?
        var rows: [Row]
    }

    private var sections: [Section] { [
        Section(footer: Self.oneHandedFooter, rows: [.oneHanded]),
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
        Section(title: "Voice", footer: Self.voiceFooter, rows: [.keepMicOn, .voiceModel]),
        Section(title: "Sources", footer: Self.sourcesFooter, rows: sources.map(Row.source) + [.addSource]),
        Section(footer: "Removes the words and typing habits Hex has learned from you.", rows: [.reset]),
    ] }

    private static let keepMicOnFooter = "After you dictate, Hex keeps the mic on this long. While it’s on, the mic beside the suggestions starts and stops dictating without leaving your app; hold it to turn the mic off. Nothing is recorded until you tap it."

    private static let voiceFooter = keepMicOnFooter + "\n\nHex writes down what you say on your iPhone, with the voice model you pick."

    private static let voiceModelFooter = "Parakeet v3 downloads once (about 500 MB), gets ready in under a minute after Hex is installed or updated, and at once every time after. Parakeet Ultra is a little more accurate, but on the newest iPhones it takes minutes to get ready, and heats the iPhone, every time Hex opens. Until the model you pick is ready, Apple’s writes, and Transcripts shows which model wrote each dictation."

    private static let sourcesFooter = "With Allow Full Access on, Hex sends each source the text of the field you’re typing in, except passwords and codes, and shows the hints it answers with above the keys. Tap a hint to hide it."

    private static let oneHandedFooter = "Hold 123 and slide to move the keys toward one thumb."

    private var settings = SettingsStore.load()
    private var sources = SourceStore.load()

    init() {
        super.init(style: .insetGrouped)
        title = "Keyboard"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        HexStyle.dress(tableView)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        settings = SettingsStore.load()
        sources = SourceStore.load()
        tableView.reloadData()
        observeVoiceModel()
    }

    private func observeVoiceModel() {
        withObservationTracking { _ = VoiceModel.shared.state } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, view.window != nil else { return }
                tableView.reloadData()
                observeVoiceModel()
            }
        }
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch row(at: indexPath) {
        case .toggle, .source: false
        default: true
        }
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard case .source(let source) = row(at: indexPath) else { return nil }
        return UISwipeActionsConfiguration(actions: [UIContextualAction(style: .destructive, title: "Delete") { [unowned self] _, _, done in
            sources.removeAll { $0 == source }
            SourceStore.save(sources)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            done(true)
        }])
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch row(at: indexPath) {
        case .oneHanded:
            let choices = OneHanded.allCases.map { (value: $0, title: Self.title(of: $0)) }
            return show(ChoiceViewController(title: "One-Handed Keyboard", footer: "The keys move toward your thumb on an upright iPhone. Tap the arrow beside them to bring back the full keyboard.", choices: choices, choice: settings.oneHanded) {
                SettingsStore.set($0)
            }, sender: self)
        case .keepMicOn:
            let choices = Dictation.micChoices.map { (value: $0, title: Dictation.title(keepingMicOn: $0)) }
            return show(ChoiceViewController(title: "Keep Mic On", footer: Self.keepMicOnFooter, choices: choices, choice: SettingsStore.keepMicOn) {
                SettingsStore.keepMicOn = $0
                Listener.shared.keepMicOn()
            }, sender: self)
        case .voiceModel:
            let choices = VoiceModel.Model.allCases.map { (value: $0, title: $0.title) }
            return show(ChoiceViewController(title: "Voice Model", footer: Self.voiceModelFooter, choices: choices, choice: VoiceModel.shared.model) {
                VoiceModel.shared.pick($0)
            }, sender: self)
        case .addSource:
            tableView.deselectRow(at: indexPath, animated: true)
            return addSource()
        default:
            break
        }
        tableView.deselectRow(at: indexPath, animated: true)
        let alert = UIAlertController(title: nil, message: "This deletes the words Hex learned from you and everything it learned about your taps.", preferredStyle: .actionSheet)
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
        case .keepMicOn:
            content.text = "Keep Mic On"
            content.secondaryText = Dictation.title(keepingMicOn: SettingsStore.keepMicOn)
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        case .voiceModel:
            content.text = "Voice Model"
            let model = VoiceModel.shared.model
            content.secondaryText = switch VoiceModel.shared.state {
            case .downloading(let done): "\(model.title), downloading \(done.formatted(.percent.precision(.fractionLength(0))))"
            case .loading: "\(model.title), getting ready"
            case .ready: model.title
            case .failed: "\(model.title) failed"
            }
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        case .source(let source):
            content = .subtitleCell()
            content.text = source.name
            content.secondaryText = source.url.absoluteString
            content.secondaryTextProperties.color = .secondaryLabel
            cell.accessoryView = nil
        case .addSource:
            content.text = "Add Source…"
            content.textProperties.color = .tintColor
            cell.accessoryView = nil
        case .reset:
            content.text = "Reset Keyboard Dictionary"
            content.textProperties.color = .tintColor
            cell.accessoryView = nil
        }
        if let (symbol, color) = Self.glyph(of: row(at: indexPath)) {
            content.image = HexStyle.glyph(symbol, color)
            content.imageProperties.reservedLayoutSize = CGSize(width: 30, height: 30)
        }
        cell.contentConfiguration = content
        HexStyle.dress(cell)
        return cell
    }

    private static func glyph(of row: Row) -> (String, UIColor)? {
        switch row {
        case .oneHanded: ("hand.raised.fill", .systemOrange)
        case .toggle(_, \KeyboardSettings.characterPreview): ("character.magnify", .systemBlue)
        case .toggle(_, \KeyboardSettings.haptics): ("iphone.radiowaves.left.and.right", .systemPink)
        case .toggle(_, \KeyboardSettings.sound): ("speaker.wave.2.fill", .systemRed)
        case .toggle(_, \KeyboardSettings.autoCapitalization): ("textformat", .systemBlue)
        case .toggle(_, \KeyboardSettings.autoCorrection): ("text.badge.checkmark", .systemGreen)
        case .toggle(_, \KeyboardSettings.capsLock): ("capslock.fill", .systemGray)
        case .toggle(_, \KeyboardSettings.smartPunctuation): ("quote.opening", .systemPurple)
        case .toggle(_, \KeyboardSettings.periodShortcut): ("character.cursor.ibeam", .systemTeal)
        case .toggle(_, \KeyboardSettings.predictiveText): ("text.insert", .systemIndigo)
        case .keepMicOn: ("mic.fill", .systemOrange)
        case .voiceModel: ("waveform", .systemRed)
        case .source: ("antenna.radiowaves.left.and.right", .systemTeal)
        default: nil
        }
    }

    private func addSource() {
        let alert = UIAlertController(title: "Add Source", message: "A source is a service Hex tells what you type. It can answer with a hint above the keys.", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Name" }
        alert.addTextField {
            $0.placeholder = "https://"
            $0.keyboardType = .URL
            $0.autocapitalizationType = .none
        }
        alert.addTextField {
            $0.placeholder = "Token (optional)"
            $0.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [unowned self, unowned alert] _ in
            let fields = alert.textFields?.map { $0.text?.trimmingCharacters(in: .whitespaces) ?? "" } ?? []
            guard let url = URL(string: fields[1]), Source.allows(url), !fields[0].isEmpty else { return }
            SourceStore.add(Source(name: fields[0], url: url, token: fields[2].isEmpty ? nil : fields[2]))
            sources = SourceStore.load()
            tableView.reloadData()
        })
        present(alert, animated: true)
    }

    private static func title(of hand: OneHanded) -> String {
        switch hand {
        case .off: "Off"
        case .left: "Left"
        case .right: "Right"
        }
    }

    private func row(at indexPath: IndexPath) -> Row {
        sections[indexPath.section].rows[indexPath.row]
    }
}
