pub const ParseError = error{
    UnexpectedToken,
    ArityMismatch,
    InvalidLoopBound,
    ReservedKeyword,
    EmptyBody,
    InvalidCondition,
    OutOfMemory,
};
