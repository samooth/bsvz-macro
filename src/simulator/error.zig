pub const SimError = error{
    StackUnderflow,
    AltStackUnderflow,
    TypeMismatch,
    PushTooLarge,
    StackOverflow,
    InvalidStackIndex,
    DivisionByZero,
    VerifyFailed,
    InvalidOpcode,
    OutOfMemory,
};
