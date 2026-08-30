const std = @import("std");

pub const Target = enum {
    bsv_mainnet,
    bsv_testnet,
    btc_strict,
};

pub const Era = enum {
    satoshi,
    bip,
    bch,
    bsv_pre_genesis,
    genesis,
    chronicle,

    pub fn fromString(s: []const u8) ?Era {
        inline for (@typeInfo(Era).@"enum".fields) |f| {
            if (std.mem.eql(u8, s, f.name)) return @enumFromInt(f.value);
        }
        return null;
    }
};

pub const Network = enum {
    btc_mainnet,
    btc_testnet,
    bch_mainnet,
    bch_testnet,
    bsv_mainnet,
    bsv_testnet,
    bsv_regtest,

    pub fn fromString(s: []const u8) ?Network {
        inline for (@typeInfo(Network).@"enum".fields) |f| {
            if (std.mem.eql(u8, s, f.name)) return @enumFromInt(f.value);
        }
        return null;
    }

    pub fn fromTarget(t: Target) Network {
        return switch (t) {
            .bsv_mainnet => .bsv_mainnet,
            .bsv_testnet => .bsv_testnet,
            .btc_strict => .btc_mainnet,
        };
    }

    pub fn isBsv(self: Network) bool {
        return switch (self) {
            .bsv_mainnet, .bsv_testnet, .bsv_regtest => true,
            else => false,
        };
    }

    pub fn isBtc(self: Network) bool {
        return switch (self) {
            .btc_mainnet, .btc_testnet => true,
            else => false,
        };
    }

    pub fn isBch(self: Network) bool {
        return switch (self) {
            .bch_mainnet, .bch_testnet => true,
            else => false,
        };
    }
};

pub const era_bounds = [_]struct { era: Era, start: u32 }{
    .{ .era = .satoshi, .start = 0 },
    .{ .era = .bip, .start = 173_805 },
    .{ .era = .bch, .start = 478_558 },
    .{ .era = .bsv_pre_genesis, .start = 556_767 },
    .{ .era = .genesis, .start = 620_538 },
    .{ .era = .chronicle, .start = 943_816 },
};

pub const chronicle_activation_height: u32 = 943_816;

pub fn eraFromBlockHeight(height: u32) Era {
    var result: Era = .satoshi;
    for (era_bounds) |b| {
        if (height >= b.start) result = b.era;
    }
    return result;
}

pub fn defaultEraForNetwork(network: Network) Era {
    return switch (network) {
        .bsv_mainnet, .bsv_testnet, .bsv_regtest => .genesis,
        .btc_mainnet, .btc_testnet => .bip,
        .bch_mainnet, .bch_testnet => .bch,
    };
}

pub const LimitSet = struct {
    push: u32 = 520,
    script: u32 = 10_000,
    opcodes: u32 = 1_000_000,
    stack: u16 = 1_000,
};

pub const LimitKind = enum {
    push,
    script,
    opcodes,
    stack,

    pub fn fromString(s: []const u8) ?LimitKind {
        inline for (@typeInfo(LimitKind).@"enum".fields) |f| {
            if (std.mem.eql(u8, s, f.name)) return @enumFromInt(f.value);
        }
        return null;
    }
};

pub const FeatureSet = packed struct {
    era_satoshi: bool = false,
    era_bip: bool = false,
    era_bch: bool = false,
    era_bsv_pre_genesis: bool = false,
    era_genesis: bool = false,
    era_chronicle: bool = false,

    cat: bool = false,
    split: bool = false,
    and_op: bool = false,
    or_op: bool = false,
    xor_op: bool = false,
    div: bool = false,
    mod: bool = false,
    num2bin: bool = false,
    bin2num: bool = false,

    mul: bool = false,
    invert: bool = false,
    lshift: bool = false,
    rshift: bool = false,
    lshiftnum: bool = false,
    rshiftnum: bool = false,

    cltv: bool = false,
    csv: bool = false,
    p2sh: bool = false,
    dersig: bool = false,
    otda: bool = false,
    codesep_sigsig: bool = false,
    bigpush: bool = false,
    bigscript: bool = false,
    malleability_fixes: bool = false,

    forkid: bool = false,
    low_s: bool = false,
    nulldummy: bool = false,
    sigpushonly: bool = false,
    cleanstack: bool = false,
    minimaldata: bool = false,
    minimalif: bool = false,

    bsv: bool = false,
    btc_strict: bool = false,

    pub fn unionWith(self: FeatureSet, other: FeatureSet) FeatureSet {
        var out = self;
        inline for (@typeInfo(FeatureSet).@"struct".fields) |f| {
            if (@field(other, f.name)) @field(out, f.name) = true;
        }
        return out;
    }

    pub fn has(self: FeatureSet, comptime name: []const u8) bool {
        return @field(self, name);
    }

    pub fn hasByName(self: *const FeatureSet, name: []const u8) bool {
        inline for (@typeInfo(FeatureSet).@"struct".fields) |f| {
            if (std.mem.eql(u8, name, f.name)) return @field(self, f.name);
        }
        return false;
    }

    pub fn isKnownFeature(name: []const u8) bool {
        inline for (@typeInfo(FeatureSet).@"struct".fields) |f| {
            if (std.mem.eql(u8, name, f.name)) return true;
        }
        return false;
    }
};

