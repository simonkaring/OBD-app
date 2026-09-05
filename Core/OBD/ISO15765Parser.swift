import Foundation

public final class ISO15765Parser: Sendable {
    public init() {}

    /// Cleans raw response from ELM327 adapter (removes headers, spaces, linefeeds, prompt >)
    public func cleanELMResponse(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: ">", with: "")
                      .replacingOccurrences(of: "\r", with: "\n")
                      .replacingOccurrences(of: "SEARCHING...", with: "")
                      .replacingOccurrences(of: "BUS INIT...", with: "")
                      .replacingOccurrences(of: "STOPPED", with: "")
                      .trimmingCharacters(in: .whitespacesAndNewlines)

        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    /// Assembles multi-line ISO 15765-4 (ISO-TP) CAN frames into a single payload string,
    /// concatenating every responding ECU's payload in arrival order. Kept for existing
    /// call sites; prefer `assembleISOTPPayloads(_:)` when the source ECU matters (e.g.
    /// merging DTCs from multiple modules).
    public func assembleISOTPPayload(_ rawResponse: String) -> String {
        assembleISOTPPayloads(rawResponse).map(\.payload).joined()
    }

    /// CAN identifier bucket for lines carrying no header at all (e.g. `AT H0`).
    public static let headerlessECU = ""

    private struct Bucket {
        var payloadHex = ""
        var multiFrameStart: Int?
        var multiFrameHexLength: Int?
        var expectedSeq: Int?
        var isInvalid = false
    }

    /// Assembles multi-line ISO 15765-4 (ISO-TP) CAN frames into one reassembled payload
    /// per responding ECU, keyed by the stripped CAN identifier ("7E8", "18DAF159",
    /// "17FE007B"), or `headerlessECU` for lines carrying no CAN ID. A second ECU's First
    /// Frame no longer clobbers another ECU's in-flight multi-frame message, and an
    /// out-of-order Consecutive Frame invalidates only that ECU's bucket.
    public func assembleISOTPPayloads(_ rawResponse: String) -> [(ecu: String, payload: String)] {
        let cleanText = cleanELMResponse(rawResponse)
        let lines = cleanText.components(separatedBy: .newlines)

        var buckets: [String: Bucket] = [:]
        var order: [String] = []

        for line in lines {
            let tokens = line.split(separator: " ").map(String.init)
            guard !tokens.isEmpty else { continue }

            // Check if headers are included, either 11-bit (e.g. 7E8 06 41 0D ...) or
            // 29-bit ISO 15765-4 extended addressing (e.g. 18 DA F1 59 05 62 01 0A ...,
            // used by the Mercedes UDS gateway's physical/functional addressing).
            var hexTokens = tokens
            var ecuKey = Self.headerlessECU
            if tokens.count >= 4, ["18", "19"].contains(tokens[0].uppercased()),
               tokens[1...3].allSatisfy({ $0.count == 2 && Int($0, radix: 16) != nil }) {
                hexTokens = Array(tokens.dropFirst(4))
                ecuKey = tokens[0...3].joined().uppercased()
            } else if let first = tokens.first, first.count == 3 || first.count == 8,
                      Int(first, radix: 16) != nil {
                // 3 hex chars = 11-bit CAN ID (7E8); 8 hex chars = a 29-bit ID printed as one
                // token, which is what `AT CAF 0` yields (e.g. VW MEB's 17FE007B).
                hexTokens = Array(tokens.dropFirst())
                ecuKey = first.uppercased()
            }

            guard !hexTokens.isEmpty else { continue }

            let firstByteStr = hexTokens[0]
            // Non-hex lines are adapter chatter ("NO DATA", "CAN ERROR", "?") — never payload.
            guard let firstByte = UInt8(firstByteStr, radix: 16) else { continue }

            let frameType = (firstByte & 0xF0) >> 4

            if buckets[ecuKey] == nil {
                buckets[ecuKey] = Bucket()
                order.append(ecuKey)
            }

            switch frameType {
            case 0: // Single Frame (0x0N length)
                let length = Int(firstByte & 0x0F)
                if length > 0, hexTokens.count >= 1 + length {
                    let dataBytes = hexTokens[1...(length)]
                    buckets[ecuKey]!.payloadHex += dataBytes.joined()
                } else {
                    buckets[ecuKey]!.payloadHex += hexTokens.dropFirst().joined()
                }

            case 1: // First Frame (0x1N NN) — 12-bit total message length
                guard hexTokens.count >= 2, let lowLength = UInt8(hexTokens[1], radix: 16) else { continue }
                let totalLength = (Int(firstByte & 0x0F) << 8) | Int(lowLength)
                buckets[ecuKey]!.multiFrameStart = buckets[ecuKey]!.payloadHex.count
                buckets[ecuKey]!.multiFrameHexLength = totalLength * 2
                buckets[ecuKey]!.expectedSeq = 1
                buckets[ecuKey]!.payloadHex += hexTokens.dropFirst(2).joined()

            case 2: // Consecutive Frame (0x2N sequence index)
                if let expected = buckets[ecuKey]!.expectedSeq {
                    guard Int(firstByte & 0x0F) == expected & 0x0F else {
                        buckets[ecuKey]!.isInvalid = true
                        continue
                    }
                    buckets[ecuKey]!.expectedSeq = expected + 1
                }
                buckets[ecuKey]!.payloadHex += hexTokens.dropFirst(1).joined()

            case 3: // Flow Control (0x30 CTS / 0x31 wait / 0x32 abort) — carries no payload
                continue

            default:
                buckets[ecuKey]!.payloadHex += hexTokens.joined()
            }
        }

        // Truncate the trailing padding the final consecutive frame pads out with,
        // using the length each First Frame declared, per bucket.
        for key in buckets.keys {
            guard let start = buckets[key]!.multiFrameStart, let length = buckets[key]!.multiFrameHexLength,
                  buckets[key]!.payloadHex.count > start + length else { continue }
            buckets[key]!.payloadHex = String(buckets[key]!.payloadHex.prefix(start + length))
        }

        return order.compactMap { key -> (ecu: String, payload: String)? in
            guard let bucket = buckets[key], !bucket.isInvalid, !bucket.payloadHex.isEmpty else { return nil }
            return (ecu: key, payload: bucket.payloadHex)
        }
    }
}

extension String {
    /// Locates `marker` in this (already ISO-TP-assembled) hex string and returns every
    /// whole byte after it. A trailing odd hex digit (shouldn't normally occur) is dropped
    /// rather than treated as an error. Shared by every `VehicleProfile`'s decoder so byte
    /// extraction isn't reimplemented per profile.
    func hexBytes(after marker: String) -> [UInt8]? {
        guard let range = range(of: marker) else { return nil }
        let suffix = self[range.upperBound...]
        let evenCount = suffix.count - suffix.count % 2
        guard evenCount > 0 else { return [] }
        return stride(from: 0, to: evenCount, by: 2).compactMap {
            UInt8(suffix.dropFirst($0).prefix(2), radix: 16)
        }
    }

    /// Same as `hexBytes(after:)`, but requires (and returns) at least `count` bytes.
    func hexBytes(after marker: String, count: Int) -> [UInt8]? {
        guard let bytes = hexBytes(after: marker), bytes.count >= count else { return nil }
        return Array(bytes.prefix(count))
    }

    /// Single-byte convenience for `hexBytes(after:count:)`.
    func hexByte(after marker: String) -> UInt8? {
        hexBytes(after: marker, count: 1)?.first
    }
}
