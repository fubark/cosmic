#include "Jolt/Jolt.h"
#include "Jolt/RegisterTypes.h"
#include "Jolt/Core/Factory.h"
#include "Jolt/Core/IssueReporting.h"
#include "Jolt/Core/JobSystemThreadPool.h"
#include "Jolt/Physics/PhysicsSystem.h"
#include "Jolt/Physics/Collision/Shape/BoxShape.h"
#include "Jolt/Physics/Body/BodyCreationSettings.h"

JPH_NAMESPACE_BEGIN

/// Layer that objects can be in, determines which other objects it can collide with
namespace Layers
{
    static constexpr uint8 UNUSED1 = 0; // 4 unused values so that broadphase layers values don't match with object layer values (for testing purposes)
    static constexpr uint8 UNUSED2 = 1;
    static constexpr uint8 UNUSED3 = 2;
    static constexpr uint8 UNUSED4 = 3;
    static constexpr uint8 NON_MOVING = 4;
    static constexpr uint8 MOVING = 5;
    static constexpr uint8 DEBRIS = 6; // Example: Debris collides only with NON_MOVING
    static constexpr uint8 SENSOR = 7; // Sensors only collide with MOVING objects
    static constexpr uint8 NUM_LAYERS = 8;
};

namespace BroadPhaseLayers
{
    static constexpr BroadPhaseLayer NON_MOVING(0);
    static constexpr BroadPhaseLayer MOVING(1);
    static constexpr BroadPhaseLayer DEBRIS(2);
    static constexpr BroadPhaseLayer SENSOR(3);
    static constexpr BroadPhaseLayer UNUSED(4);
    static constexpr uint NUM_LAYERS(5);
};

class BPLayerInterfaceImpl final : public BroadPhaseLayerInterface {
    public:
        BPLayerInterfaceImpl() {
        // Create a mapping table from object to broad phase layer
        mObjectToBroadPhase[Layers::UNUSED1] = BroadPhaseLayers::UNUSED;
        mObjectToBroadPhase[Layers::UNUSED2] = BroadPhaseLayers::UNUSED;
        mObjectToBroadPhase[Layers::UNUSED3] = BroadPhaseLayers::UNUSED;
        mObjectToBroadPhase[Layers::UNUSED4] = BroadPhaseLayers::UNUSED;
        mObjectToBroadPhase[Layers::NON_MOVING] = BroadPhaseLayers::NON_MOVING;
        mObjectToBroadPhase[Layers::MOVING] = BroadPhaseLayers::MOVING;
        mObjectToBroadPhase[Layers::DEBRIS] = BroadPhaseLayers::DEBRIS;
        mObjectToBroadPhase[Layers::SENSOR] = BroadPhaseLayers::SENSOR;
    }

    virtual uint GetNumBroadPhaseLayers() const override {
        return BroadPhaseLayers::NUM_LAYERS;
    }

    virtual BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer inLayer) const override {
        JPH_ASSERT(inLayer < Layers::NUM_LAYERS);
        return mObjectToBroadPhase[inLayer];
    }

    private:
        BroadPhaseLayer mObjectToBroadPhase[Layers::NUM_LAYERS];
};

