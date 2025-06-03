const std = @import("std");
const builtin = @import("builtin");
fn createEmsdkStep(b: *std.Build, emsdk: *std.Build.Dependency) *std.Build.Step.Run {
    if (builtin.os.tag == .windows) {
        return b.addSystemCommand(&.{emsdk.path("emsdk.bat").getPath(b)});
    } else {
        return b.addSystemCommand(&.{emsdk.path("emsdk").getPath(b)});
    }
}

const emccOutputDir = "zig-out" ++ std.fs.path.sep_str ++ "htmlout" ++ std.fs.path.sep_str;
const emccOutputFile = "index.html";
fn emSdkSetupStep(b: *std.Build, emsdk: *std.Build.Dependency) !?*std.Build.Step.Run {
    const dot_emsc_path = emsdk.path(".emscripten").getPath(b);
    const dot_emsc_exists = !std.meta.isError(std.fs.accessAbsolute(dot_emsc_path, .{}));

    if (!dot_emsc_exists) {
        const emsdk_install = createEmsdkStep(b, emsdk);
        emsdk_install.addArgs(&.{ "install", "latest" });
        const emsdk_activate = createEmsdkStep(b, emsdk);
        emsdk_activate.addArgs(&.{ "activate", "latest" });
        emsdk_activate.step.dependOn(&emsdk_install.step);
        return emsdk_activate;
    } else {
        return null;
    }
}
pub fn build(b: *std.Build) !void {
    var target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
 const enable_logging = b.option(bool, "logging", "Enable logging") orelse true;
    const enable_debug_logging = b.option(bool, "debug-logging", "Enable debug logging") orelse false;
   
    if (target.result.os.tag == .emscripten) {
        target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .cpu_model = .{ .explicit = &std.Target.wasm.cpu.mvp },
            .cpu_features_add = std.Target.wasm.featureSet(&.{
                .atomics,
                .bulk_memory,
            }),
            .os_tag = .emscripten,
        });
    }

    const libusb_deb = b.dependency("libusb", .{
        .target = target,
        .optimize = optimize,
        .logging = enable_logging,
        .@"debug-logging" = enable_debug_logging,
    });
    const wifidriver_dep = b.dependency("devourer", .{
        .target = target,
        .optimize = optimize,
    });

    const libusb = libusb_deb.artifact("usb-1.0");
    const wifidriver = wifidriver_dep.artifact("WiFiDriver");
    switch (target.result.os.tag) {
        .emscripten => {
            const lib = b.addStaticLibrary(.{
                .name = "lib",
                // .root_source_file = b.path("src/main.zig"),

                .target = b.resolveTargetQuery(.{
                    .cpu_arch = .wasm32,
                    .cpu_model = .{ .explicit = &std.Target.wasm.cpu.mvp },
                    .cpu_features_add = std.Target.wasm.featureSet(&.{
                        .atomics,
                        .bulk_memory,
                    }),
                    .os_tag = .emscripten,
                }),
                .link_libc = true,

                .optimize = optimize,
            });
            lib.linkLibrary(libusb);
            lib.linkLibrary(wifidriver);
            //lib.linkLibCpp();
            // Include emscripten for cross compilation
            if (b.lazyDependency("emsdk", .{})) |dep| {
                if (try emSdkSetupStep(b, dep)) |emSdkStep| {
                    lib.step.dependOn(&emSdkStep.step);
                }
                lib.addIncludePath(dep.path("upstream/emscripten/cache/sysroot/include/c++/v1"));
                lib.addIncludePath(dep.path("upstream/emscripten/cache/sysroot/include/compat"));
                lib.addIncludePath(dep.path("upstream/emscripten/cache/sysroot/include"));
                lib.addCSourceFile(.{ .file = b.path("src/wrapper.cpp"), .language = .cpp, .flags = &.{
                    "-std=gnu++20",
                } });
                const emccExe = switch (builtin.os.tag) {
                    .windows => "emcc.bat",
                    else => "emcc",
                };
                var emcc_run_arg = try b.allocator.alloc(
                    u8,
                    dep.path("upstream/emscripten").getPath(b).len + emccExe.len + 1,
                );
                defer b.allocator.free(emcc_run_arg);

                emcc_run_arg = try std.fmt.bufPrint(
                    emcc_run_arg,
                    "{s}" ++ std.fs.path.sep_str ++ "{s}",
                    .{ dep.path("upstream/emscripten").getPath(b), emccExe },
                );

                const mkdir_command = b.addSystemCommand(&[_][]const u8{
                    "mkdir",
                    "-p",
                    emccOutputDir,
                });
                const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_run_arg});
                emcc_command.addFileArg(lib.getEmittedBin());
                emcc_command.addFileArg(wifidriver.getEmittedBin());
                emcc_command.addFileArg(libusb.getEmittedBin());

                emcc_command.step.dependOn(&lib.step);
                emcc_command.step.dependOn(&mkdir_command.step);
                emcc_command.addArgs(&[_][]const u8{
                    "-o",
                    emccOutputDir ++ emccOutputFile,
                    "-pthread",
                    "-sASYNCIFY",
                    "-sALLOW_MEMORY_GROWTH=1", // Added =1 to explicitly enable
                    "-sUSE_PTHREADS=1",
                        "-sSHARED_MEMORY=0",  // Disable shared memory
    "-sMEMORY64=0",  // Disable 64-bit memory

                    "-sPTHREAD_POOL_SIZE=2",
                    "-sWASM_MEM_MAX=2147483648", // 2GB maximum
                    "-sINITIAL_MEMORY=128MB", // Increased from 64MB
                    "-sSTACK_SIZE=16MB", // Increased from 5MB
                    "-sTOTAL_STACK=16MB", // Explicit stack size
                    "-sASSERTIONS=1", // Enable for debugging
                    //"-sSAFE_HEAP=1", // Add bounds checking
                    "-sINITIAL_MEMORY=128MB", // Double initial memory
                    "--bind",
                    "-lembind",
                });

                b.installArtifact(lib);

                b.getInstallStep().dependOn(&emcc_command.step);
            }
        },
        else => {
            const exe = b.addExecutable(.{
                .name = "openipc-zig",
                .target = target,
                .optimize = optimize,
            });
            exe.addCSourceFile(.{
                .file = b.path("src/wrapper.cpp"),
                .flags = &.{
                    "-std=gnu++20",
                },
            });
            exe.linkLibrary(libusb);
            exe.linkLibrary(wifidriver);
            exe.linkLibC();
            exe.linkLibCpp();
            b.installArtifact(exe);
        },
    }
}
