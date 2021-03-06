// SPDX-FileCopyrightText: 2021 Jorrit Rouwe
// SPDX-License-Identifier: MIT

JPH_NAMESPACE_BEGIN

UVec4::UVec4(uint32 inX, uint32 inY, uint32 inZ, uint32 inW)
{
#if defined(JPH_USE_SSE)
	mValue = _mm_set_epi32(int(inW), int(inZ), int(inY), int(inX));
#elif defined(JPH_USE_NEON)
	uint32x2_t xy = vcreate_u32(static_cast<uint64>(inX) | (static_cast<uint64>(inY) << 32));
	uint32x2_t zw = vcreate_u32(static_cast<uint64>(inZ) | (static_cast<uint64>(inW) << 32));
	mValue = vcombine_u32(xy, zw);
#else
    mValue = { inX, inY, inZ, inW };
#endif
}

bool UVec4::operator == (UVec4Arg inV2) const
{
	return sEquals(*this, inV2).TestAllTrue();
}

template<uint32 SwizzleX, uint32 SwizzleY, uint32 SwizzleZ, uint32 SwizzleW>
UVec4 UVec4::Swizzle() const
{
	static_assert(SwizzleX <= 3, "SwizzleX template parameter out of range");
	static_assert(SwizzleY <= 3, "SwizzleY template parameter out of range");
	static_assert(SwizzleZ <= 3, "SwizzleZ template parameter out of range");
	static_assert(SwizzleW <= 3, "SwizzleW template parameter out of range");

#if defined(JPH_USE_SSE)
	return _mm_shuffle_epi32(mValue, _MM_SHUFFLE(SwizzleW, SwizzleZ, SwizzleY, SwizzleX));
#elif defined(JPH_USE_NEON)
	return __builtin_shufflevector(mValue, mValue, SwizzleX, SwizzleY, SwizzleZ, SwizzleW);
#else
    return { mU32[SwizzleX], mU32[SwizzleY], mU32[SwizzleZ], mU32[SwizzleW] };
#endif
}

UVec4 UVec4::sZero()
{
#if defined(JPH_USE_SSE)
	return _mm_setzero_si128();
#elif defined(JPH_USE_NEON)
	return vdupq_n_u32(0);
#else
    return { 0, 0, 0, 0 };
#endif
}

UVec4 UVec4::sReplicate(uint32 inV)
{
#if defined(JPH_USE_SSE)
	return _mm_set1_epi32(int(inV));
#elif defined(JPH_USE_NEON)
	return vdupq_n_u32(inV);
#else
    return { inV, inV, inV, inV };
#endif
}

UVec4 UVec4::sLoadInt(const uint32 *inV)
{
#if defined(JPH_USE_SSE)
	return _mm_castps_si128(_mm_load_ss(reinterpret_cast<const float*>(inV)));
#elif defined(JPH_USE_NEON)
	return vsetq_lane_u32(*inV, vdupq_n_u32(0), 0);
#else
    return { *inV, 0, 0, 0 };
#endif
}

UVec4 UVec4::sLoadInt4(const uint32 *inV)
{
#if defined(JPH_USE_SSE)
	return _mm_loadu_si128(reinterpret_cast<const __m128i *>(inV));
#elif defined(JPH_USE_NEON)
	return vld1q_u32(inV);
#else
    return { inV[0], inV[1], inV[2], inV[3] };
#endif
}

UVec4 UVec4::sLoadInt4Aligned(const uint32 *inV)
{
#if defined(JPH_USE_SSE)
	return _mm_load_si128(reinterpret_cast<const __m128i *>(inV));
#elif defined(JPH_USE_NEON)
	return vld1q_u32(inV); // ARM doesn't make distinction between aligned or not
#else
    return { inV[0], inV[1], inV[2], inV[3] };
#endif
}

