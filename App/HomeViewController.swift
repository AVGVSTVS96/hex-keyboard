import UIKit

final class HomeViewController: UIViewController {
    private let field = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Hex Keyboard"
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        view.backgroundColor = .systemBackground

        let steps = UILabel()
        steps.numberOfLines = 0
        steps.font = .preferredFont(forTextStyle: .body)
        steps.textColor = .secondaryLabel
        steps.text = "Settings › General › Keyboard › Keyboards › Add New Keyboard… › Hex. Then hold the globe key to switch."

        let settings = UIButton(configuration: .glass(), primaryAction: UIAction(title: "Open Settings") { _ in
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        })

        field.font = .preferredFont(forTextStyle: .body)
        field.backgroundColor = .secondarySystemBackground
        field.layer.cornerRadius = 16
        field.layer.cornerCurve = .continuous
        field.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        LaunchOptions.configure(field)

        let stack = UIStackView(arrangedSubviews: [steps, settings, field])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            field.heightAnchor.constraint(equalToConstant: 120),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if LaunchOptions.landscape {
            view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
        if LaunchOptions.focus { field.becomeFirstResponder() }
    }
}
