const std = @import("std");

pub const StackType = union(enum) {
    unknown,
    bool,
    integer,
    bytes: u32,
    hash160,
    hash256,
    pubkey,
    signature,
};

pub const StackItem = struct {
    type: StackType,
    value: ?i64 = null,
};

pub const SymbolicStack = struct {
    items: std.ArrayList(StackItem),
    max_height: usize = 0,

    pub fn init(_: std.mem.Allocator) SymbolicStack {
        return .{
            .items = .empty,
        };
    }

    pub fn deinit(self: *SymbolicStack, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
    }

    pub fn push(self: *SymbolicStack, allocator: std.mem.Allocator, item: StackItem) !void {
        try self.items.append(allocator, item);
        if (self.items.items.len > self.max_height) {
            self.max_height = self.items.items.len;
        }
    }

    pub fn pop(self: *SymbolicStack) !StackItem {
        if (self.items.items.len == 0) return error.StackUnderflow;
        return self.items.pop() orelse return error.StackUnderflow;
    }

    pub fn peek(self: *SymbolicStack, depth: usize) !StackItem {
        if (depth >= self.items.items.len) return error.InvalidStackIndex;
        return self.items.items[self.items.items.len - 1 - depth];
    }

    pub fn dup(self: *SymbolicStack, allocator: std.mem.Allocator) !void {
        const top = try self.peek(0);
        try self.push(allocator, top);
    }

    pub fn swap(self: *SymbolicStack) !void {
        if (self.items.items.len < 2) return error.StackUnderflow;
        const last = self.items.items.len - 1;
        const tmp = self.items.items[last];
        self.items.items[last] = self.items.items[last - 1];
        self.items.items[last - 1] = tmp;
    }

    pub fn height(self: *SymbolicStack) usize {
        return self.items.items.len;
    }

    pub fn ensureDepth(self: *SymbolicStack, allocator: std.mem.Allocator, depth: usize) !void {
        const old_len = self.items.items.len;
        if (depth < old_len) return;
        const missing = depth + 1 - old_len;
        try self.items.ensureUnusedCapacity(allocator, missing);
        self.items.items.len = old_len + missing;
        std.mem.copyBackwards(
            StackItem,
            self.items.items[missing .. missing + old_len],
            self.items.items[0..old_len],
        );
        @memset(self.items.items[0..missing], .{ .type = StackType.integer });
        if (self.items.items.len > self.max_height) {
            self.max_height = self.items.items.len;
        }
    }

    pub fn removeAt(self: *SymbolicStack, _: std.mem.Allocator, depth: usize) !StackItem {
        if (depth >= self.items.items.len) return error.InvalidStackIndex;
        const idx = self.items.items.len - 1 - depth;
        const item = self.items.items[idx];
        for (idx..self.items.items.len - 1) |i| {
            self.items.items[i] = self.items.items[i + 1];
        }
        _ = self.items.pop();
        return item;
    }

    pub fn insertAt(self: *SymbolicStack, allocator: std.mem.Allocator, depth: usize, item: StackItem) !void {
        if (depth > self.items.items.len) return error.InvalidStackIndex;
        const idx = self.items.items.len - depth;
        try self.items.append(allocator, self.items.getLast());
        var i: usize = self.items.items.len - 1;
        while (i > idx) : (i -= 1) {
            self.items.items[i] = self.items.items[i - 1];
        }
        self.items.items[idx] = item;
        if (self.items.items.len > self.max_height) {
            self.max_height = self.items.items.len;
        }
    }
};
