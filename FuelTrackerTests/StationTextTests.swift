import Testing
@testable import FuelTracker

/// The same real feed values fuel-web's stationText tests pin, so every platform agrees.
struct StationTextTests {
    @Test func titleCasesAllCapsAndAllLowercaseNames() {
        #expect(StationText.displayName("HORSPATH SERVICE STATION LTD") == "Horspath Service Station Ltd")
        #expect(StationText.displayName("SAINSBURYS HEYFORD HILL") == "Sainsburys Heyford Hill")
        #expect(StationText.displayName("ivor miles ltd") == "Ivor Miles Ltd")
    }

    @Test func leavesDeliberateCasingAlone() {
        #expect(StationText.displayName("BP Yarnton") == "BP Yarnton")
        #expect(StationText.displayName("Esso - Riffa Serviuce Station") == "Esso - Riffa Serviuce Station")
    }

    @Test func keepsInitialismsAndCodesButNotBrandsWrittenAsWords() {
        #expect(StationText.displayName("MFG CHERWELL") == "MFG Cherwell")
        #expect(StationText.displayName("EG ON THE MOVE") == "EG on the Move")
        #expect(StationText.displayName("ASDA WHEATLEY SUPERSTORE") == "Asda Wheatley Superstore")
        #expect(StationText.displayName("ESSO A34 NORTHBOUND") == "Esso A34 Northbound")
    }

    @Test func handlesHyphensMinorWordsApostrophesAndSeparators() {
        #expect(StationText.displayName("SHELL CO-OP COWLEY") == "Shell Co-op Cowley")
        #expect(StationText.displayName("GULF-NISA HOLLINWOOD SERVICE STATION") == "Gulf-Nisa Hollinwood Service Station")
        #expect(StationText.displayName("LAKES AND DALES CO-OPERATIVE") == "Lakes and Dales Co-operative")
        #expect(StationText.displayName("STATION TO GO ON") == "Station to Go On")
        #expect(StationText.displayName("TOUT'S NAILSEA") == "Tout's Nailsea")
        #expect(StationText.displayName("O'BRIEN GARAGE") == "O'Brien Garage")
        #expect(StationText.displayName("D.J.JOHNSON & SONS LTD") == "D.J.Johnson & Sons Ltd")
        #expect(StationText.displayName("TOUT S LANGFORD (ESSO)") == "Tout S Langford (Esso)")
        #expect(StationText.displayName("54-56 OXFORD ROAD") == "54-56 Oxford Road")
        #expect(StationText.displayName("1ST AVENUE GARAGE") == "1st Avenue Garage")
    }

    @Test func collapsesWhitespaceAndHandlesEmptyValues() {
        #expect(StationText.displayName("SHELL  CO-OP WHITEMARE POOL ") == "Shell Co-op Whitemare Pool")
        #expect(StationText.displayName(nil) == "")
        #expect(StationText.displayName("   ") == "")
    }
}