template <const int Scale>
UVec4 UVec4::sGatherInt4(const uint32 *inBase, UVec4Arg inOffsets)
{
#ifdef JPH_USE_AVX2
	return _mm_i32gather_epi32(reinterpret_cast<const int *>(inBase), inOffsets.mValue, Scale);
#else
	return Vec4::sGatherFloat4<Scale>(reinterpret_cast<const float *>(inBase), inOffsets).ReinterpretAsInt();
#endif
}

UVec4 UVec4::sMin(UVec4Arg inV1, UVec4Arg inV2)
{
#if defined(JPH_USE_SSE4_1)
	return _mm_min_epu32(inV1.mValue, inV2.mValue);
#elif defined(JPH_USE_NEON)
	return vminq_u32(inV1.mValue, inV2.mValue);
#else
	UVec4 result;
	for (int i = 0; i < 4; i++)
		result.mU32[i] = min(inV1.mU32[i], inV2.mU32[i]);
	return result;
#endif
}

UVec4 UVec4::sMax(UVec4Arg inV1, UVec4Arg inV2)
{
#if defined(JPH_USE_SSE4_1)
	return _mm_max_epu32(inV1.mValue, inV2.mValue);
#elif defined(JPH_USE_NEON)
	return vmaxq_u32(inV1.mValue, inV2.mValue);
#else
	UVec4 result;
	for (int i = 0; i < 4; i++)
		result.mU32[i] = max(inV1.mU32[i], inV2.mU32[i]);
	return result;
#endif
}

UVec4 UVec4::sEquals(UVec4Arg inV1, UVec4Arg inV2)
{
#if defined(JPH_USE_SSE)
	return _mm_cmpeq_epi32(inV1.mValue, inV2.mValue);
#elif defined(JPH_USE_NEON)
	return vceqq_u32(inV1.mValue, inV2.mValue);
#else
    return {
        (inV1.mValue.x == inV2.mValue.x) ? 0xFFFFFFFF : 0,
        (inV1.mValue.y == inV2.mValue.y) ? 0xFFFFFFFF : 0,
        (inV1.mValue.z == inV2.mValue.z) ? 0xFFFFFFFF : 0,
        (inV1.mValue.w == inV2.mValue.w) ? 0xFFFFFFFF : 0
    };
#endif
}

UVec4 UVec4::sSelect(UVec4Arg inV1, UVec4Arg inV2, UVec4Arg inControl)
{
#if defined(JPH_USE_SSE4_1)
	return _mm_castps_si128(_mm_blendv_ps(_mm_castsi128_ps(inV1.mValue), _mm_castsi128_ps(inV2.mValue), _mm_castsi128_ps(inControl.mValue)));
#elif defined(JPH_USE_NEON)
	return vbslq_u32(vshrq_n_s32(inControl.mValue, 31), inV2.mValue, inV1.mValue);
#else
	UVec4 result;
	for (int i = 0; i < 4; i++)
		result.mU32[i] = inControl.mU32[i] ? inV2.mU32[i] : inV1.mU32[i];
	return result;
#endif
}

UVec4 UVec4::sOr(UVec4Arg inV1, UVec4Arg inV2)
{
#if defined(JPH_USE_SSE)
	return _mm_or_si128(inV1.mValue, inV2.mValue);
#elif defined(JPH_USE_NEON)
	return vorrq_u32(inV1.mValue, inV2.mValue);
#else
    return { inV1.mValue.x | inV2.mValue.x, inV1.mValue.y | inV2.mValue.y, inV1.mValue.z | inV2.mValue.z, inV1.mValue.w | inV2.mValue.w };
#endif
}

UVec4 UVec4::sXor(UVec4Arg inV1, UVec4Arg inV2)
{
#if defined(JPH_USE_SSE)
	return _mm_xor_si128(inV1.mValue, inV2.mValue);
#elif defined(JPH_USE_NEON)
	return veorq_u32(inV1.mValue, inV2.mValue);
#else
    return { inV1.mValue.x ^ inV2.mValue.x, inV1.mValue.y ^ inV2.mValue.y, inV1.mValue.z ^ inV2.mValue.z, inV1.mValue.w ^ inV2.mValue.w };
#endif
}

