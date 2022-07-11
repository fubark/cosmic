#include <stdint.h>

// Core.h
typedef unsigned int uint;
typedef uint8_t uint8;
typedef uint16_t uint16;
typedef uint32_t uint32;
typedef uint64_t uint64;

// JPH basic types.
typedef char bool;
typedef uintptr_t usize;
typedef struct Vec4 {
    // Does zig support arrays in structs? Use components for now.
    float x;
    float y;
    float z;
    float w;
} Vec4 __attribute__((aligned(16)));
typedef Vec4 Vec3;
typedef Vec4 Quat;
typedef struct Mat44 {
    Vec4 mCol[4];
} Mat44 __attribute__((aligned(16)));
typedef uintptr_t RefConst;
typedef uint32 GroupID;
typedef uint32 SubGroupID;
typedef uint8 EMotionType;
typedef uint8 EMotionQuality;
typedef uint8 EOverrideMassProperties;
typedef uint32 EActivation;

// JPH main types.
typedef struct PhysicsSystem PhysicsSystem;
typedef struct BroadPhaseLayerInterface BroadPhaseLayerInterface;
typedef uint16 ObjectLayer;
typedef struct PhysicsMaterial PhysicsMaterial;
typedef struct Shape Shape;
typedef struct BoxShape BoxShape;
typedef struct TempAllocator TempAllocator;
typedef struct JobSystem JobSystem;
typedef struct BodyId {
    uint32 mID;
} BodyId;
typedef struct BroadPhaseLayer {
    uint8 mValue;
} BroadPhaseLayer;
typedef int (*ObjectVsBroadPhaseLayerFilter)(ObjectLayer inLayer1, BroadPhaseLayer inLayer2);
typedef int (*ObjectLayerPairFilter)(ObjectLayer inLayer1, ObjectLayer inLayer2);
typedef bool (*AssertFailedFunction)(const char *inExpression, const char *inMessage, const char *inFile, uint inLine);
typedef struct BPLayerInterfaceImpl BPLayerInterfaceImpl;
typedef struct BodyLockInterface BodyLockInterface;
typedef struct BodyManager BodyManager;
typedef struct BroadPhase BroadPhase;
typedef struct BodyInterface {
	BodyLockInterface* mBodyLockInterface;
	BodyManager* mBodyManager;
	BroadPhase* mBroadPhase;
} BodyInterface;
typedef struct BodyLockInterface BodyLockInterface;
typedef struct Body Body;
typedef struct CollisionGroup {
    RefConst mGroupFilter;
    GroupID	mGroupID;
    SubGroupID mSubGroupID;
} CollisionGroup;
typedef struct MassProperties {
    float mMass;
	Mat44 mInertia;
} MassProperties;
typedef struct BodyCreationSettings {
    Vec3 mPosition;
    Quat mRotation;
    Vec3 mLinearVelocity;
    Vec3 mAngularVelocity;
    uint64 mUserData;
    ObjectLayer mObjectLayer;
    CollisionGroup mCollisionGroup;
    EMotionType mMotionType;
    bool mAllowDynamicOrKinematic;
    bool mIsSensor;
    EMotionQuality mMotionQuality;
    bool mAllowSleeping;
    float mFriction;
    float mRestitution;
    float mLinearDamping;
    float mAngularDamping;
    float mMaxLinearVelocity;
    float mMaxAngularVelocity;
    float mGravityFactor;
    EOverrideMassProperties	mOverrideMassProperties;
    float mInertiaMultiplier;
    // Need this alignment to match with c++ for some reason.
    MassProperties mMassPropertiesOverride __attribute__((aligned(16)));
    // Private.
    RefConst mShape;
    RefConst mShapePtr;
} BodyCreationSettings;
typedef struct BodyLock {
	const BodyLockInterface* mBodyLockInterface;
	uint32_t mBodyLockMutex;
	Body* mBody;
} BodyLock;

void JPH__InitDefaultFactory();
void JPH__RegisterDefaultAllocator();
void JPH__RegisterTypes();

