import Testing

/// `#expect` for floating point values that may differ by float noise. The source location is the caller's, so a failure
/// points at the test, and the message names both values.
func expectClose<T: BinaryFloatingPoint>(_ actual: T, _ expected: T, tolerance: T, sourceLocation: SourceLocation = #_sourceLocation) -> Void {
    #expect(abs(actual - expected) < tolerance, "\(actual) is not within \(tolerance) of \(expected)", sourceLocation: sourceLocation)
}
