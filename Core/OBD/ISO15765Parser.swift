import Foundation

public final class ISO15765Parser: Sendable {
    public init() {}

    /// Cleans raw response from ELM327 adapter (removes headers, spaces, linefeeds, prompt >)
    public func cleanELMResponse(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: ">", with: "")
                      .replacingOccurrences(of: "\r", with: "\n")
                      .replacingOccurrences(of: "SEARCHING...", with: "")
                      .replacingOccurrences(of: "BUS INIT...", with: "")
                      .replacingOccurrences(of: "STOPPED", with: "")
                      .trimmingCharacters(in: .whitespacesAndNewlines)

        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    /// Assembles multi-line ISO 15765-4 (ISO-TP) CAN frames into a single payload string
    public func assembleISOTPPayload(_ rawResponse: String) -> String {
        let cleanText = cleanELMResponse(rawResponse)
        let lines = cleanText.components(separatedBy: .newlines)
        
        var payloadHex = ""

        for line in lines {
            let tokens = line.split(separator: " ").map(String.init)
            guard !tokens.isEmpty else { continue }
            
            // Check if headers are included, either 11-bit (e.g. 7E8 06 41 0D ...) or
            // 29-bit ISO 15765-4 extended addressing (e.g. 18 DA F1 59 05 62 01 0A ...,
            // used by the Mercedes UDS gateway's physical/functional addressing).
            var hexTokens = tokens
            if tokens.count >= 4, ["18", "19"].contains(tokens[0].uppercased()),
               tokens[1...3].allSatisfy({ $0.count == 2 && Int($0, radix: 16) != nil }) {
                hexTokens = Array(tokens.dropFirst(4))
            } else if tokens.first?.count == 3, Int(tokens.first!, radix: 16) != nil {
                hexTokens = Array(tokens.dropFirst())
            }

            guard !hexTokens.isEmpty else { continue }

            let firstByteStr = hexTokens[0]
            guard let firstByte = UInt8(firstByteStr, radix: 16) else {
                payloadHex += hexTokens.joined()
                continue
            }

            let frameType = (firstByte & 0xF0) >> 4

            switch frameType {
            case 0: // Single Frame (0x0N length)
                let length = Int(firstByte & 0x0F)
                if length > 0, hexTokens.count >= 1 + length {
                    let dataBytes = hexTokens[1...(length)]
                    payloadHex += dataBytes.joined()
                } else {
                    payloadHex += hexTokens.dropFirst().joined()
                }

            case 1: // First Frame (0x1N length)
                // Multi-frame header contains length in first 2 bytes
                if hexTokens.count >= 2 {
                    let dataBytes = hexTokens.dropFirst(2)
                    payloadHex += dataBytes.joined()
                }

            case 2: // Consecutive Frame (0x2N sequence index)
                if hexTokens.count >= 1 {
                    let dataBytes = hexTokens.dropFirst(1)
                    payloadHex += dataBytes.joined()
                }

            default:
                payloadHex += hexTokens.joined()
            }
        }

        return payloadHex
    }
}
