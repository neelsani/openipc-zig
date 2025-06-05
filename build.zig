const std = @import("std");
const builtin = @import("builtin");

fn createEmsdkStep(b: *std.Build, emsdk: *std.Build.Dependency) *std.Build.Step.Run {
    if (builtin.os.tag == .windows) {
        return b.addSystemCommand(&.{emsdk.path("emsdk.bat").getPath(b)});
    } else {
        return b.addSystemCommand(&.{emsdk.path("emsdk").getPath(b)});
    }
}

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
    }
    return null;
}

pub fn build(b: *std.Build) !void {
    var target = b.standardTargetOptions(.{});
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
    const optimize = b.standardOptimizeOption(.{});
    const enable_logging = b.option(bool, "logging", "Enable logging") orelse true;
    const enable_debug_logging = b.option(bool, "debug-logging", "Enable debug logging") orelse false;

    // Common dependencies
    const libusb_dep = b.dependency("libusb", .{
        .target = target,
        .optimize = optimize,
        .logging = enable_logging,
        .@"debug-logging" = enable_debug_logging,
    });
    const wifidriver_dep = b.dependency("devourer", .{
        .target = target,
        .optimize = optimize,
    });

    const libsodium_dep = b.dependency("libsodium", .{
        .target = target,
        .optimize = optimize,
        .@"test" = false,
        .shared = false,
    });

    const sodium = libsodium_dep.artifact(if (target.result.isMinGW()) "libsodium-static" else "sodium");
    const libusb = libusb_dep.artifact("usb-1.0");
    const wifidriver = wifidriver_dep.artifact("WiFiDriver");
    const zig_lib = b.addStaticLibrary(.{
        .name = "zig-functions",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .link_libc = true,
        .optimize = optimize,
    });
    zig_lib.addCSourceFile(.{
        .file = b.path("src/wifi/fec.c"),
        .language = .c,
    });
    zig_lib.addIncludePath(b.path("src/wifi"));
    zig_lib.linkLibrary(sodium);

    if (target.result.os.tag == .emscripten) {

        // For Emscripten target, create a single library that combines everything
        const lib = b.addStaticLibrary(.{
            .name = "openipc-zig",
            .target = target,
            .link_libc = true,
            .optimize = optimize,
        });
        lib.addIncludePath(b.path("src/wifi"));
        // Add C++ wrapper if needed
        lib.addCSourceFiles(.{
            .files = &.{
                "src/wrapper.cpp",
                "src/wifi/WfbProcessor.cpp",
                "src/wifi/WfbReceiver.cpp",
            },
            .language = .cpp,
            .flags = &.{"-std=gnu++20"},
        });
        lib.root_module.addCMacro("__EMSCRIPTEN__", "");

        lib.linkLibrary(zig_lib);
        // Link dependencies
        lib.linkLibrary(libusb);
        lib.linkLibrary(wifidriver);
        lib.linkLibrary(sodium);
        // Handle emscripten setup
        if (b.lazyDependency("emsdk", .{})) |dep| {
            if (try emSdkSetupStep(b, dep)) |emSdkStep| {
                lib.step.dependOn(&emSdkStep.step);
            }

            lib.addIncludePath(dep.path("upstream/emscripten/cache/sysroot/include/c++/v1"));
            lib.addIncludePath(dep.path("upstream/emscripten/cache/sysroot/include/compat"));
            lib.addIncludePath(dep.path("upstream/emscripten/cache/sysroot/include"));
            zig_lib.addIncludePath(dep.path("upstream/emscripten/cache/sysroot/include"));

            const emccExe = switch (builtin.os.tag) {
                .windows => "emcc.bat",
                else => "emcc",
            };
            const emccPath = try std.fs.path.join(b.allocator, &[_][]const u8{ dep.path("upstream/emscripten").getPath(b), emccExe });
            defer b.allocator.free(emccPath);

            const mkdir_command = b.addSystemCommand(&[_][]const u8{ "mkdir", "-p", b.getInstallPath(.prefix, "htmlout") });

            const emcc_command = b.addSystemCommand(&[_][]const u8{emccPath});
            emcc_command.step.dependOn(&lib.step);
            emcc_command.step.dependOn(&mkdir_command.step);

            emcc_command.addFileArg(lib.getEmittedBin());
            emcc_command.addFileArg(wifidriver.getEmittedBin());
            emcc_command.addFileArg(libusb.getEmittedBin());
            emcc_command.addFileArg(zig_lib.getEmittedBin());
            emcc_command.addFileArg(sodium.getEmittedBin());

            emcc_command.addArgs(&[_][]const u8{
                "-o",
                b.getInstallPath(.prefix, "htmlout/index.html"),
                "-pthread",
                "-sASYNCIFY",
                "-sPTHREAD_POOL_SIZE=2",
                "-sALLOW_MEMORY_GROWTH=1",
                "-sINITIAL_MEMORY=128MB",
                "-sMAXIMUM_MEMORY=2GB",
                "-sSTACK_SIZE=5MB",
                "-sTOTAL_STACK=16MB",
                "-sEXPORTED_FUNCTIONS=['_startReceiver','_stopReceiver','_main', '_sendRaw']", // Export C functions
                "-sEXPORTED_RUNTIME_METHODS=['ccall','cwrap','UTF8ToString','lengthBytesUTF8','stringToUTF8']",

                "--js-library",
                b.path("src/js_lib.js").getPath(b),

                "--bind",
                "-lembind",
            });

            b.getInstallStep().dependOn(&emcc_command.step);
        }

        b.installArtifact(lib);
    } else {

        // Native build
        const exe = b.addExecutable(.{
            .name = "openipc-zig",
            .target = target,
            .optimize = optimize,
        });
        exe.addIncludePath(b.path("src/wifi"));
        // Add C++ wrapper if needed
        exe.addCSourceFiles(.{
            .files = &.{
                "src/wrapper.cpp",
                "src/wifi/WfbProcessor.cpp",
                "src/wifi/WfbReceiver.cpp",
            },
            .language = .cpp,
            .flags = &.{"-std=gnu++20"},
        });

        zig_lib.linkLibC();
        exe.linkLibrary(zig_lib);
        // Link dependencies
        exe.linkLibrary(libusb);
        exe.linkLibrary(wifidriver);
        exe.linkLibrary(sodium);
        exe.linkLibC();
        exe.linkLibCpp();
        b.installArtifact(exe);
    }
}
