const std = @import("std");
const AstNode = @import("../parser/ast.zig").AstNode;
const ExpandError = @import("error.zig").ExpandError;

pub const ParamType = enum {
    integer,
    string,
    opcode,
    block,
};

pub const MacroDefinition = struct {
    arity: u8,
    param_types: []const ParamType,
    expand_fn: *const fn (
        allocator: std.mem.Allocator,
        args: []const AstNode,
        body: ?[]const AstNode,
        table: *const MacroTable,
    ) ExpandError![]const u8,
};

pub const MacroTable = struct {
    entries: std.StringHashMap(MacroDefinition),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MacroTable {
        return .{
            .entries = std.StringHashMap(MacroDefinition).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MacroTable) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.param_types);
        }
        self.entries.deinit();
    }

    pub fn register(
        self: *MacroTable,
        name: []const u8,
        definition: MacroDefinition,
    ) !void {
        // If a macro with this name is already registered, free its old
        // name and param_types before installing the new one.
        if (self.entries.fetchRemove(name)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value.param_types);
        }
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const owned_types = try self.allocator.dupe(ParamType, definition.param_types);
        errdefer self.allocator.free(owned_types);
        try self.entries.put(owned_name, .{
            .arity = definition.arity,
            .param_types = owned_types,
            .expand_fn = definition.expand_fn,
        });
    }

    pub fn lookup(self: *const MacroTable, name: []const u8) ?MacroDefinition {
        return self.entries.get(name);
    }
};
