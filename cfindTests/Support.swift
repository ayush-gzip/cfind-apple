import XCTest
@testable import cfind

func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

func fixture<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    let url = try XCTUnwrap(Bundle(for: FixtureMarker.self).url(forResource: name, withExtension: "json"))
    return try JSONDecoder().decode(type, from: Data(contentsOf: url))
}

private final class FixtureMarker {}

func makeAgent(_ id: String = "a1", state: String = "idle", updatedAt: Double = 1, messages: String = "[]",
               pending: String = "null", error: String = "null", title: String = "Fix bug") -> Agent {
    let json = """
    {"id":"\(id)","profile":"p","cwd":"/x","title":"\(title)","state":"\(state)","startedAt":0,
     "updatedAt":\(updatedAt),"messages":\(messages),"queue":[],"error":\(error),"pending":\(pending)}
    """
    return try! decode(Agent.self, json)
}

func makeSession(_ path: String = "/s/1", id: String = "s", profile: String = "p", state: String,
                 title: String = "Refactor", updatedAt: Double = 1, parent: String? = nil) -> Session {
    let t = String(data: try! JSONEncoder().encode(title), encoding: .utf8)!
    let p = parent.map { #""\#($0)""# } ?? "null"
    let json = """
    {"id":"\(id)","profile":"\(profile)","source":"claude","path":"\(path)","cwd":"/x","title":\(t),
     "updatedAt":\(updatedAt),"state":"\(state)","open":true,"parent":\(p)}
    """
    return try! decode(Session.self, json)
}
