import AppKit
import SwiftUI

/// The About window's contents.
///
/// More than the standard panel gives, in the same shape as Dictator's: what the
/// app is, who made it, and — for an app that reads your screen — exactly what
/// does and doesn't leave the machine.
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                author
                privacy
                utilities
                copyright
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return switch (short, build) {
        case let (short?, build?) where short != build: "Version \(short) (\(build))"
        case let (short?, _): "Version \(short)"
        default: ""
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            // The actual app icon, not an approximation of it. NSApp holds the
            // one the system is already showing in the Dock.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Shot and Tell")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Screenshots you can point at.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !version.isEmpty {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var author: some View {
        section("Author") {
            Text("I'm **Rob Gough** — a tech advisor and fractional CTO. I'm also building **StayUpfront**, support and incident management for B2B SaaS companies.")
            Text("I made this because describing *where* on a screenshot I meant was taking longer than the screenshot saved.")
            HStack(spacing: 14) {
                Link(destination: URL(string: "https://stayupfront.com")!) {
                    Label("stayupfront.com", systemImage: "bolt.horizontal")
                }
                Link(destination: URL(string: "mailto:hello@robgough.net")!) {
                    Label("hello@robgough.net", systemImage: "envelope")
                }
            }
            .font(.callout)
        }
    }

    private var privacy: some View {
        section("Privacy") {
            Text("Shot and Tell ships without the network entitlement, so it can't reach the internet at all. No telemetry, no analytics, no account.")
            Text("Redactions are composited into the exported image, so whatever was underneath never reaches the clipboard or the file. Titles are suggested by Apple's on-device model, if you have one.")
        }
    }

    private var utilities: some View {
        section("Saved screenshots") {
            HStack {
                Text(Settings.shared.saveFolderDisplayName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button("Reveal in Finder") {
                    revealSaveFolder()
                }
                .controlSize(.small)
            }
            .font(.callout)
        }
    }

    private func revealSaveFolder() {
        if let chosen = Settings.shared.resolveSaveFolder() {
            defer { chosen.stopAccessing() }
            NSWorkspace.shared.activateFileViewerSelecting([chosen.url])
            return
        }
        guard let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first else { return }
        let folder = pictures.appending(path: "Shot and Tell", directoryHint: .isDirectory)
        // Created on first export, so it may not be there yet — fall back to
        // Pictures rather than opening nothing at all.
        let target = FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) ? folder : pictures
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    /// The standard About panel showed NSHumanReadableCopyright for us; this
    /// one has to say it itself.
    private var copyright: some View {
        Text("© 2026 Rob Gough. MIT licensed.")
            .font(.footnote)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
