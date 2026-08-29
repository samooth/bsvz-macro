const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // bsvz dependency (exposes module "bsvz")
    const bsvz_dep = b.dependency("bsvz", .{
        .target = target,
        .optimize = optimize,
    });
    const bsvz_mod = bsvz_dep.module("bsvz");

    // zig-wallet-toolbox dependency (does NOT expose a module, create manually)
    const wallet_dep = b.dependency("zig_wallet_toolbox", .{
        .target = target,
        .optimize = optimize,
    });
    const wallet_mod = b.createModule(.{
        .root_source_file = wallet_dep.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    wallet_mod.addImport("bsvz", bsvz_mod);

    // Main library module
    const macro_mod = b.addModule("bsvz-macro", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    macro_mod.addImport("bsvz", bsvz_mod);
    macro_mod.addImport("zig-wallet-toolbox", wallet_mod);

    // Static library artifact
    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_module.addImport("bsvz", bsvz_mod);
    lib_module.addImport("zig-wallet-toolbox", wallet_mod);
    const lib = b.addLibrary(.{
        .name = "bsvz-macro",
        .root_module = lib_module,
        .linkage = .static,
    });
    b.installArtifact(lib);

    // WASM artifact for the web. The module graph intentionally excludes
    // zig-wallet-toolbox (never imported by the macro compiler); only bsvz
    // is imported. Built as a no-entry executable so the module owns its
    // memory (no env imports, browser-friendly).
    const wasm_step = b.step("wasm", "Build the wasm32 module for web usage");
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_optimize = b.option(std.builtin.OptimizeMode, "wasm-optimize", "Optimize mode for the wasm artifact (default: ReleaseSmall)") orelse .ReleaseSmall;
    const wasm_strip = b.option(bool, "wasm-strip", "Strip debug info from the wasm artifact (default: true)") orelse true;
    const wasm_module = b.createModule(.{
        .root_source_file = b.path("src/wasm.zig"),
        .target = wasm_target,
        .optimize = wasm_optimize,
        .strip = wasm_strip,
    });
    wasm_module.addImport("bsvz-macro", macro_mod);
    const wasm_lib = b.addExecutable(.{
        .name = "bsvz_macro",
        .root_module = wasm_module,
    });
    wasm_lib.entry = .disabled;
    wasm_lib.rdynamic = true;
    const wasm_install = b.addInstallArtifact(wasm_lib, .{
        .dest_dir = .{ .override = .{ .custom = "wasm" } },
    });
    wasm_step.dependOn(&wasm_install.step);

// Tests
     const test_step = b.step("test", "Run all tests");

     const main_tests = b.addTest(.{
         .root_module = macro_mod,
     });
     const run_main_tests = b.addRunArtifact(main_tests);
     test_step.dependOn(&run_main_tests.step);

     // E2E tests
     const e2e_test_module = b.createModule(.{
         .root_source_file = b.path("tests/macro_e2e.zig"),
         .target = target,
         .optimize = optimize,
     });
     e2e_test_module.addImport("bsvz-macro", macro_mod);
     e2e_test_module.addImport("bsvz", bsvz_mod);
     const e2e_tests = b.addTest(.{
         .root_module = e2e_test_module,
     });
     const run_e2e_tests = b.addRunArtifact(e2e_tests);
     test_step.dependOn(&run_e2e_tests.step);

     // Canonical tests
     const canon_test_module = b.createModule(.{
         .root_source_file = b.path("tests/canonical.zig"),
         .target = target,
         .optimize = optimize,
     });
     canon_test_module.addImport("bsvz-macro", macro_mod);
     canon_test_module.addImport("bsvz", bsvz_mod);
     const canon_tests = b.addTest(.{
         .root_module = canon_test_module,
     });
     const run_canon_tests = b.addRunArtifact(canon_tests);
     test_step.dependOn(&run_canon_tests.step);

     // Stack sim tests
     const sim_test_module = b.createModule(.{
         .root_source_file = b.path("tests/stack_sim.zig"),
         .target = target,
         .optimize = optimize,
     });
     sim_test_module.addImport("bsvz-macro", macro_mod);
     sim_test_module.addImport("bsvz", bsvz_mod);
     const sim_tests = b.addTest(.{
         .root_module = sim_test_module,
     });
     const run_sim_tests = b.addRunArtifact(sim_tests);
     test_step.dependOn(&run_sim_tests.step);

     // Negative tests
     const neg_test_module = b.createModule(.{
         .root_source_file = b.path("tests/negative_tests.zig"),
         .target = target,
         .optimize = optimize,
     });
     neg_test_module.addImport("bsvz-macro", macro_mod);
     neg_test_module.addImport("bsvz", bsvz_mod);
     const neg_tests = b.addTest(.{
         .root_module = neg_test_module,
     });
     const run_neg_tests = b.addRunArtifact(neg_tests);
     test_step.dependOn(&run_neg_tests.step);

     // Validator tests
     const val_test_module = b.createModule(.{
         .root_source_file = b.path("tests/validator_tests.zig"),
         .target = target,
         .optimize = optimize,
     });
     val_test_module.addImport("bsvz-macro", macro_mod);
     val_test_module.addImport("bsvz", bsvz_mod);
     const val_tests = b.addTest(.{
         .root_module = val_test_module,
     });
     const run_val_tests = b.addRunArtifact(val_tests);
     test_step.dependOn(&run_val_tests.step);

     // Simulator tests
     const sim2_test_module = b.createModule(.{
         .root_source_file = b.path("tests/simulator_tests.zig"),
         .target = target,
         .optimize = optimize,
     });
     sim2_test_module.addImport("bsvz-macro", macro_mod);
     sim2_test_module.addImport("bsvz", bsvz_mod);
     const sim2_tests = b.addTest(.{
         .root_module = sim2_test_module,
     });
     const run_sim2_tests = b.addRunArtifact(sim2_tests);
     test_step.dependOn(&run_sim2_tests.step);

     // Expander tests
     const exp_test_module = b.createModule(.{
         .root_source_file = b.path("tests/expander_tests.zig"),
         .target = target,
         .optimize = optimize,
     });
     exp_test_module.addImport("bsvz-macro", macro_mod);
     exp_test_module.addImport("bsvz", bsvz_mod);
     const exp_tests = b.addTest(.{
         .root_module = exp_test_module,
     });
     const run_exp_tests = b.addRunArtifact(exp_tests);
     test_step.dependOn(&run_exp_tests.step);

     // Lexer tests
     const lex_test_module = b.createModule(.{
         .root_source_file = b.path("tests/lexer_tests.zig"),
         .target = target,
         .optimize = optimize,
     });
     lex_test_module.addImport("bsvz-macro", macro_mod);
     lex_test_module.addImport("bsvz", bsvz_mod);
     const lex_tests = b.addTest(.{
         .root_module = lex_test_module,
     });
     const run_lex_tests = b.addRunArtifact(lex_tests);
     test_step.dependOn(&run_lex_tests.step);

     // Parser tests
     const parse_test_module = b.createModule(.{
         .root_source_file = b.path("tests/parser_tests.zig"),
         .target = target,
         .optimize = optimize,
     });
     parse_test_module.addImport("bsvz-macro", macro_mod);
     parse_test_module.addImport("bsvz", bsvz_mod);
     const parse_tests = b.addTest(.{
         .root_module = parse_test_module,
     });
     const run_parse_tests = b.addRunArtifact(parse_tests);
     test_step.dependOn(&run_parse_tests.step);

     // Test helpers (contains tests for the helpers themselves)
     const helpers_test_module = b.createModule(.{
         .root_source_file = b.path("tests/helpers.zig"),
         .target = target,
         .optimize = optimize,
     });
     helpers_test_module.addImport("bsvz-macro", macro_mod);
     helpers_test_module.addImport("bsvz", bsvz_mod);
     const helpers_tests = b.addTest(.{
         .root_module = helpers_test_module,
     });
     const run_helpers_tests = b.addRunArtifact(helpers_tests);
     test_step.dependOn(&run_helpers_tests.step);

     // Test data builders (contains tests for the builders)
     const test_data_test_module = b.createModule(.{
         .root_source_file = b.path("tests/test_data.zig"),
         .target = target,
         .optimize = optimize,
     });
     test_data_test_module.addImport("bsvz-macro", macro_mod);
     test_data_test_module.addImport("bsvz", bsvz_mod);
     const test_data_tests = b.addTest(.{
         .root_module = test_data_test_module,
     });
     const run_test_data_tests = b.addRunArtifact(test_data_tests);
     test_step.dependOn(&run_test_data_tests.step);

     // Property-based tests
     const prop_test_module = b.createModule(.{
         .root_source_file = b.path("tests/property_tests.zig"),
         .target = target,
         .optimize = optimize,
     });
     prop_test_module.addImport("bsvz-macro", macro_mod);
     prop_test_module.addImport("bsvz", bsvz_mod);
     const prop_tests = b.addTest(.{
         .root_module = prop_test_module,
     });
     const run_prop_tests = b.addRunArtifact(prop_tests);
     test_step.dependOn(&run_prop_tests.step);

     // Benchmark tests
     const bench_test_module = b.createModule(.{
         .root_source_file = b.path("tests/benchmark_tests.zig"),
         .target = target,
         .optimize = optimize,
     });
     bench_test_module.addImport("bsvz-macro", macro_mod);
     bench_test_module.addImport("bsvz", bsvz_mod);
     const bench_tests = b.addTest(.{
         .root_module = bench_test_module,
     });
     const run_bench_tests = b.addRunArtifact(bench_tests);
     test_step.dependOn(&run_bench_tests.step);

     // Example tests using helpers (demonstrates helper value)
     const examples_test_module = b.createModule(.{
         .root_source_file = b.path("tests/examples_tests.zig"),
         .target = target,
         .optimize = optimize,
     });
     examples_test_module.addImport("bsvz-macro", macro_mod);
     examples_test_module.addImport("bsvz", bsvz_mod);
     const examples_tests = b.addTest(.{
         .root_module = examples_test_module,
     });
     const run_examples_tests = b.addRunArtifact(examples_tests);
     test_step.dependOn(&run_examples_tests.step);
}
