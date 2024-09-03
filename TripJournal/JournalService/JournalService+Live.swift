import Combine
import Foundation

enum HTTPMethods: String {
    case POST, GET, PUT, DELETE
}

enum MIMEType: String {
    case JSON = "application/json"
    case form = "application/x-www-form-urlencoded"
}

enum HTTPHeaders: String {
    case accept
    case contentType = "Content-Type"
    case authorization = "Authorization"
}

enum NetworkError: Error {
    case badUrl
    case badResponse
    case failedToDecodeResponse
    case invalidValue
}

enum SessionError: Error {
    case expired
}

class LiveJournalService: JournalService {
    
    enum EndPoints {
        static let base = "http://localhost:8000/"
        
        case register
        case login
        case trips
        case handleTrip(String)
        case events
        case handleEvent(String)
        case media
        case deleteMedia(String)
        
        private var stringValue: String {
            switch self {
            case .register:
                return EndPoints.base + "register"
            case .login:
                return EndPoints.base + "token"
            case .trips:
                return EndPoints.base + "trips"
            case .handleTrip(let tripId):
                return EndPoints.base + "trips/\(tripId)"
            case .events:
                return EndPoints.base + "events"
            case .handleEvent(let eventId):
                return EndPoints.base + "events/\(eventId)"
            case .media:
                return EndPoints.base + "media"
            case .deleteMedia(let mediaId):
                return EndPoints.base + "media/\(mediaId)"
            }
        }
        
        var url: URL {
            return URL(string: stringValue)!
        }
    }
    
    private let urlSession: URLSession
    
    init(delay: TimeInterval = 0) {
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        self.urlSession = URLSession(configuration: configuration)
    }
    
    @Published private var token: Token?
    
    var isAuthenticated: AnyPublisher<Bool, Never> {
        $token
            .map { $0 != nil }
            .eraseToAnyPublisher()
    }
    
    func register(username: String, password: String) async throws -> Token {
        let request = try createRegisterRequest(username: username, password: password)
        return try await performNetworkRequest(request, responseType: Token.self)
    }
    
    private func createRegisterRequest(username: String, password: String) throws -> URLRequest {
        var request = URLRequest(url: EndPoints.register.url)
        request.httpMethod = HTTPMethods.POST.rawValue
        request.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        request.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)
        
        let registerRequest = LoginRequest(username: username, password: password)
        request.httpBody = try JSONEncoder().encode(registerRequest)
        
