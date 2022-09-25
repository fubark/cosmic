const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("../../stdx/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "sdl",
    .source = .{ .path = srcPath() ++ "/sdl.zig" },
    .dependencies = &.{ stdx.pkg },
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    step.addPackage(pkg);
    step.linkLibC();
    step.addIncludePath(srcPath() ++ "/vendor/include");
    step.addIncludePath(srcPath() ++ "/");
}

pub fn create(
    b: *std.build.Builder,
    target: std.zig.CrossTarget,
    mode: std.builtin.Mode,
) !*std.build.LibExeObjStep {
    const lib = b.addStaticLibrary("sdl2", null);
    lib.setTarget(target);
    lib.setBuildMode(mode);

    const alloc = b.allocator;

    // Use SDL_config_minimal.h instead of relying on configure or CMake
    // and add defines to make it work for most modern platforms.
    var c_flags = std.ArrayList([]const u8).init(alloc);
    // Don't include SDL rendering lib.
    try c_flags.append("-DSDL_RENDER_DISABLED=1");

    if (target.getOsTag() == .macos) {
        try c_flags.appendSlice(&.{
            // Silence warnings that are errors by default in objc source files. Noticed this in github ci.
            "-Wno-deprecated-declarations",
            "-Wno-unguarded-availability",
        });
    } else if (target.getOsTag() == .linux) {
        try c_flags.append("-DSDL_VIDEO_VULKAN=1");
    }

    // Look at CMakeLists.txt.
    var c_files = std.ArrayList([]const u8).init(alloc);

    try c_files.appendSlice(&.{
        // General source files.
        "SDL_log.c",
        "SDL_hints.c",
        "SDL_error.c",
        "SDL_dataqueue.c",
        "SDL.c",
        "SDL_assert.c",
        "SDL_list.c",
        "SDL_utils.c",
        "SDL_guid.c",
        "atomic/SDL_spinlock.c",
        "atomic/SDL_atomic.c",
        "audio/SDL_wave.c",
        "audio/SDL_mixer.c",
        "audio/SDL_audiotypecvt.c",
        "audio/SDL_audiodev.c",
        "audio/SDL_audiocvt.c",
        "audio/SDL_audio.c",
        "audio/disk/SDL_diskaudio.c",
        "audio/dsp/SDL_dspaudio.c",
        "audio/sndio/SDL_sndioaudio.c",
        "cpuinfo/SDL_cpuinfo.c",
        "dynapi/SDL_dynapi.c",
        "events/SDL_windowevents.c",
        "events/SDL_touch.c",
        "events/SDL_quit.c",
        "events/SDL_mouse.c",
        "events/SDL_keyboard.c",
        "events/SDL_gesture.c",
        "events/SDL_events.c",
        "events/SDL_dropevents.c",
        "events/SDL_displayevents.c",
        "events/SDL_clipboardevents.c",
        "events/imKStoUCS.c",
        "file/SDL_rwops.c",
        "haptic/SDL_haptic.c",
        "hidapi/SDL_hidapi.c",
        "locale/SDL_locale.c",
        "misc/SDL_url.c",
        "power/SDL_power.c",

        // Minimum render code to compile.
        "render/SDL_yuv_sw.c",
        "render/SDL_render.c",

        "sensor/SDL_sensor.c",
        "stdlib/SDL_strtokr.c",
        "stdlib/SDL_stdlib.c",
        "stdlib/SDL_qsort.c",
        "stdlib/SDL_memcpy.c",
        "stdlib/SDL_memset.c",
        "stdlib/SDL_malloc.c",
        "stdlib/SDL_iconv.c",
        "stdlib/SDL_getenv.c",
        "stdlib/SDL_crc32.c",
        "stdlib/SDL_string.c",
        "thread/SDL_thread.c",
        "timer/SDL_timer.c",
        "video/SDL_yuv.c",
        "video/SDL_vulkan_utils.c",
        "video/SDL_surface.c",
        "video/SDL_stretch.c",
        "video/SDL_shape.c",
        "video/SDL_RLEaccel.c",
        "video/SDL_rect.c",
        "video/SDL_pixels.c",
        "video/SDL_video.c",
        "video/SDL_fillrect.c",
        "video/SDL_egl.c",
        "video/SDL_bmp.c",
        "video/SDL_clipboard.c",
        "video/SDL_blit_slow.c",
        "video/SDL_blit_N.c",
        "video/SDL_blit_copy.c",
        "video/SDL_blit_auto.c",
        "video/SDL_blit_A.c",
        "video/SDL_blit.c",
        "video/SDL_blit_0.c",
        "video/SDL_blit_1.c",
        "video/yuv2rgb/yuv_rgb.c",

        // SDL_JOYSTICK
        "joystick/SDL_joystick.c",
        "joystick/SDL_gamecontroller.c",
        "joystick/controller_type.c",

        // Dummy
        "audio/dummy/SDL_dummyaudio.c",
        "sensor/dummy/SDL_dummysensor.c",
        "haptic/dummy/SDL_syshaptic.c",
        "joystick/dummy/SDL_sysjoystick.c",
        "video/dummy/SDL_nullvideo.c",
        "video/dummy/SDL_nullframebuffer.c",
        "video/dummy/SDL_nullevents.c",

        // Steam
        "joystick/steam/SDL_steamcontroller.c",

        "joystick/hidapi/SDL_hidapi_rumble.c",
        "joystick/hidapi/SDL_hidapijoystick.c",
        "joystick/hidapi/SDL_hidapi_xbox360w.c",
        "joystick/hidapi/SDL_hidapi_switch.c",
        "joystick/hidapi/SDL_hidapi_steam.c",
        "joystick/hidapi/SDL_hidapi_stadia.c",
        "joystick/hidapi/SDL_hidapi_ps4.c",
        "joystick/hidapi/SDL_hidapi_xboxone.c",
        "joystick/hidapi/SDL_hidapi_xbox360.c",
        "joystick/hidapi/SDL_hidapi_gamecube.c",
        "joystick/hidapi/SDL_hidapi_ps5.c",
        "joystick/hidapi/SDL_hidapi_luna.c",

        "joystick/virtual/SDL_virtualjoystick.c",
    });

    if (target.getOsTag() == .linux or target.getOsTag() == .macos) {
        try c_files.appendSlice(&.{
            // Threads
            "thread/pthread/SDL_systhread.c",
            "thread/pthread/SDL_systls.c",
            "thread/pthread/SDL_syssem.c",
            "thread/pthread/SDL_sysmutex.c",
            "thread/pthread/SDL_syscond.c",
        });
    }

    if (target.getOsTag() == .linux) {
        try c_files.appendSlice(&.{
            "core/unix/SDL_poll.c",
            "core/linux/SDL_evdev.c",
            "core/linux/SDL_evdev_kbd.c",
            "core/linux/SDL_dbus.c",
            "core/linux/SDL_ime.c",
            "core/linux/SDL_udev.c",
            "core/linux/SDL_threadprio.c",
            // "core/linux/SDL_fcitx.c",
            "core/linux/SDL_ibus.c",
            "core/linux/SDL_evdev_capabilities.c",

            "power/linux/SDL_syspower.c",
            "haptic/linux/SDL_syshaptic.c",

            "misc/unix/SDL_sysurl.c",
            "timer/unix/SDL_systimer.c",
            "locale/unix/SDL_syslocale.c",

            "loadso/dlopen/SDL_sysloadso.c",

            "filesystem/unix/SDL_sysfilesystem.c",

            "video/x11/SDL_x11opengles.c",
            "video/x11/SDL_x11messagebox.c",
            "video/x11/SDL_x11touch.c",
            "video/x11/SDL_x11mouse.c",
            "video/x11/SDL_x11keyboard.c",
            "video/x11/SDL_x11video.c",
            "video/x11/edid-parse.c",
            "video/x11/SDL_x11dyn.c",
            "video/x11/SDL_x11framebuffer.c",
            "video/x11/SDL_x11opengl.c",
            "video/x11/SDL_x11modes.c",
            "video/x11/SDL_x11shape.c",
            "video/x11/SDL_x11window.c",
            "video/x11/SDL_x11vulkan.c",
            "video/x11/SDL_x11xfixes.c",
            "video/x11/SDL_x11clipboard.c",
            "video/x11/SDL_x11events.c",
            "video/x11/SDL_x11xinput2.c",

            "audio/alsa/SDL_alsa_audio.c",
            "audio/pulseaudio/SDL_pulseaudio.c",
            "joystick/linux/SDL_sysjoystick.c",
        });
    } else if (target.getOsTag() == .macos) {
        try c_files.appendSlice(&.{
            "joystick/darwin/SDL_iokitjoystick.c",
            "haptic/darwin/SDL_syshaptic.c",

            "video/cocoa/SDL_cocoametalview.m",
            "video/cocoa/SDL_cocoaclipboard.m",
            "video/cocoa/SDL_cocoashape.m",
            "video/cocoa/SDL_cocoakeyboard.m",
            "video/cocoa/SDL_cocoamessagebox.m",
            "video/cocoa/SDL_cocoaevents.m",
            "video/cocoa/SDL_cocoamouse.m",
            "video/cocoa/SDL_cocoavideo.m",
            "video/cocoa/SDL_cocoawindow.m",
            "video/cocoa/SDL_cocoavulkan.m",
            "video/cocoa/SDL_cocoaopengles.m",
            "video/cocoa/SDL_cocoamodes.m",
            "video/cocoa/SDL_cocoaopengl.m",
            "file/cocoa/SDL_rwopsbundlesupport.m",
            "render/metal/SDL_render_metal.m",
            "filesystem/cocoa/SDL_sysfilesystem.m",
            "audio/coreaudio/SDL_coreaudio.m",
            "locale/macosx/SDL_syslocale.m",

            // Currently, joystick support is disabled in SDL_config.h for macos since there were issues
            // building in github ci and there is no cosmic joystick api atm.
            // Once enabled, SDL_mfijoystick will have a compile error in github ci: cannot create __weak reference in file using manual reference counting
            // This can be resolved by giving it "-fobjc-arc" cflag for just the one file.
            // After that it turns out we'll need CoreHaptics but it's not always available and zig doesn't have a way to set weak frameworks yet:
            // https://github.com/ziglang/zig/issues/10206
            "joystick/iphoneos/SDL_mfijoystick.m",

            "timer/unix/SDL_systimer.c",
            "loadso/dlopen/SDL_sysloadso.c",
            "misc/unix/SDL_sysurl.c",
            "power/macosx/SDL_syspower.c",
        });
    } else if (target.getOsTag() == .windows) {
        try c_files.appendSlice(&.{
            "core/windows/SDL_xinput.c",
            "core/windows/SDL_windows.c",
            "core/windows/SDL_hid.c",
            "misc/windows/SDL_sysurl.c",
            "locale/windows/SDL_syslocale.c",
            "sensor/windows/SDL_windowssensor.c",
            "power/windows/SDL_syspower.c",
            "video/windows/SDL_windowsmodes.c",
            "video/windows/SDL_windowsclipboard.c",
            "video/windows/SDL_windowsopengles.c",
            "video/windows/SDL_windowsevents.c",
            "video/windows/SDL_windowsvideo.c",
            "video/windows/SDL_windowskeyboard.c",
            "video/windows/SDL_windowsshape.c",
            "video/windows/SDL_windowswindow.c",
            "video/windows/SDL_windowsvulkan.c",
            "video/windows/SDL_windowsmouse.c",
            "video/windows/SDL_windowsopengl.c",
            "video/windows/SDL_windowsframebuffer.c",
            "video/windows/SDL_windowsmessagebox.c",
            "joystick/windows/SDL_rawinputjoystick.c",
            "joystick/windows/SDL_dinputjoystick.c",
            "joystick/windows/SDL_xinputjoystick.c",
            "joystick/windows/SDL_windows_gaming_input.c",
            "joystick/windows/SDL_windowsjoystick.c",
            "haptic/windows/SDL_windowshaptic.c",
            "haptic/windows/SDL_xinputhaptic.c",
            "haptic/windows/SDL_dinputhaptic.c",
            "audio/winmm/SDL_winmm.c",
            "audio/directsound/SDL_directsound.c",
            "audio/wasapi/SDL_wasapi.c",
            "audio/wasapi/SDL_wasapi_win32.c",
            "timer/windows/SDL_systimer.c",
            "thread/windows/SDL_sysmutex.c",
            "thread/windows/SDL_systhread.c",
            "thread/windows/SDL_syssem.c",
            "thread/windows/SDL_systls.c",
            "thread/windows/SDL_syscond_cv.c",
            "thread/generic/SDL_systls.c",
            "thread/generic/SDL_syssem.c",
            "thread/generic/SDL_sysmutex.c",
            "thread/generic/SDL_systhread.c",
            "thread/generic/SDL_syscond.c",
            "loadso/windows/SDL_sysloadso.c",
            "filesystem/windows/SDL_sysfilesystem.c",
        });
    }

    for (c_files.items) |file| {
        const path = b.fmt("{s}/vendor/src/{s}", .{ srcPath(), file });
        lib.addCSourceFile(path, c_flags.items);
    }

    lib.linkLibC();
    // Look for our custom SDL_config.h.
    lib.addIncludePath(srcPath());
    // For local CMake generated config.
    // lib.addIncludePath(fromRoot(b, "vendor/build/include"));
    lib.addIncludePath(fromRoot(b, "vendor/include"));
    if (target.getOsTag() == .linux) {
        lib.addIncludePath("/usr/include");
        lib.addIncludePath("/usr/include/x86_64-linux-gnu");
        lib.addIncludePath("/usr/include/dbus-1.0");
        lib.addIncludePath("/usr/lib/x86_64-linux-gnu/dbus-1.0/include");
    } else if (builtin.os.tag == .macos and target.getOsTag() == .macos) {
        if (target.isNativeOs()) {
            lib.linkFramework("CoreFoundation");
        } else {
            lib.addFrameworkPath("/System/Library/Frameworks");
            lib.setLibCFile(std.build.FileSource.relative("./lib/macos.libc"));
        }
    }

    return lib;
}

