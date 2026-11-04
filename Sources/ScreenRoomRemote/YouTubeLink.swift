import Foundation

enum YouTubeLink {
    /// Only accept a specific YouTube video, then reconstruct the URL to avoid passing arbitrary shell text to ADB.
    static func videoID(_ input: String) -> String? {
        guard let url = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host?.lowercased() else { return nil }
        let id: String?
        if host == "youtu.be" {
            id = url.path.split(separator: "/").first.map(String.init)
        } else if ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(host), url.path == "/watch" {
            id = url.queryItems?.first(where: { $0.name == "v" })?.value
        } else { return nil }
        guard let id, id.count == 11, id.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return id
    }
}
