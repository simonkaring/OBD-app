import XCTest
@testable import VoltLinkEngine

final class AILogAnalyzerTests: XCTestCase {

    func testPromptConstructionIncludesSentAndResponse() {
        let entries = [
            OBDLogEntry(timestamp: Date(), sent: "22010A", response: "62 01 0A 0F 8C\r\n>"),
            OBDLogEntry(timestamp: Date(), sent: "220210", response: "62 02 10 04 00 00 39 90\r\n>")
        ]

        let prompt = AILogAnalyzer.buildAnalysisPrompt(log: entries, vehicleContext: "Mercedes-Benz EQA 250")

        XCTAssertTrue(prompt.contains("Mercedes-Benz EQA 250"))
        XCTAssertTrue(prompt.contains("22010A"))
        XCTAssertTrue(prompt.contains("62 01 0A 0F 8C"))
        XCTAssertTrue(prompt.contains("220210"))
        XCTAssertTrue(prompt.contains("62 02 10 04 00 00 39 90"))
    }

    func testEmptyApiKeyThrowsMissingApiKey() async {
        let entries = [
            OBDLogEntry(timestamp: Date(), sent: "0100", response: "41 00 BE 3F B8 13\r\n>")
        ]

        do {
            _ = try await AILogAnalyzer.analyze(log: entries, vehicleContext: "Test Vehicle", apiKey: "   ")
            XCTFail("Expected missingAPIKey error to be thrown")
        } catch let error as AILogAnalyzerError {
            if case .missingAPIKey = error {
                XCTAssertEqual(error.localizedDescription, "Please provide an API Key in Developer Settings.")
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExportPreservesCANFrameBoundariesAndTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 1_788_000_000)
        let raw = "18 DA F1 59 10 0B 62 02 10 04 00 00\r18 DA F1 59 21 40 F4 00 00 00 00 00\r>"
        let prompt = AILogAnalyzer.buildAnalysisPrompt(log: [
            OBDLogEntry(timestamp: timestamp, sent: "220210", response: raw)
        ])
        XCTAssertTrue(prompt.contains(raw))
        XCTAssertTrue(prompt.contains(timestamp.ISO8601Format()))
    }
}
