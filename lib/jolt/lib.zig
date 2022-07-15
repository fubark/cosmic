const std = @import("std");

const sdl = @import("../sdl/lib.zig");
const stdx = @import("../../stdx/lib.zig");

pub const pkg = std.build.Pkg{
    .name = "jolt",
    .source = .{ .path = srcPath() ++ "/jolt.zig" },
    .dependencies = &.{ stdx.pkg },
};

pub fn addPackage(step: *std.build.LibExeObjStep) void {
    var new_pkg = pkg;
    step.addPackage(new_pkg);
    step.addIncludeDir(srcPath() ++ "/vendor");
    step.addIncludeDir(srcPath() ++ "/");
}

const BuildOptions = struct {
    multi_threaded: bool = true,
    enable_simd: bool = true,
};

pub fn createTest(b: *std.build.Builder, target: std.zig.CrossTarget, mode: std.builtin.Mode, opts: BuildOptions) *std.build.LibExeObjStep {
    const exe = b.addExecutable("test-jolt", null);
    exe.setBuildMode(mode);
    exe.setTarget(target);
    exe.addIncludeDir(srcPath() ++ "/vendor/UnitTests");
    exe.addIncludeDir(srcPath() ++ "/vendor");
    exe.linkLibCpp();

    buildAndLink(exe, opts);

    var c_flags = std.ArrayList([]const u8).init(b.allocator);
    c_flags.appendSlice(&.{ "-std=c++17" }) catch @panic("error");

    if (!opts.multi_threaded) {
        c_flags.append("-DJPH_SINGLE_THREAD=1") catch @panic("error");
    }
    if (!opts.enable_simd) {
        c_flags.append("-DJPH_NO_SIMD=1") catch @panic("error");
    }

    var sources = std.ArrayList([]const u8).init(b.allocator);
    if (opts.enable_simd) {
        sources.appendSlice(&.{
            "/vendor/UnitTests/Core/FPFlushDenormalsTest.cpp",
        }) catch @panic("error");
    }
    // Many tests won't pass with simd disabled due to not having denormalize mechanism.
    // However the Math tests should pass.
    sources.appendSlice(&.{
        "/vendor/UnitTests/Math/HalfFloatTests.cpp",
        "/vendor/UnitTests/Math/MatrixTests.cpp",
        "/vendor/UnitTests/Math/MathTests.cpp",
        "/vendor/UnitTests/Math/VectorTests.cpp",
        "/vendor/UnitTests/Math/DVec3Tests.cpp",
        "/vendor/UnitTests/Math/Vec3Tests.cpp",
        "/vendor/UnitTests/Math/Vec4Tests.cpp",
        "/vendor/UnitTests/Math/UVec4Tests.cpp",
        "/vendor/UnitTests/Math/QuatTests.cpp",
        "/vendor/UnitTests/Math/Mat44Tests.cpp",
        "/vendor/UnitTests/Geometry/GJKTests.cpp",
        "/vendor/UnitTests/Geometry/EllipseTest.cpp",
        "/vendor/UnitTests/Geometry/EPATests.cpp",
        "/vendor/UnitTests/Geometry/RayAABoxTests.cpp",
        "/vendor/UnitTests/Geometry/PlaneTests.cpp",
        "/vendor/UnitTests/Geometry/ConvexHullBuilderTest.cpp",
        "/vendor/UnitTests/Core/StringToolsTest.cpp",
        "/vendor/UnitTests/Core/JobSystemTest.cpp",
        "/vendor/UnitTests/Core/LinearCurveTest.cpp",
        // Currently not building all of ObjectStream since it is an extra feature.
        // "/vendor/UnitTests/ObjectStream/ObjectStreamTest.cpp",

        "/vendor/UnitTests/Physics/PhysicsTests.cpp",
        "/vendor/UnitTests/Physics/BroadPhaseTests.cpp",
        "/vendor/UnitTests/Physics/ShapeTests.cpp",
        "/vendor/UnitTests/Physics/PhysicsStepListenerTests.cpp",
        "/vendor/UnitTests/Physics/ContactListenerTests.cpp",
        "/vendor/UnitTests/Physics/TransformedShapeTests.cpp",
        "/vendor/UnitTests/Physics/SensorTests.cpp",
        "/vendor/UnitTests/Physics/ConvexVsTrianglesTest.cpp",
        "/vendor/UnitTests/Physics/CollideShapeTests.cpp",
        "/vendor/UnitTests/Physics/CollisionGroupTests.cpp",
        "/vendor/UnitTests/Physics/RayShapeTests.cpp",
        "/vendor/UnitTests/Physics/CastShapeTests.cpp",
        "/vendor/UnitTests/Physics/CollidePointTests.cpp",
        "/vendor/UnitTests/Physics/SliderConstraintTests.cpp",
        "/vendor/UnitTests/Physics/PathConstraintTests.cpp",
        "/vendor/UnitTests/Physics/ActiveEdgesTests.cpp",
        "/vendor/UnitTests/Physics/SubShapeIDTest.cpp",
        "/vendor/UnitTests/Physics/HeightFieldShapeTests.cpp",
        "/vendor/UnitTests/Physics/MotionQualityLinearCastTests.cpp",
        "/vendor/UnitTests/Physics/PhysicsDeterminismTests.cpp",
        "/vendor/UnitTests/PhysicsTestContext.cpp",
        
        // This generates the main with doctest.
        "/vendor/UnitTests/UnitTestFramework.cpp",
    }) catch @panic("error");
    for (sources.items) |src| {
        exe.addCSourceFile(b.fmt("{s}{s}", .{srcPath(), src}), c_flags.items);
    }

    // Turns out UnitTestFramework generates the main and sets up the default allocator.
    // c_flags.clearRetainingCapacity();
    // c_flags.appendSlice(&.{ "-std=c++17" }) catch @panic("error");
    // c_flags.appendSlice(&.{ "-DDOCTEST_CONFIG_IMPLEMENT_WITH_MAIN=1" }) catch @panic("error");
    // exe.addCSourceFile(b.fmt("{s}/doctest.cpp", .{srcPath()}), c_flags.items);

    return exe;
}

