import Foundation

/// Thin stdin/stdout helpers for the interactive `create` flow. Deliberately free of
/// business logic so the flow that uses them stays readable and the validation/derivation
/// they orchestrate lives in testable pure functions elsewhere.
enum Prompt {
    /// True when stdin is an interactive terminal. When false (piped input, CI), the
    /// caller must not prompt — it should fall back to non-interactive behaviour.
    static var isInteractive: Bool {
        isatty(STDIN_FILENO) == 1
    }

    /// Prints a prompt (no newline) and returns the trimmed line the user typed, or nil
    /// on EOF (e.g. Ctrl-D).
    static func line(_ message: String) -> String? {
        print(message, terminator: "")
        guard let raw = readLine(strippingNewline: true) else { return nil }
        return raw.trimmingCharacters(in: .whitespaces)
    }

    /// Outcome of validating a prompt response: a parsed value, or an error message to
    /// show before re-prompting.
    enum Validation<T> {
        case valid(T)
        case invalid(String)
    }

    /// Repeatedly prompts until `validate` accepts the input. Returns nil only on EOF
    /// (user aborted with Ctrl-D).
    static func ask<T>(_ message: String,
                       validate: (String) -> Validation<T>) -> T? {
        while true {
            guard let input = line(message) else { return nil }
            switch validate(input) {
            case .valid(let value):
                return value
            case .invalid(let error):
                print("  \(error)")
            }
        }
    }

    /// Prompts with a default shown in brackets; an empty response accepts the default.
    static func lineWithDefault(_ message: String, default defaultValue: String) -> String {
        guard let input = line("\(message) [\(defaultValue)]: "), !input.isEmpty else {
            return defaultValue
        }
        return input
    }

    /// Like `lineWithDefault`, but validates non-empty input: an empty response accepts
    /// `defaultValue` verbatim, otherwise `validate` parses the input and re-prompts on a
    /// rejection (showing its message). Returns nil only on EOF. `defaultDisplay` shows
    /// what the default means in the prompt (e.g. "keep existing", "none").
    static func askWithDefault<T>(_ message: String,
                                  default defaultValue: T,
                                  defaultDisplay: String,
                                  validate: (String) -> Validation<T>) -> T? {
        while true {
            guard let input = line("\(message) [\(defaultDisplay)]: ") else { return nil }
            if input.isEmpty { return defaultValue }
            switch validate(input) {
            case .valid(let value):
                return value
            case .invalid(let error):
                print("  \(error)")
            }
        }
    }

    /// Yes/no confirmation. Empty response accepts `defaultYes`.
    static func confirm(_ message: String, defaultYes: Bool = true) -> Bool {
        let hint = defaultYes ? "[Y/n]" : "[y/N]"
        guard let input = line("\(message) \(hint): ")?.lowercased(), !input.isEmpty else {
            return defaultYes
        }
        return input == "y" || input == "yes"
    }
}
