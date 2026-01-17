import Foundation

struct BeadsParser {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(data: Data) throws -> [Issue] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw BeadsParserError.invalidEncoding
        }

        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var issues: [Issue] = []

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            if let date = dateFormatter.date(from: dateString) {
                return date
            }
            if let date = fallbackDateFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }

        for line in lines {
            guard let lineData = line.data(using: .utf8) else { continue }

            do {
                let issue = try decoder.decode(Issue.self, from: lineData)
                issues.append(issue)
            } catch {
                // Skip malformed lines
                print("Failed to parse issue: \(error)")
            }
        }

        return issues
    }

    static func serialize(issues: [Issue]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [] // Compact, single line per issue

        var lines: [String] = []

        for issue in issues {
            let data = try encoder.encode(issue)
            if let jsonString = String(data: data, encoding: .utf8) {
                lines.append(jsonString)
            }
        }

        let content = lines.joined(separator: "\n")
        guard let data = content.data(using: .utf8) else {
            throw BeadsParserError.serializationFailed
        }

        return data
    }
}

enum BeadsParserError: LocalizedError {
    case invalidEncoding
    case serializationFailed

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Invalid file encoding"
        case .serializationFailed:
            return "Failed to serialize issues"
        }
    }
}