PhysicsSystem* JPH__PhysicsSystem__NEW();
void JPH__PhysicsSystem__Init(
    PhysicsSystem* self,
    uint inMaxBodies,
    uint inNumBodyMutexes,
    uint inMaxBodyPairs,
    uint inMaxContactConstraints,
    BroadPhaseLayerInterface* inBroadPhaseLayerInterface,
    ObjectVsBroadPhaseLayerFilter inObjectVsBroadPhaseLayerFilter,
    ObjectLayerPairFilter inObjectLayerPairFilter
);
void JPH__PhysicsSystem__DELETE(PhysicsSystem* handle);
BodyInterface* JPH__PhysicsSystem__GetBodyInterface(PhysicsSystem* handle);
BodyInterface* JPH__PhysicsSystem__GetBodyInterfaceNoLock(PhysicsSystem* handle);
BodyLockInterface* JPH__PhysicsSystem__GetBodyLockInterface(PhysicsSystem* handle);
BodyLockInterface* JPH__PhysicsSystem__GetBodyLockInterfaceNoLock(PhysicsSystem* handle);
void JPH__PhysicsSystem__Update(
    PhysicsSystem* self,
    float inDeltaTime,
    int inCollisionSteps,
    int inIntegrationSubSteps,
    TempAllocator* inTempAllocator,
    JobSystem* inJobSystem
);
Vec3 JPH__PhysicsSystem__GetGravity(const PhysicsSystem* self);
usize JPH__PhysicsSystem__GetNumActiveBodies(const PhysicsSystem* self);
void JPH__PhysicsSystem__GetActiveBodies(const PhysicsSystem* self, BodyId* out);

BPLayerInterfaceImpl* JPH__BPLayerInterfaceImpl__NEW();
void JPH__BPLayerInterfaceImpl__DELETE(BPLayerInterfaceImpl* handle);

Body* JPH__BodyInterface__CreateBody(BodyInterface* self, const BodyCreationSettings* settings);
void JPH__BodyInterface__AddBody(BodyInterface* self, const BodyId* inBodyID, EActivation inActivationMode);
void JPH__BodyInterface__SetLinearVelocity(BodyInterface* self, const BodyId* inBodyID, Vec3 inLinearVelocity);

Body* JPH__BodyLockInterface__TryGetBody(const BodyLockInterface* self, const BodyId* bodyId);

usize JPH__BodyCreationSettings__SIZEOF();
BodyCreationSettings JPH__BodyCreationSettings__CONSTRUCT();
BodyCreationSettings JPH__BodyCreationSettings__CONSTRUCT2(
    Shape* shape,
    Vec3* pos,
    Quat* rot,
    EMotionType motion_type,
    ObjectLayer object_layer
);

BoxShape* JPH__BoxShape__NEW(
    Vec3* inHalfExtent,
    float inConvexRadius,
    const PhysicsMaterial* inMaterial
);

BodyId JPH__Body__GetID(const Body* self);
Vec3 JPH__Body__GetPosition(const Body* self);
Quat JPH__Body__GetRotation(const Body* self);
bool JPH__Body__IsActive(const Body* self);
uint64 JPH__Body__GetUserData(const Body* self);
void JPH__Body__SetUserData(Body* self, uint64 user_data);

void JPH__BodyLockRead__CONSTRUCT(
    BodyLock* self,
    const BodyLockInterface* body_iface,
    const BodyId* body_id
);
void JPH__BodyLockRead__DESTRUCT(BodyLock* self);
bool JPH__BodyLockRead__SucceededAndIsInBroadPhase(BodyLock* self);
bool JPH__BodyLockRead__Succeeded(BodyLock* self);
Body* JPH__BodyLockRead__GetBody(BodyLock* self);
usize JPH__BodyLockRead__SIZEOF();

TempAllocator* JPH__TempAllocatorImpl__NEW(uint size);
void JPH__TempAllocatorImpl__DELETE(TempAllocator* self);

JobSystem* JPH__JobSystemThreadPool__NEW(uint inMaxJobs, uint inMaxBarriers, int inNumThreads);
void JPH__JobSystemThreadPool__DELETE(JobSystem* self);

void JPH__SetAssertFailed(AssertFailedFunction func);