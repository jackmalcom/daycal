import AppKit
import Foundation

@MainActor
final class UpdateManager: ObservableObject {
    private let owner = "jackmalcom"
    private let repo = "daycal"
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private let lastCheckKey = "DaycalLastUpdateCheck"
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            await self.checkIfNeeded(force: false)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.checkInterval * 1_000_000_000))
                await self.checkIfNeeded(force: true)
            }
        }
    }

    private func checkIfNeeded(force: Bool) async {
        let now = Date()
        if !force, let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date {
            if now.timeIntervalSince(lastCheck) < checkInterval {
                return
            }
        }
        UserDefaults.standard.set(now, forKey: lastCheckKey)

        do {
            let release = try await fetchLatestRelease()
            guard let latestBuild = buildNumber(from: release.tagName) else { return }
            let currentBuild = currentBuildNumber()
            guard latestBuild > currentBuild else { return }

            promptToUpdate(release: release)
        } catch {
            return
        }
    }

    private func currentBuildNumber() -> Int {
        let buildString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return Int(buildString ?? "0") ?? 0
    }

    private func buildNumber(from tag: String) -> Int? {
        guard tag.hasPrefix("build-") else { return nil }
        return Int(tag.replacingOccurrences(of: "build-", with: ""))
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func promptToUpdate(release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "Update available"
        alert.informativeText = "A newer build of Daycal is available."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        if let assetURL = release.assets.first?.browserDownloadURL ?? release.htmlURL {
            NSWorkspace.shared.open(assetURL)
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case browserDownloadURL = "browser_download_url"
    }
}
