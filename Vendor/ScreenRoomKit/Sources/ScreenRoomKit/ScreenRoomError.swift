import Foundation

public enum ScreenRoomError: Error, Equatable, Sendable {
    case keyRejected
    case rateLimited
    case notFound
    case server(Int)
    case badResponse
    case offline
    case modelUnavailable
    case unreadableImage
}

extension ScreenRoomError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .keyRejected: "TMDB did not accept the configured key."
        case .rateLimited: "TMDB is limiting requests right now. Try again in a moment."
        case .notFound: "That film could not be found."
        case .server(let status): "The service answered with an error (\(status))."
        case .badResponse: "The service sent something the app could not read."
        case .offline: "No connection to the service."
        case .modelUnavailable: "The on-device model is not available."
        case .unreadableImage: "That image could not be read."
        }
    }
}
