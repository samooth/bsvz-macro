pub const ExpandError = error{
    UnboundMacro,
    ArityMismatch,
    TypeMismatch,
    Overflow,
    LoopBoundTooLarge,
    MacroRecursionDepthExceeded,
    InvalidOpcodeInExpansion,
    OutOfMemory,
};
