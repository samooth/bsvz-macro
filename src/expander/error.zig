pub const ExpandError = error{
    UnboundMacro,
    ArityMismatch,
    TypeMismatch,
    Overflow,
    LoopBoundTooLarge,
    MacroRecursionDepthExceeded,
    InvalidOpcodeInExpansion,
    CompileError,
    OutOfMemory,
};
