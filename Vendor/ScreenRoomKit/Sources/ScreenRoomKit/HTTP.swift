import Foundation

/// The only door to the network. Tests replace it with a fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ScreenRoomError.badResponse }
        return (data, http.statusCode)
    }
}

extension HTTPTransport {
    /// Sends the request and maps transport and status failures to `ScreenRoomError`.
    func fetch(_ request: URLRequest) async throws -> Data {
        let data: Data
        let status: Int
        do {
            (data, status) = try await send(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw ScreenRoomError.offline
        }
        switch status {
        case 200..<300: return data
        case 401: throw ScreenRoomError.keyRejected
        case 404: throw ScreenRoomError.notFound
        case 429: throw ScreenRoomError.rateLimited
        default: throw ScreenRoomError.server(status)
        }
    }
}

enum Query {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Builds a URL with every query value strictly percent-encoded (`&`, `+` and `|` included).
    static func url(_ base: String, _ items: [(String, String)]) -> URL {
        var components = URLComponents(string: base)!
        components.percentEncodedQueryItems = items.map { name, value in
            URLQueryItem(name: name, value: value.addingPercentEncoding(withAllowedCharacters: unreserved))
        }
        return components.url!
    }
}

extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func decodeResponse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decode(type, from: data)
        } catch {
            throw ScreenRoomError.badResponse
        }
    }
}
