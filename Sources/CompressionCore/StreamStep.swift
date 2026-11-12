/// Result of a streaming de/compression call. Tells the user what to do next.
public struct StreamStep: Sendable {
    public enum Status: Sendable {
        /// Everything passed in was used, and the stream hasn't ended.
        case awaitingInput
        /// `output` is full. Drain it and call again with the unconsumed input.
        case outputIsFull
        /// The end of the stream was reached.
        case finished
    }

    /// How many of the input's bytes were consumed in the step.
    public let consumed: Int
    /// What the result of the step was, for example
    /// whether we can continue feeding input or need to drain the output first.
    public let status: Status

    @usableFromInline
    package init(consumed: Int, status: StreamStep.Status) {
        self.consumed = consumed
        self.status = status
    }
}
