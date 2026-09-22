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
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .systemRed).opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: "1.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .font(.system(size: 26, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Shot and Tell")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Screenshots you can point at. Mark things up with numbers, describe them, and hand the picture and the words over together.")
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
            Text("I'm **Rob Gough** — a tech advisor and fractional CTO offering a senior pair of eyes on tech strategy and what to build next, drawing on a long career in engineering and tech leadership. I'm also building **Stay Upfront**, a unified support and incident management tool for B2B SaaS companies.")
            Text("Shot and Tell came out of a small, daily annoyance. I'd paste a screenshot to an AI and then write a paragraph trying to describe *where* on it I meant — \"the heading, no, the one above that, on the left\" — and half the time it answered about the wrong thing. Numbering what I wanted to talk about turned out to be the whole fix. Once the numbers are on the picture, the same numbers can carry the words, so the model gets the pixels and the sentences at once and there's nothing left to be vague about.")
            Text("I use it most days for exactly that. I hope you find it useful — and thank you for giving it a try.")
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
            Text("Nothing leaves your Mac, and that isn't a promise — it's a build setting. Shot and Tell ships without the network entitlement, so it has no way to reach the internet even if it wanted to.")
            Text("Screenshots are held in memory while you mark them up. The only thing ever written to disk is the finished image, in the folder you choose. Redactions are composited into that image rather than drawn over it, so the pixels underneath never reach the clipboard or the file.")
            Text("If Apple Intelligence is available, the title is suggested by Apple's on-device model. That runs locally too. There is no telemetry, no analytics and no account.")
            Text("Shot and Tell is provided as-is. Please use it for what it's good at, and let me know when it isn't.")
                .foregroundStyle(.secondary)
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
