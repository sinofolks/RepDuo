import Foundation

extension String {
    /// English source copy is the localization key. Missing translations fall
    /// back to that English value because English is the development language.
    var rdLocalized: String {
        NSLocalizedString(self, tableName: nil, bundle: .main, value: self, comment: "")
    }

    func rdLocalizedFormat(_ arguments: CVarArg...) -> String {
        String(format: rdLocalized, locale: Locale.current, arguments: arguments)
    }
}
