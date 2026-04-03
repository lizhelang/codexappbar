import XCTest

final class LocalhostOAuthCallbackServerTests: XCTestCase {
    func testCallbackURLParsesValidRequestLine() {
        let request = """
        GET /auth/callback?code=abc123&state=xyz HTTP/1.1\r
        Host: localhost:1455\r
        Connection: close\r
        \r
        """

        let callbackURL = LocalhostOAuthCallbackServer.callbackURL(from: request)
        XCTAssertEqual(callbackURL, "http://localhost:1455/auth/callback?code=abc123&state=xyz")
    }

    func testCallbackURLRejectsNonCallbackRoutes() {
        let request = """
        GET /favicon.ico HTTP/1.1\r
        Host: localhost:1455\r
        \r
        """

        XCTAssertNil(LocalhostOAuthCallbackServer.callbackURL(from: request))
    }
}
