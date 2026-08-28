pub const LexError = error{
    UnrecognizedToken,
    InvalidLiteral,
    InvalidHexLiteral,
    IntegerOverflow,
    UnclosedBlock,
    UnclosedString,
    UnclosedComment,
    IteratorOutsideLoop,
};