pub fn buildAndLink(step: *std.build.LibExeObjStep, opts: BuildOptions) void {
    const b = step.builder;
    const lib = b.addStaticLibrary("jolt", null);
    lib.setTarget(step.target);
    lib.setBuildMode(step.build_mode);
    lib.addIncludeDir(srcPath() ++ "/vendor");
    lib.linkLibCpp();

    var c_flags = std.ArrayList([]const u8).init(b.allocator);
    c_flags.appendSlice(&.{ "-std=c++17" }) catch @panic("error");
    // Since the TempAllocator does allocations aligned by 16bytes, data structures that use JPH_CACHE_LINE_SIZE should also be aligned by 16bytes.
    c_flags.append("-DJPH_CACHE_LINE_SIZE=16") catch @panic("error");
    if (step.build_mode == .Debug) {
        c_flags.append("-DJPH_ENABLE_ASSERTS=1") catch @panic("error");
        // For debugging:
        // c_flags.append("-O0") catch @panic("error");
        if (step.target.getCpuArch().isWasm()) {
            // Compile with some optimization or number of function locals will exceed max limit in browsers.
            c_flags.append("-O1") catch @panic("error");
        }
    }
    if (!opts.multi_threaded) {
        c_flags.append("-DJPH_SINGLE_THREAD=1") catch @panic("error");
    }
    if (!opts.enable_simd) {
        c_flags.append("-DJPH_NO_SIMD=1") catch @panic("error");
    }

    var sources = std.ArrayList([]const u8).init(b.allocator);
    sources.appendSlice(&.{
        "/vendor/Jolt/AABBTree/AABBTreeBuilder.cpp",
        "/vendor/Jolt/Core/Color.cpp",
        "/vendor/Jolt/Core/Factory.cpp",
        "/vendor/Jolt/Core/IssueReporting.cpp",
        "/vendor/Jolt/Core/LinearCurve.cpp",
        "/vendor/Jolt/Core/Memory.cpp",
        "/vendor/Jolt/Core/RTTI.cpp",
        "/vendor/Jolt/Core/StringTools.cpp",
        "/vendor/Jolt/Core/JobSystemThreadPool.cpp",
        "/vendor/Jolt/Geometry/Indexify.cpp",
        "/vendor/Jolt/Geometry/OrientedBox.cpp",
        "/vendor/Jolt/Geometry/ConvexHullBuilder.cpp",
        "/vendor/Jolt/Geometry/ConvexHullBuilder2D.cpp",
        "/vendor/Jolt/Math/UVec4.cpp",
        "/vendor/Jolt/ObjectStream/ObjectStream.cpp",
        "/vendor/Jolt/ObjectStream/ObjectStreamOut.cpp",
        "/vendor/Jolt/ObjectStream/SerializableObject.cpp",
        "/vendor/Jolt/ObjectStream/TypeDeclarations.cpp",
        "/vendor/Jolt/Physics/Body/Body.cpp",
        "/vendor/Jolt/Physics/Body/BodyAccess.cpp",
        "/vendor/Jolt/Physics/Body/BodyCreationSettings.cpp",
        "/vendor/Jolt/Physics/Body/BodyInterface.cpp",
        "/vendor/Jolt/Physics/Body/BodyManager.cpp",
        "/vendor/Jolt/Physics/Body/MassProperties.cpp",
        "/vendor/Jolt/Physics/Body/MotionProperties.cpp",
        "/vendor/Jolt/Physics/Collision/BroadPhase/BroadPhase.cpp",
        "/vendor/Jolt/Physics/Collision/BroadPhase/BroadPhaseQuadTree.cpp",
        "/vendor/Jolt/Physics/Collision/BroadPhase/QuadTree.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/BoxShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/CapsuleShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/CompoundShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/ConvexHullShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/ConvexShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/CylinderShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/DecoratedShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/HeightFieldShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/MeshShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/MutableCompoundShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/OffsetCenterOfMassShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/RotatedTranslatedShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/ScaledShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/Shape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/SphereShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/StaticCompoundShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/TaperedCapsuleShape.cpp",
        "/vendor/Jolt/Physics/Collision/Shape/TriangleShape.cpp",
        "/vendor/Jolt/Physics/Collision/CastConvexVsTriangles.cpp",
        "/vendor/Jolt/Physics/Collision/CastSphereVsTriangles.cpp",
        "/vendor/Jolt/Physics/Collision/CollideConvexVsTriangles.cpp",
        "/vendor/Jolt/Physics/Collision/CollideSphereVsTriangles.cpp",
        "/vendor/Jolt/Physics/Collision/CollisionDispatch.cpp",
        "/vendor/Jolt/Physics/Collision/CollisionGroup.cpp",
        "/vendor/Jolt/Physics/Collision/GroupFilter.cpp",
        "/vendor/Jolt/Physics/Collision/GroupFilterTable.cpp",
        "/vendor/Jolt/Physics/Collision/ManifoldBetweenTwoFaces.cpp",
        "/vendor/Jolt/Physics/Collision/NarrowPhaseQuery.cpp",
        "/vendor/Jolt/Physics/Collision/PhysicsMaterial.cpp",
        "/vendor/Jolt/Physics/Collision/PhysicsMaterialSimple.cpp",
        "/vendor/Jolt/Physics/Collision/TransformedShape.cpp",
        "/vendor/Jolt/Physics/Constraints/ConeConstraint.cpp",
        "/vendor/Jolt/Physics/Constraints/Constraint.cpp",
        "/vendor/Jolt/Physics/Constraints/ConstraintManager.cpp",
        "/vendor/Jolt/Physics/Constraints/ContactConstraintManager.cpp",
        "/vendor/Jolt/Physics/Constraints/DistanceConstraint.cpp",
        "/vendor/Jolt/Physics/Constraints/FixedConstraint.cpp",
        "/vendor/Jolt/Physics/Constraints/GearConstraint.cpp",
        "/vendor/Jolt/Physics/Constraints/HingeConstraint.cpp",
        "/vendor/Jolt/Physics/Constraints/MotorSettings.cpp",
        "/vendor/Jolt/Physics/Constraints/PathConstraint.cpp",
        "/vendor/Jolt/Physics/Constraints/PathConstraintPath.cpp",
        "/vendor/Jolt/Physics/Constraints/PathConstraintPathHermite.cpp",
        "/vendor/Jolt/Physics/Constraints/PointConstraint.cpp",
        "/vendor/Jolt/Physics/Constraints/RackAndPinionConstraint.cpp",
        "/vendor/Jolt/Physics/Constraints/SixDOFConstraint.cpp",
        "/vendor/Jolt/Physics/Constraints/SliderConstraint.cpp",
        "/vendor/Jolt/Physics/Constraints/SwingTwistConstraint.cpp",
        "/vendor/Jolt/Physics/Constraints/TwoBodyConstraint.cpp",
        "/vendor/Jolt/Physics/Ragdoll/Ragdoll.cpp",
        "/vendor/Jolt/Physics/Vehicle/VehicleAntiRollBar.cpp",
        "/vendor/Jolt/Physics/Vehicle/VehicleConstraint.cpp",
        "/vendor/Jolt/Physics/Vehicle/VehicleController.cpp",
        "/vendor/Jolt/Physics/Vehicle/VehicleDifferential.cpp",
        "/vendor/Jolt/Physics/Vehicle/VehicleEngine.cpp",
        "/vendor/Jolt/Physics/Vehicle/VehicleTransmission.cpp",
        "/vendor/Jolt/Physics/Vehicle/Wheel.cpp",
        "/vendor/Jolt/Physics/Vehicle/WheeledVehicleController.cpp",
        "/vendor/Jolt/Physics/IslandBuilder.cpp",
        "/vendor/Jolt/Physics/PhysicsLock.cpp",
        "/vendor/Jolt/Physics/PhysicsScene.cpp",
        "/vendor/Jolt/Physics/PhysicsSystem.cpp",
        "/vendor/Jolt/Physics/PhysicsUpdateContext.cpp",
        "/vendor/Jolt/Skeleton/Skeleton.cpp",
        "/vendor/Jolt/Skeleton/SkeletalAnimation.cpp",
        "/vendor/Jolt/TriangleSplitter/TriangleSplitter.cpp",
        "/vendor/Jolt/TriangleSplitter/TriangleSplitterBinning.cpp",
        "/vendor/Jolt/RegisterTypes.cpp",
        "/cjolt.cpp",
    }) catch @panic("error");
    for (sources.items) |src| {
        lib.addCSourceFile(b.fmt("{s}{s}", .{srcPath(), src}), c_flags.items);
    }
    if (!opts.multi_threaded) {
        lib.addCSourceFile(b.fmt("{s}/vendor/Jolt/atomic.cpp", .{srcPath()}), c_flags.items);
    }
    step.linkLibrary(lib);
}

fn srcPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse unreachable;
}