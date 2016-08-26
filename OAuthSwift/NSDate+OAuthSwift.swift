import Foundation

extension Date: Comparable {}

public func == (lhs: Date, rhs: Date) -> Bool {
    return (lhs == rhs)
}

public func <= (lhs: Date, rhs: Date) -> Bool {
    return lhs < rhs || lhs == rhs
}

public func >= (lhs: Date, rhs: Date) -> Bool {
    return rhs <= lhs
}

public func < (lhs: Date, rhs: Date) -> Bool {
    return lhs.compare(rhs) == ComparisonResult.orderedAscending
}

public func > (lhs: Date, rhs: Date) -> Bool {
    return rhs < lhs
}
