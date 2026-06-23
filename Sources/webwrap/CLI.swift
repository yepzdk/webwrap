import Foundation
import ArgumentParser

struct WebWrap: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "webwrap",
        abstract: "Wrap any website into a standalone macOS .app.",
        version: "0.1.0",
        subcommands: [Create.self],
        defaultSubcommand: Create.self
    )
}

struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a standalone .app bundle for a website."
    )

    @Option(name: [.short, .long], help: "The URL the app should open, e.g. https://outlook.office.com")
    var url: String

    @Option(name: [.short, .long], help: "The display name of the app, e.g. \"Outlook\".")
    var name: String

    @Option(name: [.short, .long], help: "Where to write the .app bundle. Defaults to /Applications.")
    var output: String = "/Applications"

    @Option(name: .long, help: "Bundle identifier. Defaults to dk.yepz.webwrap.<slug>.")
    var bundleId: String?

    @Option(name: .long, help: "Path to a .png or .icns icon. If omitted, the site's favicon is fetched.")
    var icon: String?

    @Option(name: .long, help: "Initial window width in points.")
    var width: Int = 1200

    @Option(name: .long, help: "Initial window height in points.")
    var height: Int = 800

    @Flag(name: .long, help: "Overwrite the destination .app if it already exists.")
    var force: Bool = false

    @Flag(name: .long, help: "Skip ad-hoc code signing (codesign --sign -).")
    var noSign: Bool = false

    func validate() throws {
        guard let parsed = URL(string: url), parsed.scheme != nil, parsed.host != nil else {
            throw ValidationError("`--url` must be an absolute URL including scheme, e.g. https://example.com")
        }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError("`--name` must not be empty.")
        }
    }

    func run() throws {
        let builder = AppBuilder(
            url: url,
            name: name,
            outputDir: output,
            bundleId: bundleId,
            iconPath: icon,
            width: width,
            height: height,
            force: force,
            sign: !noSign
        )
        let appPath = try builder.build()
        print("✓ Created \(appPath)")
    }
}
