import KeyboardCore
import KeyboardUI
import UIKit

final class OneHandedViewController: UITableViewController {
    private var choice = SettingsStore.load().oneHanded

    static func title(of hand: OneHanded) -> String {
        switch hand {
        case .off: "Off"
        case .left: "Left"
        case .right: "Right"
        }
    }

    init() {
        super.init(style: .insetGrouped)
        title = "One-Handed Keyboard"
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "choice")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { OneHanded.allCases.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "The keys move toward your thumb on an upright iPhone. Tap the arrow beside them to bring back the full keyboard."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "choice", for: indexPath)
        let hand = OneHanded.allCases[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = Self.title(of: hand)
        cell.contentConfiguration = content
        cell.accessoryType = hand == choice ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        choice = OneHanded.allCases[indexPath.row]
        SettingsStore.set(choice)
        for cell in tableView.visibleCells {
            guard let row = tableView.indexPath(for: cell)?.row else { continue }
            cell.accessoryType = OneHanded.allCases[row] == choice ? .checkmark : .none
        }
    }
}
