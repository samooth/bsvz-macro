pub const ValError = error{
    ScriptTooLarge,
    StackTooDeep,
    PushTooLarge,
    NonStandard,
    OutOfMemory,
};