UVec4 UVec4::sAnd(UVec4Arg inV1, UVec4Arg inV2)
{
#if defined(JPH_USE_SSE)
	return _mm_and_si128(inV1.mValue, inV2.mValue);
#elif defined(JPH_USE_NEON)
	return vandq_u32(inV1.mValue, inV2.mValue);
#else
    return { inV1.mValue.x & inV2.mValue.x, inV1.mValue.y & inV2.mValue.y, inV1.mValue.z & inV2.mValue.z, inV1.mValue.w & inV2.mValue.w };
#endif
}


UVec4 UVec4::sNot(UVec4Arg inV1)
{
#if defined(JPH_USE_SSE)
	return sXor(inV1, sReplicate(0xffffffff));
#elif defined(JPH_USE_NEON)
	return vmvnq_u32(inV1.mValue);
#else
    return { ~inV1.mValue.x, ~inV1.mValue.y, ~inV1.mValue.z, ~inV1.mValue.w };
#endif
}

UVec4 UVec4::sSort4True(UVec4Arg inValue, UVec4Arg inIndex)
{
	// If inValue.z is false then shift W to Z
	UVec4 v = UVec4::sSelect(inIndex.Swizzle<SWIZZLE_X, SWIZZLE_Y, SWIZZLE_W, SWIZZLE_W>(), inIndex, inValue.SplatZ());

	// If inValue.y is false then shift Z and further to Y and further
	v = UVec4::sSelect(v.Swizzle<SWIZZLE_X, SWIZZLE_Z, SWIZZLE_W, SWIZZLE_W>(), v, inValue.SplatY());

	// If inValue.x is false then shift X and furhter to Y and furhter
	v = UVec4::sSelect(v.Swizzle<SWIZZLE_Y, SWIZZLE_Z, SWIZZLE_W, SWIZZLE_W>(), v, inValue.SplatX());

	return v;
}

UVec4 UVec4::operator * (UVec4Arg inV2) const
{
#if defined(JPH_USE_SSE4_1)
	return _mm_mullo_epi32(mValue, inV2.mValue);
#elif defined(JPH_USE_NEON)
	return vmulq_u32(mValue, inV2.mValue);
#else
	UVec4 result;
	for (int i = 0; i < 4; i++)
		result.mU32[i] = mU32[i] * inV2.mU32[i];
	return result;
#endif
}

UVec4 UVec4::operator + (UVec4Arg inV2)
{
#if defined(JPH_USE_SSE)
	return _mm_add_epi32(mValue, inV2.mValue);
#elif defined(JPH_USE_NEON)
	return vaddq_u32(mValue, inV2.mValue);
#else
    return { mValue.x + inV2.mValue.x, mValue.y + inV2.mValue.y, mValue.z + inV2.mValue.z, mValue.w + inV2.mValue.w };
#endif
}

UVec4 &UVec4::operator += (UVec4Arg inV2)
{
#if defined(JPH_USE_SSE)
	mValue = _mm_add_epi32(mValue, inV2.mValue);
#elif defined(JPH_USE_NEON)
	mValue = vaddq_u32(mValue, inV2.mValue);
#else
    mValue = { mValue.x + inV2.mValue.x, mValue.y + inV2.mValue.y, mValue.z + inV2.mValue.z, mValue.w + inV2.mValue.w };
#endif
	return *this;
}

UVec4 UVec4::SplatX() const
{
#if defined(JPH_USE_SSE)
	return _mm_shuffle_epi32(mValue, _MM_SHUFFLE(0, 0, 0, 0));
#elif defined(JPH_USE_NEON)
	return vdupq_laneq_u32(mValue, 0);
#else
    return { mValue.x, mValue.x, mValue.x, mValue.x };
#endif
}

