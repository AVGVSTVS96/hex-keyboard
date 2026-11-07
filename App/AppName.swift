import Foundation

/// An app's name as the iPhone shows it under its icon, from its bundle ID.
enum AppName {
    private static var known: [String: String] = [:]

    static func of(_ bundle: String) -> String {
        if let name = known[bundle] { return name }
        let name = lookUp(bundle) ?? bundle.split(separator: ".").last.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? bundle
        known[bundle] = name
        return name
    }

    /// `LSApplicationProxy` isn't API; where it's gone, the bundle ID's last part stands in.
    private static func lookUp(_ bundle: String) -> String? {
        #if APP_STORE
        return nil
        #else
        guard let type = NSClassFromString("LSApplicationProxy") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("applicationProxyForIdentifier:")
        guard type.responds(to: selector), let proxy = type.perform(selector, with: bundle)?.takeUnretainedValue() as? NSObject else { return nil }
        return (proxy.value(forKey: "localizedName") as? String).flatMap { $0.isEmpty ? nil : $0 }
        #endif
    }
}
