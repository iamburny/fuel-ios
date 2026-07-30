import Testing
import Foundation
@testable import FuelTracker

struct DeepLinkTests {
    @Test func stationPath() {
        let url = URL(string: "https://fueltracker.uk/stations/431")!
        #expect(DeepLink.from(url: url) == .station(431))
    }

    @Test func pricesPath() {
        let url = URL(string: "https://fueltracker.uk/prices")!
        #expect(DeepLink.from(url: url) == .prices)
    }

    @Test func settingsPath() {
        let url = URL(string: "https://fueltracker.uk/settings")!
        #expect(DeepLink.from(url: url) == .settings)
    }

    @Test func rootPathIsHome() {
        let url = URL(string: "https://fueltracker.uk/")!
        #expect(DeepLink.from(url: url) == .home)
    }

    @Test func hostIsCaseInsensitive() {
        let url = URL(string: "https://FuelTracker.UK/prices")!
        #expect(DeepLink.from(url: url) == .prices)
    }

    @Test func nonNumericStationIdReturnsNil() {
        let url = URL(string: "https://fueltracker.uk/stations/abc")!
        #expect(DeepLink.from(url: url) == nil)
    }

    @Test func unrecognizedPathReturnsNil() {
        let url = URL(string: "https://fueltracker.uk/something-else")!
        #expect(DeepLink.from(url: url) == nil)
    }

    @Test func wrongHostReturnsNil() {
        let url = URL(string: "https://example.com/stations/431")!
        #expect(DeepLink.from(url: url) == nil)
    }
}