UVec4 UVec4::SplatY() const
{
#if defined(JPH_USE_SSE)
	return _mm_shuffle_epi32(mValue, _MM_SHUFFLE(1, 1, 1, 1));
#elif defined(JPH_USE_NEON)
	return vdupq_laneq_u32(mValue, 1);
#else
    return { mValue.y, mValue.y, mValue.y, mValue.y };
#endif
}

UVec4 UVec4::SplatZ() const
{
#if defined(JPH_USE_SSE)
	return _mm_shuffle_epi32(mValue, _MM_SHUFFLE(2, 2, 2, 2));
#elif defined(JPH_USE_NEON)
	return vdupq_laneq_u32(mValue, 2);
#else
    return { mValue.z, mValue.z, mValue.z, mValue.z };
#endif
}

UVec4 UVec4::SplatW() const
{
#if defined(JPH_USE_SSE)
	return _mm_shuffle_epi32(mValue, _MM_SHUFFLE(3, 3, 3, 3));
#elif defined(JPH_USE_NEON)
	return vdupq_laneq_u32(mValue, 3);
#else
    return { mValue.w, mValue.w, mValue.w, mValue.w };
#endif
}

Vec4 UVec4::ToFloat() const
{
#if defined(JPH_USE_SSE)
	return _mm_cvtepi32_ps(mValue);
#elif defined(JPH_USE_NEON)
	return vcvtq_f32_s32(mValue);
#else
    return { static_cast<float>(mValue.x), static_cast<float>(mValue.y), static_cast<float>(mValue.z), static_cast<float>(mValue.w) };
#endif
}

Vec4 UVec4::ReinterpretAsFloat() const
{
#if defined(JPH_USE_SSE)
	return Vec4(_mm_castsi128_ps(mValue));
#elif defined(JPH_USE_NEON)
	return vreinterpretq_f32_s32(mValue);
#else
    return { reinterpret_cast<const float&>(mValue.x), reinterpret_cast<const float&>(mValue.y), reinterpret_cast<const float&>(mValue.z), reinterpret_cast<const float&>(mValue.w) };
#endif
}

void UVec4::StoreInt4(uint32 *outV) const
{
#if defined(JPH_USE_SSE)
	_mm_storeu_si128(reinterpret_cast<__m128i *>(outV), mValue);
#elif defined(JPH_USE_NEON)
	vst1q_u32(outV, mValue);
#else
    outV[0] = mValue.x;
    outV[1] = mValue.y;
    outV[2] = mValue.z;
    outV[3] = mValue.w;
#endif
}

void UVec4::StoreInt4Aligned(uint32 *outV) const
{
#if defined(JPH_USE_SSE)
	_mm_store_si128(reinterpret_cast<__m128i *>(outV), mValue);
#elif defined(JPH_USE_NEON)
	vst1q_u32(outV, mValue); // ARM doesn't make distinction between aligned or not
#else
    outV[0] = mValue.x;
    outV[1] = mValue.y;
    outV[2] = mValue.z;
    outV[3] = mValue.w;
#endif
}

int UVec4::CountTrues() const
{
#if defined(JPH_USE_SSE)
	return CountBits(_mm_movemask_ps(_mm_castsi128_ps(mValue)));
#elif defined(JPH_USE_NEON)
    return vaddvq_u32(vshrq_n_u32(mValue, 31));
#else
    int count = (mValue.x >> 31) & 1;
    count += (mValue.y >> 31) & 1;
    count += (mValue.z >> 31) & 1;
    count += (mValue.w >> 31) & 1;
    return count;
#endif
}

int UVec4::GetTrues() const
{
#if defined(JPH_USE_SSE)
	return _mm_movemask_ps(_mm_castsi128_ps(mValue));
#elif defined(JPH_USE_NEON)
    int32x4_t shift = { 0, 1, 2, 3 };
    return vaddvq_u32(vshlq_u32(vshrq_n_u32(mValue, 31), shift));
#else
    int res = 0;
    if (mValue.x & 1 << 31) {
        res += 0b1;
    }
    if (mValue.y & 1 << 31) {
        res += 0b10;
    }
    if (mValue.z & 1 << 31) {
        res += 0b100;
    }
    if (mValue.w & 1 << 31) {
        res += 0b1000;
    }
    return res;
#endif
}

