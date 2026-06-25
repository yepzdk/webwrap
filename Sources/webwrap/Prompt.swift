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

    /// Words that cancel the flow at any prompt (case-insensitive). EOF (Ctrl-D) cancels too.
    static let cancelWords: Set<String> = ["q", "quit", "cancel"]

    /// Whether a raw response is a cancel request. Pure — unit-testable.
    static func isCancel(_ input: String) -> Bool {
        cancelWords.contains(input.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// The raw outcome of reading one line: a value, an explicit cancel, or EOF — both of
    /// the latter mean "abort". Callers fold cancel/eof into a nil return.
    private enum Line {
        case value(String)
        case cancelled
    }

    /// Prints a prompt (no newline) and returns the trimmed line, folding a typed cancel
    /// word or EOF into `.cancelled`.
    private static func readCancellable(_ message: String) -> Line {
        print(message, terminator: "")
        guard let raw = readLine(strippingNewline: true) else { return .cancelled }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return isCancel(trimmed) ? .cancelled : .value(trimmed)
    }

    /// Prints a prompt (no newline) and returns the trimmed line the user typed, or nil
    /// on EOF or a typed cancel word.
    static func line(_ message: String) -> String? {
        if case .value(let v) = readCancellable(message) { return v }
        return nil
    }

    /// Outcome of validating a prompt response: a parsed value, or an error message to
    /// show before re-prompting.
    enum Validation<T> {
        case valid(T)
        case invalid(String)
    }

    /// Repeatedly prompts until `validate` accepts the input. Returns nil on EOF/cancel.
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
    /// Returns nil on EOF/cancel.
    static func lineWithDefault(_ message: String, default defaultValue: String) -> String? {
        switch readCancellable("\(message) [\(defaultValue)]: ") {
        case .cancelled: return nil
        case .value(let input): return input.isEmpty ? defaultValue : input
        }
    }

    /// Like `lineWithDefault`, but validates non-empty input: an empty response accepts
    /// `defaultValue` verbatim, otherwise `validate` parses the input and re-prompts on a
    /// rejection (showing its message). Returns nil on EOF/cancel. `defaultDisplay` shows
    /// what the default means in the prompt (e.g. "keep existing", "none").
    static func askWithDefault<T>(_ message: String,
                                  default defaultValue: T,
                                  defaultDisplay: String,
                                  validate: (String) -> Validation<T>) -> T? {
        while true {
            switch readCancellable("\(message) [\(defaultDisplay)]: ") {
            case .cancelled:
                return nil
            case .value(let input):
                if input.isEmpty { return defaultValue }
                switch validate(input) {
                case .valid(let value): return value
                case .invalid(let error): print("  \(error)")
                }
            }
        }
    }

    /// Yes/no confirmation. Empty response accepts `defaultYes`. Returns nil on EOF/cancel
    /// (so a confirm can be aborted like any other step).
    static func confirmOrCancel(_ message: String, defaultYes: Bool) -> Bool? {
        let hint = defaultYes ? "[Y/n]" : "[y/N]"
        switch readCancellable("\(message) \(hint): ") {
        case .cancelled: return nil
        case .value(let input):
            if input.isEmpty { return defaultYes }
            let lower = input.lowercased()
            return lower == "y" || lower == "yes"
        }
    }

    /// Yes/no confirmation that cannot be cancelled (empty → `defaultYes`). Used for the
    /// final "Create this app?" gate, where the user has already passed the cancel steps.
    static func confirm(_ message: String, defaultYes: Bool = true) -> Bool {
        confirmOrCancel(message, defaultYes: defaultYes) ?? false
    }

    // MARK: - Step header

    /// Prints a step header — `[Step n/total] Title` plus dim help lines — above a prompt,
    /// so the user knows where they are and what the option does. `help` may be multi-line.
    static func step(_ n: Int, of total: Int, title: String, help: String) {
        print("\n\(dim("[Step \(n)/\(total)]")) \(bold(title))")
        for line in help.split(separator: "\n", omittingEmptySubsequences: false) {
            print(dim("  \(line)"))
        }
    }

    /// Prints the one-time intro line explaining how to accept defaults and cancel.
    static func intro(_ message: String) {
        print(message)
        print(dim("Press Enter to accept the [default]. Type q to cancel.\n"))
    }

    // MARK: - ANSI styling (no-ops when stdout isn't a terminal)

    private static var styled: Bool { isatty(STDOUT_FILENO) == 1 }
    private static func dim(_ s: String) -> String { styled ? "\u{001B}[2m\(s)\u{001B}[0m" : s }
    private static func bold(_ s: String) -> String { styled ? "\u{001B}[1m\(s)\u{001B}[0m" : s }
}
