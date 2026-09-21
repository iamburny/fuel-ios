import Testing
import Foundation
@testable import FuelTracker

struct DeepLinkTests {
    @Test func stationPath() {
        let url = URL(string: "https://fueltracker.uk/stations/431")!
        #expect(DeepLink.from(url: url) == .station(431))
    }

    /// fuel-web serves a station at both `/stations/4312` and a slug form carrying the same
    /// leading id. An installed build has to resolve either, or a tap on a shared link drops the
    /// user on the default screen having asked for a specific station.
    @Test func stationPathWithSlug() {
        let url = URL(string: "https://fueltracker.uk/stations/4312-shell-high-street-guildford")!
        #expect(DeepLink.from(url: url) == .station(4312))
    }

    @Test func slugContainingDigitsIsNotAStation() {
        #expect(DeepLink.from(url: URL(string: "https://fueltracker.uk/stations/shell-4312")!) == nil)
        #expect(DeepLink.from(url: URL(string: "https://fueltracker.uk/stations/guildford")!) == nil)
    }

    /// Guards the looser "leading run of digits" reading, which would accept this.
    @Test func digitsMustEndTheSegmentOrMeetAHyphen() {
        #expect(DeepLink.from(url: URL(string: "https://fueltracker.uk/stations/4312abc")!) == nil)
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

    @Test func stationsPathWithNoIdReturnsNil() {
        let url = URL(string: "https://fueltracker.uk/stations")!
        #expect(DeepLink.from(url: url) == nil)
    }
}