bool UVec4::TestAnyTrue() const
{
	return GetTrues() != 0;
}

bool UVec4::TestAnyXYZTrue() const
{
	return (GetTrues() & 0b111) != 0;
}

bool UVec4::TestAllTrue() const
{
	return GetTrues() == 0b1111;
}

bool UVec4::TestAllXYZTrue() const
{
	return (GetTrues() & 0b111) == 0b111;
}

template <const uint Count>
UVec4 UVec4::LogicalShiftLeft() const
{
	static_assert(Count <= 31, "Invalid shift");

#if defined(JPH_USE_SSE)
	return _mm_slli_epi32(mValue, Count);
#elif defined(JPH_USE_NEON)
	return vshlq_n_u32(mValue, Count);
#else
    return { mValue.x << Count, mValue.y << Count, mValue.z << Count, mValue.w << Count };
#endif
}

template <const uint Count>
UVec4 UVec4::LogicalShiftRight() const
{
	static_assert(Count <= 31, "Invalid shift");

#if defined(JPH_USE_SSE)
	return _mm_srli_epi32(mValue, Count);
#elif defined(JPH_USE_NEON)
	return vshrq_n_u32(mValue, Count);
#else
    return { mValue.x >> Count, mValue.y >> Count, mValue.z >> Count, mValue.w >> Count };
#endif
}

template <const uint Count>
UVec4 UVec4::ArithmeticShiftRight() const
{
	static_assert(Count <= 31, "Invalid shift");

#if defined(JPH_USE_SSE)
	return _mm_srai_epi32(mValue, Count);
#elif defined(JPH_USE_NEON)
	return vshrq_n_s32(mValue, Count);
#else
    return {
		mValue.x & (1 << 31) ? ~(~mValue.x >> Count) : mValue.x >> Count,
		mValue.y & (1 << 31) ? ~(~mValue.y >> Count) : mValue.y >> Count,
		mValue.z & (1 << 31) ? ~(~mValue.z >> Count) : mValue.z >> Count,
		mValue.w & (1 << 31) ? ~(~mValue.w >> Count) : mValue.w >> Count
    };
#endif
}

UVec4 UVec4::Expand4Uint16Lo() const
{
#if defined(JPH_USE_SSE)
	return _mm_unpacklo_epi16(mValue, _mm_castps_si128(_mm_setzero_ps()));
#elif defined(JPH_USE_NEON)
	int16x4_t value = vget_low_s16(mValue);
	int16x4_t zero = vdup_n_s16(0);
	return vcombine_s16(vzip1_s16(value, zero), vzip2_s16(value, zero));
#else
    return {
        mValue.x & 0xFFFF,
        mValue.x >> 16,
        mValue.y & 0xFFFF,
        mValue.y >> 16,
    };
#endif
}

UVec4 UVec4::Expand4Uint16Hi() const
{
#if defined(JPH_USE_SSE)
	return _mm_unpackhi_epi16(mValue, _mm_castps_si128(_mm_setzero_ps()));
#elif defined(JPH_USE_NEON)
	int16x4_t value = vget_high_s16(mValue);
	int16x4_t zero = vdup_n_s16(0);
	return vcombine_s16(vzip1_s16(value, zero), vzip2_s16(value, zero));
#else
    return {
        mValue.z & 0xFFFF,
        mValue.z >> 16,
        mValue.w & 0xFFFF,
        mValue.w >> 16,
    };
#endif
}

