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
                
            }
        }
        
        var url: URL {
            return URL(string: stringValue)!
        }
    }
    
    private let urlSession: URLSession
    
    // TODO: Remove
    private struct MockError: Error {}
    
    init(delay: TimeInterval = 0) {
        // TODO: Delete delay
        self.delay = delay
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        self.urlSession = URLSession(configuration: configuration)
    }
    
    private let delay: TimeInterval
    private var trips = Trip.sample
    
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
        
        
        
        try await Task.sleep(for: .seconds(delay))
        for tripIndex in trips.indices {
            for (eventIndex, event) in trips[tripIndex].events.enumerated() where event.id == request.eventId {
                let newMedia = Media(from: request)
                trips[tripIndex].events[eventIndex].medias.append(newMedia)
                return newMedia
            }
        }
        throw MockError()
    }
    
    func deleteMedia(withId mediaId: Media.ID) async throws {
        try await Task.sleep(for: .seconds(delay))
        for tripIndex in trips.indices {
            for eventIndex in trips[tripIndex].events.indices {
                for (mediaIndex, media) in trips[tripIndex].events[eventIndex].medias.enumerated() where media.id == mediaId {
                    trips[tripIndex].events[eventIndex].medias.remove(at: mediaIndex)
                    return
                }
            }
        }
        throw MockError()
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

//    extension Event {
//        init(from create: EventCreate) {
//            id = Int.random(in: 0 ... 1000)
//            name = create.name
//            note = create.note
//            date = create.date
//            location = create.location
//            medias = []
//            transitionFromPrevious = create.transitionFromPrevious
//        }
//
//        mutating func update(from update: EventUpdate) {
//            name = update.name
//            note = update.note
//            date = update.date
//            location = update.location
//            transitionFromPrevious = update.transitionFromPrevious
//        }
//
//        static let amsterdam: [Self] = [
//            .init(
//                id: 1,
//                name: "Canal Tour",
//                note: nil,
//                date: Date(day: 1, month: 6, year: 2024),
//                location: .init(latitude: 52.3676, longitude: 4.9041, address: "Amsterdam"),
//                medias: [
//                    .randomPlaceholder(),
//                    .randomPlaceholder(),
//                    .randomPlaceholder(),
//                ],
//                transitionFromPrevious: "Walk from Hotel"
//            ),
//            .init(
//                id: 2,
//                name: "Visit to the Van Gogh Museum",
//                note: "A vivid, unforgettable art experience...",
//                date: Date(day: 2, month: 6, year: 2024),
//                location: .init(latitude: 52.3584, longitude: 4.8811, address: "Museumplein, Amsterdam"),
//                medias: [
//                    .randomPlaceholder(),
//                    .randomPlaceholder(),
//                ],
//                transitionFromPrevious: "Tram ride from hotel"
//            ),
//            .init(
//                id: 3,
//                name: "Lunch",
//                note: "The best pizza ever!",
//                date: Date(day: 3, month: 6, year: 2024),
//                location: nil,
//                medias: [],
//                transitionFromPrevious: nil
//            ),
//            .init(
//                id: 4,
//                name: "Evening at Dam Square",
//                note: nil,
//                date: Date(day: 4, month: 6, year: 2024),
//                location: .init(latitude: 52.3731, longitude: 4.8936, address: "Dam Square, Amsterdam"),
//                medias: [
//                    .randomPlaceholder(),
//                    .randomPlaceholder(),
//                ],
//                transitionFromPrevious: "Walk from the Jordaan neighborhood"
//            ),
//        ]
//
//        static let rome: [Self] = [
//            .init(
//                id: 3,
//                name: "Colosseum Tour",
//                note: nil,
//                date: Date(day: 10, month: 7, year: 2024),
//                location: .init(latitude: 41.8902, longitude: 12.4922, address: "Rome"),
//                medias: [
//                    .randomPlaceholder(),
//                ],
//                transitionFromPrevious: "Arrival in Rome"
//            ),
//            .init(
//                id: 4,
//                name: "Vatican Visit",
//                note: nil,
//                date: Date(day: 12, month: 7, year: 2024),
//                location: .init(latitude: 41.9029, longitude: 12.4534, address: "Vatican City"),
//                medias: [
//                    .randomPlaceholder(),
//                ],
//                transitionFromPrevious: "Metro from Rome"
//            ),
//        ]
//
//        static let tokyo: [Self] = [
//            .init(
//                id: 5,
//                name: "Shinjuku Exploration",
//                note: nil,
//                date: Date(day: 20, month: 8, year: 2024),
//                location: .init(latitude: 35.6895, longitude: 139.6917, address: "Tokyo"),
//                medias: [.init(id: 5, url: URL(string: "https://picsum.photos/id/1/640/360"))],
//                transitionFromPrevious: "Arrival at Haneda Airport"
//            ),
//            .init(
//                id: 6,
//                name: "Sushi Tasting",
//                note: nil,
//                date: Date(day: 22, month: 8, year: 2024),
//                location: .init(latitude: 35.6895, longitude: 139.6917, address: "Tokyo"),
//                medias: [
//                    .randomPlaceholder(),
//                ],
//                transitionFromPrevious: "Walk through Tsukiji"
//            ),
//        ]
//
//        static let paris: [Self] = [
//            .init(
//                id: 7,
//                name: "Eiffel Tower Visit",
//                note: nil,
//                date: Date(day: 5, month: 9, year: 2024),
//                location: .init(latitude: 48.8584, longitude: 2.2945, address: "Paris"),
//                medias: [
//                    .randomPlaceholder(),
//                    .randomPlaceholder(),
//                    .randomPlaceholder(),
//                    .randomPlaceholder(),
//                    .randomPlaceholder(),
//                    .randomPlaceholder(),
//                ],
//                transitionFromPrevious: "Arrival at Charles de Gaulle"
//            ),
//            .init(
//                id: 8,
//                name: "Louvre Museum Tour",
//                note: nil,
//                date: Date(day: 7, month: 9, year: 2024),
//                location: nil,
//                medias: [],
//                transitionFromPrevious: "Metro ride from hotel"
//            ),
//        ]
//    }
//
//    extension Media {
//        static func randomPlaceholder() -> Self {
//            let id = Int.random(in: 0 ... 1000)
//            return Self(id: id, url: URL(string: "https://picsum.photos/id/\(id)/640/360"))
//        }
//    }
//
//    extension Trip {
//        init(from create: TripCreate) {
//            id = Int.random(in: 0 ... 1000)
//            name = create.name
//            startDate = create.startDate
//            endDate = create.endDate
//            events = []
//        }
//
//        mutating func update(from update: TripUpdate) {
//            name = update.name
//            startDate = update.startDate
//            endDate = update.endDate
//        }
//
//        static let sample: [Self] = {
//            let amsterdamAdventure = Trip(
//                id: 1,
//                name: "Amsterdam Adventure",
//                startDate: Date(day: 1, month: 6, year: 2024),
//                endDate: Date(day: 5, month: 6, year: 2024),
//                events: Event.amsterdam
//            )
//
//            let romeRetreat = Trip(
//                id: 2,
//                name: "Rome Retreat",
//                startDate: Date(day: 10, month: 7, year: 2024),
//                endDate: Date(day: 15, month: 7, year: 2024),
//                events: Event.rome
//            )
//
//            let tokyoTour = Trip(
//                id: 3,
//                name: "Tokyo Tour",
//                startDate: Date(day: 20, month: 8, year: 2024),
//                endDate: Date(day: 25, month: 8, year: 2024),
//                events: Event.tokyo
//            )
//
//            let parisPilgrimage = Trip(
//                id: 4,
//                name: "Paris Pilgrimage",
//                startDate: Date(day: 5, month: 9, year: 2024),
//                endDate: Date(day: 10, month: 9, year: 2024),
//                events: Event.paris
//            )
//
//            return [amsterdamAdventure, romeRetreat, tokyoTour, parisPilgrimage]
//        }()
//    }
//
//    extension Media {
//        init(from _: MediaCreate) {
//            self = .randomPlaceholder()
//        }
//    }
//
//    extension Trip: Comparable {
//        static func < (lhs: Self, rhs: Self) -> Bool {
//            return lhs.startDate < rhs.startDate
//        }
//    }
//
//    extension Event: Comparable {
//        static func < (lhs: Self, rhs: Self) -> Bool {
//            return lhs.date < rhs.date
//        }
//    }

//    private extension Date {
//        init(day: Int, month: Int, year: Int) {
//            var dateComponents = DateComponents()
//            dateComponents.year = year
//            dateComponents.month = month
//            dateComponents.day = day
//
//            guard let date = Calendar.current.date(from: dateComponents) else {
//                fatalError("Invalid date components: \(year)-\(month)-\(day)")
//            }
//            self = date
//        }
//    }

