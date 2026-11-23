import Foundation
import Testing

@testable import RTMPHaishinKit

@Suite struct AMFFoundationTests {
    static let hello: String = "<a>hello</a>"

    @Test func array() {
        var array = AMFArray()
        array[5] = "hoge"
        if let array_5: String = array[5] as? String {
            #expect(array_5 == "hoge")
        }
    }

    @Test func dictionaryKeysTakePrecedenceOverNumericIndices() {
        var array = AMFArray(["0": "field", "2026": "season", "-1": "negative", "1": nil])
        array[0] = "index"
        array[1] = "another index"
        #expect(array["0"] as? String == "field")
        #expect(array[0] as? String == "index")
        #expect(array["2026"] as? String == "season")
        #expect(array["-1"] as? String == "negative")
        #expect(array["1"] == nil)
        #expect(array[1] as? String == "another index")
        array[2] = "fallback"
        #expect(array["2"] as? String == "fallback")
        array["0"] = "updated field"
        array["2026"] = "next season"
        array["-1"] = "updated negative"
        array["1"] = "was nil"
        #expect(array["0"] as? String == "updated field")
        #expect(array[0] as? String == "index")
        #expect(array["2026"] as? String == "next season")
        #expect(array["-1"] as? String == "updated negative")
        #expect(array["1"] as? String == "was nil")
        array["1"] = nil
        #expect(array["1"] == nil)
        #expect(array[1] as? String == "another index")
    }

    @Test func xmlDocument() {
        let xml = AMFXMLDocument(data: AMFFoundationTests.hello)
        #expect(xml.description == AMFFoundationTests.hello)
    }

    @Test func xml() {
        let xml = AMFXML(data: AMFFoundationTests.hello)
        #expect(xml.description == AMFFoundationTests.hello)
    }
}