UVec4 UVec4::Expand4Byte0() const
{
#if defined(JPH_USE_SSE4_1)
	return _mm_shuffle_epi8(mValue, _mm_set_epi32(int(0xffffff03), int(0xffffff02), int(0xffffff01), int(0xffffff00)));
#elif defined(JPH_USE_NEON)
	int8x16_t idx = { 0x00, 0x7f, 0x7f, 0x7f, 0x01, 0x7f, 0x7f, 0x7f, 0x02, 0x7f, 0x7f, 0x7f, 0x03, 0x7f, 0x7f, 0x7f };
	return vreinterpretq_u32_s8(vqtbl1q_s8(vreinterpretq_s8_u32(mValue), idx));
#else
	UVec4 result;
	for (int i = 0; i < 4; i++)
		result.mU32[i] = (mU32[0] >> (i * 8)) & 0xff;
	return result;
#endif
}

UVec4 UVec4::Expand4Byte4() const
{
#if defined(JPH_USE_SSE4_1)
	return _mm_shuffle_epi8(mValue, _mm_set_epi32(int(0xffffff07), int(0xffffff06), int(0xffffff05), int(0xffffff04)));
#elif defined(JPH_USE_NEON)
	int8x16_t idx = { 0x04, 0x7f, 0x7f, 0x7f, 0x05, 0x7f, 0x7f, 0x7f, 0x06, 0x7f, 0x7f, 0x7f, 0x07, 0x7f, 0x7f, 0x7f };
	return vreinterpretq_u32_s8(vqtbl1q_s8(vreinterpretq_s8_u32(mValue), idx));
#else
	UVec4 result;
	for (int i = 0; i < 4; i++)
		result.mU32[i] = (mU32[1] >> (i * 8)) & 0xff;
	return result;
#endif
}

UVec4 UVec4::Expand4Byte8() const
{
#if defined(JPH_USE_SSE4_1)
	return _mm_shuffle_epi8(mValue, _mm_set_epi32(int(0xffffff0b), int(0xffffff0a), int(0xffffff09), int(0xffffff08)));
#elif defined(JPH_USE_NEON)
	int8x16_t idx = { 0x08, 0x7f, 0x7f, 0x7f, 0x09, 0x7f, 0x7f, 0x7f, 0x0a, 0x7f, 0x7f, 0x7f, 0x0b, 0x7f, 0x7f, 0x7f };
	return vreinterpretq_u32_s8(vqtbl1q_s8(vreinterpretq_s8_u32(mValue), idx));
#else
	UVec4 result;
	for (int i = 0; i < 4; i++)
		result.mU32[i] = (mU32[2] >> (i * 8)) & 0xff;
	return result;
#endif
}

UVec4 UVec4::Expand4Byte12() const
{
#if defined(JPH_USE_SSE4_1)
	return _mm_shuffle_epi8(mValue, _mm_set_epi32(int(0xffffff0f), int(0xffffff0e), int(0xffffff0d), int(0xffffff0c)));
#elif defined(JPH_USE_NEON)
	int8x16_t idx = { 0x0c, 0x7f, 0x7f, 0x7f, 0x0d, 0x7f, 0x7f, 0x7f, 0x0e, 0x7f, 0x7f, 0x7f, 0x0f, 0x7f, 0x7f, 0x7f };
	return vreinterpretq_u32_s8(vqtbl1q_s8(vreinterpretq_s8_u32(mValue), idx));
#else
	UVec4 result;
	for (int i = 0; i < 4; i++)
		result.mU32[i] = (mU32[3] >> (i * 8)) & 0xff;
	return result;
#endif
}

UVec4 UVec4::ShiftComponents4Minus(int inCount) const
{
#if defined(JPH_USE_SSE4_1)
	return _mm_shuffle_epi8(mValue, sFourMinusXShuffle[inCount].mValue);
#elif defined(JPH_USE_NEON)
	uint8x16_t idx = vreinterpretq_u8_u32(sFourMinusXShuffle[inCount].mValue);
	return vreinterpretq_u32_s8(vqtbl1q_s8(vreinterpretq_s8_u32(mValue), idx));
#else
	UVec4 result = UVec4::sZero();
	for (int i = 0; i < inCount; i++)
		result.mU32[i] = mU32[i + 4 - inCount];
	return result;
#endif
}

JPH_NAMESPACE_END
