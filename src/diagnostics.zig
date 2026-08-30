const std = @import("std");

pub const Phase = enum {
    lex,
    parse,
    expand,
    simulate,
    validate,
};

pub const Severity = enum {
    @"error",
    warning,
    note,
};

pub const SourceLocation = struct {
    line: u32,
    column: u32,
    offset: u32,
    length: u32,
};

pub const CompileDiagnostic = struct {
    phase: Phase,
    severity: Severity,
    message: []const u8,
    location: SourceLocation,
    suggestion: ?[]const u8 = null,

    pub fn deinit(self: *const CompileDiagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        if (self.suggestion) |s| allocator.free(s);
    }
};

pub const DiagnosticList = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged(CompileDiagnostic) = .empty,

    pub fn init(allocator: std.mem.Allocator) DiagnosticList {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *DiagnosticList) void {
        for (self.items.items) |*d| d.deinit(self.allocator);
        self.items.deinit(self.allocator);
    }

    pub fn append(
        self: *DiagnosticList,
        phase: Phase,
        severity: Severity,
        comptime fmt: []const u8,
        location: SourceLocation,
        args: anytype,
    ) void {
        const message = std.fmt.allocPrint(self.allocator, fmt, args) catch return;
        self.items.append(self.allocator, .{
            .phase = phase,
            .severity = severity,
            .message = message,
            .location = location,
        }) catch self.allocator.free(message);
    }

    pub fn len(self: *const DiagnosticList) usize {
        return self.items.items.len;
    }

    pub fn get(self: *const DiagnosticList, index: usize) ?CompileDiagnostic {
        if (index >= self.items.items.len) return null;
        return self.items.items[index];
    }
};

pub const unknown_location: SourceLocation = .{ .line = 0, .column = 0, .offset = 0, .length = 0 };