pub fn featuresForEra(era: Era) FeatureSet {
    var f = FeatureSet{};
    switch (era) {
        .satoshi => {
            f.era_satoshi = true;
        },
        .bip => {
            f.era_bip = true;
            f.dersig = true;
            f.p2sh = true;
            f.malleability_fixes = true;
            f.low_s = true;
            f.nulldummy = true;
            f.cleanstack = true;
            f.minimaldata = true;
            f.minimalif = true;
        },
        .bch => {
            f.era_bch = true;
            f.dersig = true;
            f.p2sh = true;
            f.malleability_fixes = true;
            f.low_s = true;
            f.nulldummy = true;
            f.cleanstack = true;
            f.minimaldata = true;
            f.minimalif = true;
            f.cat = true;
            f.split = true;
            f.and_op = true;
            f.or_op = true;
            f.xor_op = true;
            f.div = true;
            f.mod = true;
            f.num2bin = true;
            f.bin2num = true;
            f.forkid = true;
        },
        .bsv_pre_genesis => {
            f.era_bsv_pre_genesis = true;
            f.dersig = true;
            f.p2sh = true;
            f.malleability_fixes = true;
            f.low_s = true;
            f.nulldummy = true;
            f.cleanstack = true;
            f.minimaldata = true;
            f.minimalif = true;
            f.cat = true;
            f.split = true;
            f.and_op = true;
            f.or_op = true;
            f.xor_op = true;
            f.div = true;
            f.mod = true;
            f.num2bin = true;
            f.bin2num = true;
            f.forkid = true;
            f.cltv = true;
            f.csv = true;
        },
        .genesis => {
            f.era_genesis = true;
            f.dersig = true;
            f.low_s = true;
            f.nulldummy = true;
            f.cleanstack = true;
            f.minimaldata = true;
            f.minimalif = true;
            f.cat = true;
            f.split = true;
            f.and_op = true;
            f.or_op = true;
            f.xor_op = true;
            f.div = true;
            f.mod = true;
            f.num2bin = true;
            f.bin2num = true;
            f.forkid = true;
            f.mul = true;
            f.invert = true;
            f.lshift = true;
            f.rshift = true;
            f.bigpush = true;
            f.sigpushonly = true;
        },
        .chronicle => {
            f.era_chronicle = true;
            f.dersig = true;
            f.low_s = true;
            f.nulldummy = true;
            f.cleanstack = true;
            f.minimaldata = true;
            f.minimalif = true;
            f.cat = true;
            f.split = true;
            f.and_op = true;
            f.or_op = true;
            f.xor_op = true;
            f.div = true;
            f.mod = true;
            f.num2bin = true;
            f.bin2num = true;
            f.forkid = true;
            f.mul = true;
            f.invert = true;
            f.lshift = true;
            f.rshift = true;
            f.bigpush = true;
            f.sigpushonly = true;
            f.lshiftnum = true;
            f.rshiftnum = true;
            f.otda = true;
            f.codesep_sigsig = true;
            f.bigscript = true;
        },
    }
    return f;
}

pub const StandardnessFlags = packed struct {
    dersig: bool = true,
    low_s: bool = true,
    forkid: bool = true,
    cleanstack: bool = true,
    nulldummy: bool = true,
    sigpushonly: bool = true,
    minimaldata: bool = true,
    minimalif: bool = true,

    pub fn hasByName(self: *const StandardnessFlags, name: []const u8) bool {
        inline for (@typeInfo(StandardnessFlags).@"struct".fields) |f| {
            if (std.mem.eql(u8, name, f.name)) return @field(self, f.name);
        }
        return false;
    }

    pub fn isKnownFlag(name: []const u8) bool {
        inline for (@typeInfo(StandardnessFlags).@"struct".fields) |f| {
            if (std.mem.eql(u8, name, f.name)) return true;
        }
        return false;
    }
};

