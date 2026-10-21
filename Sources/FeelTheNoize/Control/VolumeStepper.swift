/// Step math for Dial-driven volume changes (Docs/DESIGN.md §7.3).
enum VolumeStepper {
    // Absorbs float noise so that a volume read back as 0.37999997 still counts as on the 0.38 grid line.
    private static let epsilon = 0.0001

    /// Snaps the volume to the step grid in the direction of travel, so a level set elsewhere (e.g. 37 %) never
    /// produces an uneven first step, then moves by `detents` steps and clamps to 0...1.
    static func volume(from volume: Float32, detents: Int, step: Float32) -> Float32 {
        guard detents != 0, step > 0 else { return volume }
        let current = Double(volume)
        let size = Double(step)
        let gridIndex = detents > 0 ? ((current + epsilon) / size).rounded(.down) : ((current - epsilon) / size).rounded(.up)
        let result = (gridIndex + Double(detents)) * size
        return Float32(min(max(result, 0), 1))
    }
}
