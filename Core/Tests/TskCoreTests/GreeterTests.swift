import Testing
@testable import TskCore

@Suite("Greeter")
struct GreeterTests {
    @Test func greetsByName() {
        #expect(Greeter.greeting(for: "Ada") == "Hello, Ada!")
    }

    @Test func fallsBackToWorldWhenNameIsBlank() {
        #expect(Greeter.greeting(for: "   ") == "Hello, world!")
    }
}
