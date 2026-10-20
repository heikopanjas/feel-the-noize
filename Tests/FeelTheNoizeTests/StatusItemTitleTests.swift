import Testing

@testable import FeelTheNoize

struct StatusItemTitleTests {
    @Test(
        "Dial status line",
        arguments: [
            (DialConnection.connected, Int?.some(85), "Surface Dial: Connected, battery 85 %"),
            (.connected, nil, "Surface Dial: Connected"),
            (.notConnected, 85, "Surface Dial: Not Connected"),
            (.inUseElsewhere, 85, "Surface Dial: In Use by Another App")
        ] as [(DialConnection, Int?, String)])
    func dialTitle(connection: DialConnection, battery: Int?, expected: String) {
        #expect(StatusItemController.title(for: connection, batteryLevel: battery) == expected)
    }
}
