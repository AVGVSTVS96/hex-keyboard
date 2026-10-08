import UIKit
import KeyboardUI

final class HomeViewController: UIViewController {
    private let field = PlaygroundTextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Hex"
        view.backgroundColor = .systemBackground
        field.font = .preferredFont(forTextStyle: .body)
        field.backgroundColor = .secondarySystemBackground
        field.layer.cornerRadius = 12
        field.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        field.translatesAutoresizingMaskIntoConstraints = false
        Playground.configure(field)
        view.addSubview(field)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            field.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            field.heightAnchor.constraint(equalToConstant: 120),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard Playground.current != nil else { return }
        if Playground.landscape {
            view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
        field.becomeFirstResponder()
    }
}
