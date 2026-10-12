import UIKit

final class HomeViewController: UITableViewController {
    private enum Row {
        case keyboard, fullAccess, field, settings, taps
    }

    private struct Section {
        var title: String?
        var footer: String?
        var rows: [Row]
    }

    private let sections = [
        Section(title: "Set Up", footer: "In Settings, tap Keyboards, then turn on Hex and Allow Full Access. What you type stays on your iPhone: Hex has no network code. Full Access lets it play haptics and show you where your taps land.", rows: [.keyboard, .fullAccess]),
        Section(title: "Try It", rows: [.field]),
        Section(rows: [.settings, .taps]),
    ]

    private let field = UITextView()
    private let fieldCell = UITableViewCell()
    private var isAdded = HomeViewController.keyboardIsAdded

    /// The keyboards in Settings › General › Keyboard › Keyboards, read from the global defaults iOS keeps them in.
    private static var keyboardIsAdded: Bool {
        (UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String] ?? []).contains("com.shahidy.hexkeyboard.keyboard")
    }

    init() {
        super.init(style: .insetGrouped)
        title = "Hex"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.keyboardDismissMode = .interactive

        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.backgroundColor = .clear
        field.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        field.accessibilityLabel = "Try Hex"
        LaunchOptions.configure(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        fieldCell.selectionStyle = .none
        fieldCell.contentView.addSubview(field)
        let margins = fieldCell.contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: fieldCell.contentView.topAnchor),
            field.bottomAnchor.constraint(equalTo: fieldCell.contentView.bottomAnchor),
            field.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            field.heightAnchor.constraint(equalToConstant: 120),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(refreshStatus), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let orientation = LaunchOptions.orientation {
            view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        }
        if LaunchOptions.focus { field.becomeFirstResponder() }
    }

    @objc private func refreshStatus() {
        let added = Self.keyboardIsAdded
        guard added != isAdded else { return }
        isAdded = added
        tableView.reconfigureRows(at: [IndexPath(row: 0, section: 0)])
    }

    func showSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: false)
    }

    func showTaps() {
        navigationController?.pushViewController(TapsViewController(), animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        row(at: indexPath) != .field
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch row(at: indexPath) {
        case .keyboard, .fullAccess: UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        case .settings: navigationController?.pushViewController(SettingsViewController(), animated: true)
        case .taps: showTaps()
        case .field: break
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if row(at: indexPath) == .field { return fieldCell }
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.valueCell()
        cell.accessoryType = .disclosureIndicator
        cell.accessoryView = nil
        switch row(at: indexPath) {
        case .keyboard:
            content.image = UIImage(systemName: "keyboard")
            content.text = "Hex Keyboard"
            content.secondaryText = isAdded ? nil : "Off"
            if isAdded {
                let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
                check.tintColor = .systemGreen
                cell.accessoryView = check
            }
        case .fullAccess:
            content = UIListContentConfiguration.subtitleCell()
            content.image = UIImage(systemName: "lock.open")
            content.text = "Allow Full Access"
            content.secondaryText = "For haptics and Your Taps"
            content.secondaryTextProperties.color = .secondaryLabel
        case .field:
            break
        case .settings:
            content.image = UIImage(systemName: "gearshape")
            content.text = "Keyboard Settings"
        case .taps:
            content.image = UIImage(systemName: "hand.tap")
            content.text = "Your Taps"
        }
        cell.contentConfiguration = content
        return cell
    }

    private func row(at indexPath: IndexPath) -> Row {
        sections[indexPath.section].rows[indexPath.row]
    }
}