        return request
    }
    
    func logIn(username: String, password: String) async throws -> Token {
        let request = try createLoginRequest(username: username, password: password)
        return try await performNetworkRequest(request, responseType: Token.self)
    }
    
    private func createLoginRequest(username: String, password: String) throws -> URLRequest {
        var request = URLRequest(url: EndPoints.login.url)
        request.httpMethod = HTTPMethods.POST.rawValue
        request.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        request.addValue(MIMEType.form.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)

        let loginData = "grant_type=&username=\(username)&password=\(password)"
        request.httpBody = loginData.data(using: .utf8)

        return request
    }
    
    func logOut() {
        token = nil
    }
    
    func createTrip(with request: TripCreate) async throws -> Trip {
        guard let token = token else {
            throw NetworkError.invalidValue
        }

        var requestURL = URLRequest(url: EndPoints.trips.url)
        requestURL.httpMethod = HTTPMethods.POST.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let tripData: [String: Any] = [
            "name": request.name,
            "start_date": dateFormatter.string(from: request.startDate),
            "end_date": dateFormatter.string(from: request.endDate)
        ]
        requestURL.httpBody = try JSONSerialization.data(withJSONObject: tripData)

        return try await performNetworkRequest(requestURL, responseType: Trip.self)
    }
    
    func getTrips() async throws -> [Trip] {
        guard let token = token else {
            throw NetworkError.invalidValue
        }

        var requestURL = URLRequest(url: EndPoints.trips.url)
        requestURL.httpMethod = HTTPMethods.GET.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)

        return try await performNetworkRequest(requestURL, responseType: [Trip].self)
    }
    
    func getTrip(withId tripId: Trip.ID) async throws -> Trip {
        guard let token = token else {
            throw NetworkError.invalidValue
        }

        var requestURL = URLRequest(url: EndPoints.handleTrip(String(tripId)).url)
        requestURL.httpMethod = HTTPMethods.GET.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)

        return try await performNetworkRequest(requestURL, responseType: Trip.self)
    }
    
    func updateTrip(withId tripId: Trip.ID, and request: TripUpdate) async throws -> Trip {
        guard let token = token else {
            throw NetworkError.invalidValue
        }

        var requestURL = URLRequest(url: EndPoints.handleTrip(String(tripId)).url)
        requestURL.httpMethod = HTTPMethods.PUT.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let tripData: [String: Any] = [
            "name": request.name,
            "start_date": dateFormatter.string(from: request.startDate),
            "end_date": dateFormatter.string(from: request.endDate)
        ]
        requestURL.httpBody = try JSONSerialization.data(withJSONObject: tripData)
        
        return try await performNetworkRequest(requestURL, responseType: Trip.self)
    }
    
    func deleteTrip(withId tripId: Trip.ID) async throws {
        guard let token = token else {
            throw NetworkError.invalidValue
        }

        var requestURL = URLRequest(url: EndPoints.handleTrip(String(tripId)).url)
        requestURL.httpMethod = HTTPMethods.DELETE.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)

        try await performVoidNetworkRequest(requestURL)
    }
    
    func createEvent(with request: EventCreate) async throws -> Event {
        guard let token = token else {
            throw NetworkError.invalidValue
        }

        var requestURL = URLRequest(url: EndPoints.events.url)
        requestURL.httpMethod = HTTPMethods.POST.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        let locationData: [String: Any] = [
            "latitude": request.location?.latitude ?? 0,
            "longitude": request.location?.longitude ?? 0,
            "address": request.location?.address ?? "",
        ]

        let eventData: [String: Any] = [
            "name": request.name,
            "date": dateFormatter.string(from: request.date),
            "note": request.note ?? "",
            "location": locationData,
            "transition_from_previous": request.transitionFromPrevious ?? "",
            "trip_id": request.tripId,
        ]
        requestURL.httpBody = try JSONSerialization.data(withJSONObject: eventData)

        return try await performNetworkRequest(requestURL, responseType: Event.self)
    }
    
    func updateEvent(withId eventId: Event.ID, and request: EventUpdate) async throws -> Event {
        guard let token = token else {
            throw NetworkError.invalidValue
        }

        var requestURL = URLRequest(url: EndPoints.handleEvent(String(eventId)).url)
        requestURL.httpMethod = HTTPMethods.PUT.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        let locationData: [String: Any] = [
            "latitude": request.location?.latitude ?? 0,
            "longitude": request.location?.longitude ?? 0,
            "address": request.location?.address ?? "",
        ]

        let eventData: [String: Any] = [
            "name": request.name,
            "date": dateFormatter.string(from: request.date),
            "note": request.note ?? "",
            "location": locationData,
            "transition_from_previous": request.transitionFromPrevious ?? "",
        ]
        requestURL.httpBody = try JSONSerialization.data(withJSONObject: eventData)

        return try await performNetworkRequest(requestURL, responseType: Event.self)
    }
    
    func deleteEvent(withId eventId: Event.ID) async throws {
        guard let token = token else {
            throw NetworkError.invalidValue
        }

        var requestURL = URLRequest(url: EndPoints.handleEvent(String(eventId)).url)
        requestURL.httpMethod = HTTPMethods.DELETE.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)

        try await performVoidNetworkRequest(requestURL)
    }
    
    @discardableResult
    func createMedia(with request: MediaCreate) async throws -> Media {
        guard let token = token else {
            throw NetworkError.invalidValue
        }

        var requestURL = URLRequest(url: EndPoints.media.url)
        requestURL.httpMethod = HTTPMethods.POST.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)

        let base64Str = request.base64Data.base64EncodedString(options: .lineLength64Characters)
        
        let mediaData: [String: Any] = [
            "event_id": request.eventId,
            "base64_data": base64Str
        ]
        
        requestURL.httpBody = try JSONSerialization.data(withJSONObject: mediaData)

        return try await performNetworkRequest(requestURL, responseType: Media.self)
    }
    
    func deleteMedia(withId mediaId: Media.ID) async throws {
        guard let token = token else {
            throw NetworkError.invalidValue
        }

        var requestURL = URLRequest(url: EndPoints.deleteMedia(String(mediaId)).url)
        requestURL.httpMethod = HTTPMethods.DELETE.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)

        try await performVoidNetworkRequest(requestURL)
    }
    
    private func performNetworkRequest<T: Decodable>(_ request: URLRequest, responseType: T.Type) async throws -> T {
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.badResponse
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let object = try decoder.decode(T.self, from: data)
            if var token = object as? Token {
                token.expirationDate = Token.defaultExpirationDate()
                self.token = token
            }
            return object
        } catch {
            throw NetworkError.failedToDecodeResponse
        }
    }
    
    private func performVoidNetworkRequest(_ request: URLRequest) async throws {
        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
            throw NetworkError.badResponse
        }
    }
    
}