extern "C" {

void JPH__InitDefaultFactory() {
    Factory::sInstance = new Factory();
}

void JPH__RegisterDefaultAllocator() {
    RegisterDefaultAllocator();
}

void JPH__RegisterTypes() {
    RegisterTypes();
}

/// PhysicsSystem

PhysicsSystem* JPH__PhysicsSystem__NEW() {
    PhysicsSystem* res = new PhysicsSystem();
    if (res == nullptr) {
        exit(0);
    }
    return res;
}

void JPH__PhysicsSystem__Init(
    PhysicsSystem* self,
    uint inMaxBodies,
    uint inNumBodyMutexes,
    uint inMaxBodyPairs,
    uint inMaxContactConstraints,
    const BroadPhaseLayerInterface& inBroadPhaseLayerInterface,
    ObjectVsBroadPhaseLayerFilter inObjectVsBroadPhaseLayerFilter,
    ObjectLayerPairFilter inObjectLayerPairFilter
) {
    self->Init(inMaxBodies, inNumBodyMutexes, inMaxBodyPairs, inMaxContactConstraints,
        inBroadPhaseLayerInterface, inObjectVsBroadPhaseLayerFilter, inObjectLayerPairFilter);
}

void JPH__PhysicsSystem__DELETE(PhysicsSystem* handle) {
    delete handle;
}

void JPH__PhysicsSystem__Update(
    PhysicsSystem* self,
    float inDeltaTime,
    int inCollisionSteps,
    int inIntegrationSubSteps,
    TempAllocator* inTempAllocator,
    JobSystem* inJobSystem
) {
    self->Update(inDeltaTime, inCollisionSteps, inIntegrationSubSteps, inTempAllocator, inJobSystem);
}

const BodyInterface* JPH__PhysicsSystem__GetBodyInterface(PhysicsSystem* handle) {
    return &handle->GetBodyInterface();
}

const BodyInterface* JPH__PhysicsSystem__GetBodyInterfaceNoLock(PhysicsSystem* handle) {
    return &handle->GetBodyInterfaceNoLock();
}

const BodyLockInterface* JPH__PhysicsSystem__GetBodyLockInterface(PhysicsSystem* handle) {
    return &handle->GetBodyLockInterface();
}

const BodyLockInterface* JPH__PhysicsSystem__GetBodyLockInterfaceNoLock(PhysicsSystem* handle) {
    return &handle->GetBodyLockInterfaceNoLock();
}

Vec3 JPH__PhysicsSystem__GetGravity(const PhysicsSystem& self) {
    return self.GetGravity();
}

size_t JPH__PhysicsSystem__GetNumActiveBodies(const PhysicsSystem& self) {
    return self.GetNumActiveBodies();
}

// Operates on buffer instead of c++ vector.
void JPH__PhysicsSystem__GetActiveBodies(const PhysicsSystem& self, BodyID* out) {
    self.GetActiveBodiesBuf(out);
}

/// BPLayerInterfaceImpl

BPLayerInterfaceImpl* JPH__BPLayerInterfaceImpl__NEW() {
    return new BPLayerInterfaceImpl();
}

void JPH__BPLayerInterfaceImpl__DELETE(BPLayerInterfaceImpl* handle) {
    delete handle;
}

/// BodyInterface

Body* JPH__BodyInterface__CreateBody(
    BodyInterface* self,
    const BodyCreationSettings& settings
) {
    return self->CreateBody(settings);
}

void JPH__BodyInterface__AddBody(
    BodyInterface* self,
    const BodyID &inBodyID,
    EActivation inActivationMode
) {
    self->AddBody(inBodyID, inActivationMode);
}

void JPH__BodyInterface__SetLinearVelocity(BodyInterface* self, const BodyID& inBodyID, Vec3Arg inLinearVelocity) {
	self->SetLinearVelocity(inBodyID, inLinearVelocity);
}

/// BodyLockInterface
Body* JPH__BodyLockInterface__TryGetBody(const BodyLockInterface& self, const BodyID& bodyId) {
    return self.TryGetBody(bodyId);
}

size_t JPH__BodyCreationSettings__SIZEOF() {
    return sizeof(BodyCreationSettings);
}

BodyCreationSettings JPH__BodyCreationSettings__CONSTRUCT() {
    return BodyCreationSettings();
}

BodyCreationSettings JPH__BodyCreationSettings__CONSTRUCT2(
    Shape* shape,
    Vec3Arg& pos,
    QuatArg& rot,
    EMotionType motion_type,
    ObjectLayer object_layer
) {
    return BodyCreationSettings(shape, pos, rot, motion_type, object_layer);
}

BoxShape* JPH__BoxShape__NEW(
    Vec3Arg& inHalfExtent,
    float inConvexRadius,
    const PhysicsMaterial *inMaterial
) {
    return new BoxShape(inHalfExtent, inConvexRadius, inMaterial);
}

/// Body

BodyID JPH__Body__GetID(const Body& self) {
    return self.GetID();
}

Vec3 JPH__Body__GetPosition(const Body& self) {
	return self.GetPosition();
}

Quat JPH__Body__GetRotation(const Body& self) {
    return self.GetRotation();
}

bool JPH__Body__IsActive(const Body& self) {
    return self.IsActive();
}

uint64 JPH__Body__GetUserData(const Body& self)	{
    return self.GetUserData();
}

void JPH__Body__SetUserData(Body* self, uint64 user_data) {
    self->SetUserData(user_data);
}

void JPH__BodyLockRead__CONSTRUCT(
    BodyLockRead* self,
    const BodyLockInterface& body_iface,
    const BodyID& body_id
) {
    new (self) BodyLockRead(body_iface, body_id);
}

void JPH__BodyLockRead__DESTRUCT(BodyLockRead* self) {
    self->~BodyLockRead();
}

bool JPH__BodyLockRead__SucceededAndIsInBroadPhase(const BodyLockRead& self) {
    return self.SucceededAndIsInBroadPhase();
}

bool JPH__BodyLockRead__Succeeded(const BodyLockRead& self) {
    return self.Succeeded();
}

const Body* JPH__BodyLockRead__GetBody(const BodyLockRead& self) {
    return &self.GetBody();
}

size_t JPH__BodyLockRead__SIZEOF() {
    return sizeof(BodyLockRead);
}

TempAllocatorImpl* JPH__TempAllocatorImpl__NEW(uint size) {
    return new TempAllocatorImpl(size);
}

void JPH__TempAllocatorImpl__DELETE(TempAllocatorImpl* self) {
    delete self;
}

JobSystemThreadPool* JPH__JobSystemThreadPool__NEW(uint inMaxJobs, uint inMaxBarriers, int inNumThreads) {
    return new JobSystemThreadPool(inMaxJobs, inMaxBarriers, inNumThreads);
}

void JPH__JobSystemThreadPool__DELETE(JobSystemThreadPool* self) {
    delete self;
}

#ifdef JPH_ENABLE_ASSERTS
void JPH__SetAssertFailed(AssertFailedFunction func) {
    AssertFailed = func;
}
#endif

}

JPH_NAMESPACE_END