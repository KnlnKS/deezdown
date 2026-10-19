import Foundation

/// Kept in the order Settings lists them.
public typealias TemplateVariables = KeyValuePairs<String, String>

public enum TemplateEngine {
    /// deemix drops one leading space with these when they render empty, so titles don't
    /// end up with a double space where the feature or advisory marker would have been.
    static let spaceEating: Set<String> = ["featartists", "explicit"]

    /// One pass over the template. Sweeping the whole string once per variable was both
    /// slower and order-dependent: a value that happened to contain a token was substituted
    /// again or not depending on how the dictionary happened to be laid out. Only the values
    /// the template uses are escaped.
    public static func render(
        _ template: String, _ variables: TemplateVariables, escape: (String) -> String = { $0 }
    ) -> String {
        var output = ""
        output.reserveCapacity(template.count)
        var rest = Substring(template)

        while let start = rest.firstIndex(of: "%") {
            let nameStart = rest.index(after: start)
            guard let end = rest[nameStart...].firstIndex(of: "%") else { break }
            let name = rest[nameStart..<end]
            guard let raw = variables.first(where: { $0.key == name })?.value else {
                // Not a variable, so the closing marker may yet open a real one.
                output += rest[...start]
                rest = rest[nameStart...]
                continue
            }
            let value = escape(raw)
            output += rest[..<start]
            if value.isEmpty, spaceEating.contains(String(name)), output.last == " " {
                output.removeLast()
            }
            output += value
            rest = rest[rest.index(after: end)...]
        }

        output += rest
        return output.trimmingCharacters(in: .whitespaces)
    }
}
