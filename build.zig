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
}