pub const CompileOptions = struct {
    target: Target = .bsv_mainnet,
    network: ?Network = null,
    era: ?Era = null,
    block_height: ?u32 = null,
    protocol_version: u32 = 1,
    tx_version: u32 = 1,
    features: FeatureSet = .{},
    standardness: StandardnessFlags = .{},
    limits: LimitSet = .{},
    enforce_standardness: bool = true,
    max_script_size: u32 = 10_000,
    max_stack_elements: u16 = 1_000,
    max_push_size: u16 = 520,
    emit_asm: bool = false,

    pub fn effectiveNetwork(self: CompileOptions) Network {
        if (self.network) |n| return n;
        return Network.fromTarget(self.target);
    }

    pub fn effectiveEra(self: CompileOptions) Era {
        if (self.era) |e| return e;
        if (self.block_height) |h| return eraFromBlockHeight(h);
        return defaultEraForNetwork(self.effectiveNetwork());
    }

    pub fn effectiveFeatures(self: CompileOptions) FeatureSet {
        var f = self.features;
        const era = self.effectiveEra();
        f = f.unionWith(featuresForEra(era));
        const network = self.effectiveNetwork();
        if (network.isBsv()) f.bsv = true;
        if (network.isBtc()) f.btc_strict = true;
        return f;
    }

    pub fn effectiveLimits(self: CompileOptions) LimitSet {
        var l = self.limits;
        if (self.max_script_size != 10_000) l.script = self.max_script_size;
        if (self.max_stack_elements != 1_000) l.stack = self.max_stack_elements;
        if (self.max_push_size != 520) l.push = self.max_push_size;
        return l;
    }
};

pub fn eraFromString(s: []const u8) ?Era {
    return Era.fromString(s);
}

pub fn networkFromString(s: []const u8) ?Network {
    return Network.fromString(s);
}

test "options: era boundaries" {
    try std.testing.expectEqual(Era.satoshi, eraFromBlockHeight(0));
    try std.testing.expectEqual(Era.satoshi, eraFromBlockHeight(173_804));
    try std.testing.expectEqual(Era.bip, eraFromBlockHeight(173_805));
    try std.testing.expectEqual(Era.bip, eraFromBlockHeight(478_557));
    try std.testing.expectEqual(Era.bch, eraFromBlockHeight(478_558));
    try std.testing.expectEqual(Era.bch, eraFromBlockHeight(556_766));
    try std.testing.expectEqual(Era.bsv_pre_genesis, eraFromBlockHeight(556_767));
    try std.testing.expectEqual(Era.bsv_pre_genesis, eraFromBlockHeight(620_537));
    try std.testing.expectEqual(Era.genesis, eraFromBlockHeight(620_538));
    try std.testing.expectEqual(Era.genesis, eraFromBlockHeight(943_815));
    try std.testing.expectEqual(Era.chronicle, eraFromBlockHeight(943_816));
    try std.testing.expectEqual(Era.chronicle, eraFromBlockHeight(1_000_000));
}

test "options: era features" {
    const chronicle = featuresForEra(.chronicle);
    try std.testing.expect(chronicle.lshiftnum);
    try std.testing.expect(chronicle.bigscript);
    try std.testing.expect(chronicle.otda);
    try std.testing.expect(!chronicle.cltv);
    try std.testing.expect(!chronicle.p2sh);
    try std.testing.expect(!chronicle.malleability_fixes);

    const genesis = featuresForEra(.genesis);
    try std.testing.expect(genesis.mul);
    try std.testing.expect(!genesis.cltv);

    const bip = featuresForEra(.bip);
    try std.testing.expect(bip.p2sh);
    try std.testing.expect(bip.dersig);
    try std.testing.expect(!bip.cat);
}

test "options: effective layers" {
    const opts = CompileOptions{ .network = .bsv_mainnet, .block_height = 943_816 };
    try std.testing.expectEqual(Era.chronicle, opts.effectiveEra());
    const feats = opts.effectiveFeatures();
    try std.testing.expect(feats.bsv);
    try std.testing.expect(feats.era_chronicle);

    const legacy = CompileOptions{ .target = .btc_strict };
    try std.testing.expectEqual(Network.btc_mainnet, legacy.effectiveNetwork());
    try std.testing.expect(legacy.effectiveFeatures().btc_strict);

    const manual = CompileOptions{ .era = .bch };
    try std.testing.expectEqual(Era.bch, manual.effectiveEra());
    try std.testing.expect(manual.effectiveFeatures().cat);
}

test "options: legacy limit fields map to limits" {
    const opts = CompileOptions{ .max_script_size = 2, .max_push_size = 100 };
    const l = opts.effectiveLimits();
    try std.testing.expectEqual(@as(u32, 2), l.script);
    try std.testing.expectEqual(@as(u32, 100), l.push);
    try std.testing.expectEqual(@as(u16, 1_000), l.stack);
}

test "options: string lookups" {
    try std.testing.expectEqual(Era.chronicle, Era.fromString("chronicle"));
    try std.testing.expectEqual(@as(?Era, null), Era.fromString("nope"));
    try std.testing.expectEqual(Network.bsv_regtest, Network.fromString("bsv_regtest"));
    try std.testing.expect(FeatureSet.isKnownFeature("lshiftnum"));
    try std.testing.expect(!FeatureSet.isKnownFeature("nonexistent"));
    try std.testing.expect(StandardnessFlags.isKnownFlag("cleanstack"));
    try std.testing.expect(!StandardnessFlags.isKnownFlag("nonexistent"));
}
