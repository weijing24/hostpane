import Foundation

public enum DashboardBackground: String, Codable, CaseIterable, Sendable, Identifiable {
    case plain
    case sunrise
    case sunset
    case love
    case ocean
    case barbie
    case starry
    case jelly
    case lavandula
    case watermelon
    case dandelion
    case lemon
    case spring
    case summer
    case autumn
    case winter
    case neon
    case aurora
    case ai
    case colorful

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plain: return "普通"
        case .sunrise: return "Sunrise"
        case .sunset: return "Sunset"
        case .love: return "Love"
        case .ocean: return "Ocean"
        case .barbie: return "Barbie"
        case .starry: return "Starry"
        case .jelly: return "Jelly"
        case .lavandula: return "Lavandula"
        case .watermelon: return "Watermelon"
        case .dandelion: return "Dandelion"
        case .lemon: return "Lemon"
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .autumn: return "Autumn"
        case .winter: return "Winter"
        case .neon: return "Neon"
        case .aurora: return "Aurora"
        case .ai: return "AI"
        case .colorful: return "Colorful"
        }
    }
}

public enum StatusCardKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case cpu
    case load
    case processes
    case memory
    case network
    case storage
    case docker

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: return "CPU 利用率"
        case .load: return "CPU 负载"
        case .processes: return "进程"
        case .memory: return "内存利用"
        case .network: return "网络使用情况"
        case .storage: return "存储"
        case .docker: return "Docker"
        }
    }
}

public struct StatusCardPlacement: Codable, Equatable, Sendable, Identifiable {
    public var kind: StatusCardKind
    public var column: Int
    public var width: Int
    public var height: Int

    public static let maxHeight = 3

    public var id: StatusCardKind { kind }

    public init(kind: StatusCardKind, column: Int, width: Int, height: Int) {
        self.kind = kind
        self.column = column
        self.width = width
        self.height = height
    }
}

public struct StatusDetailLayout: Codable, Equatable, Sendable {
    public var columns: Int
    public var cards: [StatusCardPlacement]

    public init(columns: Int, cards: [StatusCardPlacement]) {
        self.columns = columns
        self.cards = cards
    }

    public static let `default` = StatusDetailLayout(
        columns: 2,
        cards: [
            StatusCardPlacement(kind: .cpu, column: 0, width: 2, height: 1),
            StatusCardPlacement(kind: .load, column: 0, width: 1, height: 1),
            StatusCardPlacement(kind: .processes, column: 1, width: 1, height: 2),
            StatusCardPlacement(kind: .memory, column: 0, width: 1, height: 1),
            StatusCardPlacement(kind: .network, column: 0, width: 2, height: 1),
            StatusCardPlacement(kind: .storage, column: 0, width: 2, height: 1),
            StatusCardPlacement(kind: .docker, column: 0, width: 2, height: 1)
        ]
    )

    public func normalized() -> StatusDetailLayout {
        let columns = min(max(self.columns, 1), 4)
        var seen = Set<StatusCardKind>()
        var cards: [StatusCardPlacement] = []
        for card in self.cards {
            guard seen.insert(card.kind).inserted else { continue }
            let width = min(max(card.width, 1), columns)
            let column = min(max(card.column, 0), columns - width)
            let height = min(max(card.height, 1), StatusCardPlacement.maxHeight)
            cards.append(StatusCardPlacement(kind: card.kind, column: column, width: width, height: height))
        }
        return StatusDetailLayout(columns: columns, cards: cards)
    }

    public var missingKinds: [StatusCardKind] {
        let present = Set(normalized().cards.map(\.kind))
        return StatusCardKind.allCases.filter { !present.contains($0) }
    }

    public mutating func add(_ kind: StatusCardKind) {
        guard !cards.contains(where: { $0.kind == kind }) else { return }
        cards.append(StatusCardPlacement(kind: kind, column: 0, width: 1, height: 1))
        self = normalized()
    }

    public mutating func remove(_ kind: StatusCardKind) {
        cards.removeAll { $0.kind == kind }
        self = normalized()
    }
}

public struct StatusGridSlot: Equatable, Sendable, Identifiable {
    public var kind: StatusCardKind
    public var column: Int
    public var row: Int
    public var width: Int
    public var height: Int

    public var id: StatusCardKind { kind }
}

public enum StatusLayoutGrid {
    /// Places each card at its column, on the first row where the span fits.
    /// A card with height > 1 occupies the rows beneath it so the next card
    /// can sit beside that span.
    public static func slots(for layout: StatusDetailLayout) -> [StatusGridSlot] {
        let layout = layout.normalized()
        let columns = layout.columns
        var occupied = Set<Int>()
        func key(_ column: Int, _ row: Int) -> Int { row * columns + column }

        func fits(_ column: Int, _ row: Int, _ width: Int, _ height: Int) -> Bool {
            for rowOffset in 0..<height {
                for columnOffset in 0..<width {
                    if occupied.contains(key(column + columnOffset, row + rowOffset)) {
                        return false
                    }
                }
            }
            return true
        }

        var slots: [StatusGridSlot] = []
        for card in layout.cards {
            var row = 0
            while !fits(card.column, row, card.width, card.height) {
                row += 1
                if row > 64 { break }
            }
            for rowOffset in 0..<card.height {
                for columnOffset in 0..<card.width {
                    occupied.insert(key(card.column + columnOffset, row + rowOffset))
                }
            }
            slots.append(
                StatusGridSlot(
                    kind: card.kind,
                    column: card.column,
                    row: row,
                    width: card.width,
                    height: card.height
                )
            )
        }
        return slots.sorted { lhs, rhs in
            if lhs.row != rhs.row { return lhs.row < rhs.row }
            return lhs.column < rhs.column
        }
    }
}