pub fn linkLib(step: *std.build.LibExeObjStep, lib: *std.build.LibExeObjStep) void {
    linkDeps(step);
    step.linkLibrary(lib);
}

pub fn linkLibPath(step: *std.build.LibExeObjStep, path: []const u8) void {
    linkDeps(step);
    step.addAssemblyFile(path);
}

pub fn linkDeps(step: *std.build.LibExeObjStep) void {
    if (builtin.os.tag == .macos and step.target.getOsTag() == .macos) {
        // "sdl2_config --static-libs" tells us what we need
        if (!step.target.isNativeOs()) {
            step.addFrameworkPath("/System/Library/Frameworks");
            step.addLibraryPath("/usr/lib"); // To find libiconv.
        }
        step.linkFramework("Cocoa");
        step.linkFramework("IOKit");
        step.linkFramework("CoreAudio");
        step.linkFramework("CoreVideo");
        step.linkFramework("Carbon");
        step.linkFramework("Metal");
        step.linkFramework("ForceFeedback");
        step.linkFramework("AudioToolbox");
        step.linkFramework("GameController");
        step.linkFramework("CFNetwork");
        step.linkSystemLibrary("iconv");
        step.linkSystemLibrary("m");
    } else if (step.target.getOsTag() == .windows and step.target.getAbi() == .gnu) {
        step.linkSystemLibrary("setupapi");
        step.linkSystemLibrary("ole32");
        step.linkSystemLibrary("oleaut32");
        step.linkSystemLibrary("gdi32");
        step.linkSystemLibrary("imm32");
        step.linkSystemLibrary("version");
        step.linkSystemLibrary("winmm");
    }
}

pub const Options = struct {
    lib_path: ?[]const u8 = null,
};

pub fn buildAndLink(step: *std.build.LibExeObjStep, opts: Options) void {
    if (opts.lib_path) |path| {
        linkLibPath(step, path);
    } else {
        const lib = create(step.builder, step.target, step.build_mode) catch unreachable;
        linkLib(step, lib);
    }
}

inline fn srcPath() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}

fn fromRoot(b: *std.build.Builder, rel_path: []const u8) []const u8 {
    return std.fs.path.resolve(b.allocator, &.{ srcPath(), rel_path }) catch unreachable;
}
