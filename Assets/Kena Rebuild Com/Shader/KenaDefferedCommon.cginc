#define PI 3.141593f 

//@ShadingCommon 
// SHADINGMODELID_* occupy the 4 low bits of an 8bit channel and SKIP_* occupy the 4 high bits
#define SHADINGMODELID_UNLIT				0
#define SHADINGMODELID_DEFAULT_LIT			1
#define SHADINGMODELID_SUBSURFACE			2
#define SHADINGMODELID_PREINTEGRATED_SKIN	3
#define SHADINGMODELID_CLEAR_COAT			4
#define SHADINGMODELID_SUBSURFACE_PROFILE	5
#define SHADINGMODELID_TWOSIDED_FOLIAGE		6
#define SHADINGMODELID_HAIR					7
#define SHADINGMODELID_CLOTH				8
#define SHADINGMODELID_EYE					9
#define SHADINGMODELID_SINGLELAYERWATER		10
#define SHADINGMODELID_THIN_TRANSLUCENT		11
#define SHADINGMODELID_NUM					12
#define SHADINGMODELID_MASK					0xF		// 4 bits reserved for ShadingModelID	

// The flags are defined so that 0 value has no effect!
// These occupy the 4 high bits in the same channel as the SHADINGMODELID_*
#define SKIP_CUSTOMDATA_MASK			(1 << 4)	// TODO remove. Can be inferred from shading model.
#define SKIP_PRECSHADOW_MASK			(1 << 5)
#define ZERO_PRECSHADOW_MASK			(1 << 6)
#define SKIP_VELOCITY_MASK				(1 << 7)

//@SubsurfaceProfileCommon 
// NOTE: Changing offsets below requires updating all instances of #SSSS_CONSTANTS
// TODO: This needs to be defined in a single place and shared between C++ and shaders!
#define SSSS_SUBSURFACE_COLOR_OFFSET			0
#define BSSS_SURFACEALBEDO_OFFSET               (SSSS_SUBSURFACE_COLOR_OFFSET+1)
#define BSSS_DMFP_OFFSET                        (BSSS_SURFACEALBEDO_OFFSET+1)
#define SSSS_TRANSMISSION_OFFSET				(BSSS_DMFP_OFFSET+1)
#define SSSS_BOUNDARY_COLOR_BLEED_OFFSET		(SSSS_TRANSMISSION_OFFSET+1)
#define SSSS_DUAL_SPECULAR_OFFSET				(SSSS_BOUNDARY_COLOR_BLEED_OFFSET+1)
#define SSSS_KERNEL0_OFFSET						(SSSS_DUAL_SPECULAR_OFFSET+1)
#define SSSS_KERNEL0_SIZE						13
#define SSSS_KERNEL1_OFFSET						(SSSS_KERNEL0_OFFSET + SSSS_KERNEL0_SIZE)
#define SSSS_KERNEL1_SIZE						9
#define SSSS_KERNEL2_OFFSET						(SSSS_KERNEL1_OFFSET + SSSS_KERNEL1_SIZE)
#define SSSS_KERNEL2_SIZE						6
#define SSSS_KERNEL_TOTAL_SIZE					(SSSS_KERNEL0_SIZE + SSSS_KERNEL1_SIZE + SSSS_KERNEL2_SIZE)
#define SSSS_TRANSMISSION_PROFILE_OFFSET		(SSSS_KERNEL0_OFFSET + SSSS_KERNEL_TOTAL_SIZE)
#define SSSS_TRANSMISSION_PROFILE_SIZE			32
#define BSSS_TRANSMISSION_PROFILE_OFFSET        (SSSS_TRANSMISSION_PROFILE_OFFSET + SSSS_TRANSMISSION_PROFILE_SIZE)
#define BSSS_TRANSMISSION_PROFILE_SIZE			SSSS_TRANSMISSION_PROFILE_SIZE
#define	SSSS_MAX_TRANSMISSION_PROFILE_DISTANCE	5.0f // See MaxTransmissionProfileDistance in ComputeTransmissionProfile(), SeparableSSS.cpp
#define SSSS_MAX_DUAL_SPECULAR_ROUGHNESS		2.0f

// Must match C++
#define AO_DOWNSAMPLE_FACTOR 2

//------------------Define Struct Start------------------
struct FHairTransmittanceData
{
	// Average front/back scattering for a given L, V, T (tangent)
	float3 Transmittance;
	float3 A_front;
	float3 A_back;

	float OpaqueVisibility;
	float HairCount;

	// TEMP: for fastning iteration times
	float3 LocalScattering;
	float3 GlobalScattering;

	uint ScatteringComponent;
};

struct FDeferredLightData
{
	float3 Direction;
	float4 Color;
	float3 Tangent;
	float ContactShadowLength;
	float4 ShadowMapChannelMask;
	uint ShadowedBits;
	float SourceLength;
	float SourceRadius;
	float SoftSourceRadius;
	bool bInverseSquared;
	float SpecularScale;
};

struct FGBufferData
{
	// normalized
	float3 WorldNormal;
	// normalized, only valid if GBUFFER_HAS_TANGENT
	float3 WorldTangent;
	// 0..1 (derived from BaseColor, Metalness, Specular)
	float3 DiffuseColor;
	// 0..1 (derived from BaseColor, Metalness, Specular)
	float3 SpecularColor;
	// 0..1, white for SHADINGMODELID_SUBSURFACE_PROFILE and SHADINGMODELID_EYE (apply BaseColor after scattering is more correct and less blurry)
	float3 BaseColor;
	float4 CustomData;
	float Metallic; // 0..1
	float Specular; // 0..1
	float Roughness; // 0..1
	float GBufferAO; // 0..1
	float IndirectIrradiance; // 0..1
	uint ShadingModelID; // 0..15 
	uint SelectiveOutputMask; // 0..255 
	float Anisotropy;
	// in unreal units (linear), can be used to reconstruct world position,
	// only valid when decoding the GBuffer as the value gets reconstructed from the Z buffer
	float Depth;
};
//------------------Define Struct End------------------



//------------------Per DC Com Variant Start------------------
static float FrameId = 3;
static bool bSubsurfacePostprocessEnabled = true;
static uint bCheckerboardSubsurfaceProfileRendering = 1;
static FDeferredLightData kena_LightData = (FDeferredLightData)0;

static float4 View_BufferSizeAndInvSize = float4(1708.00, 960.00, 0.00059, 0.00104);
static float4 View_ViewSizeAndInvSize = float4(1708.00, 960.00, 0.00059, 0.00104);
static float4 View_SkyLightColor = float4(4.95, 4.19202, 3.12225, 0.00);
static float4 OcclusionTintAndMinOcclusion = float4(0.04519, 0.05127, 0.02956, 0.00);
static float4 ContrastAndNormalizeMulAdd = float4(0.01, 40.00843, -19.50422, 0.70);

static float4 ReflectionStruct_SkyLightParameters = float4(7.00, 1.00, 1.00, 0.00);

//SH irradiance map 
static float4 View_SkyIrradianceEnvironmentMap[] = {
	float4(0.00226, -0.06811, 0.24557, 0.34246),
	float4(0.00125, -0.05614, 0.2917, 0.4208),
	float4(0.00028, -0.03233, 0.36868, 0.53767),
	float4(-0.01405, -0.01719, -0.07034, 0.00444),
	float4(-0.01044, -0.01305, -0.07727, 0.00333),
	float4(-0.00504, -0.00213, -0.07663, 0.00164),
	float4(-0.01606, -0.01079, -0.0033, 1.00),
};

static float4 InvDeviceZToWorldZTransform = float4(0.00, 0.00, 0.10, -1.00000E-08); //CB0[65] 对应Unity的zBufferParams  
static float4 ScreenPositionScaleBias = float4(0.49971, -0.50, 0.50, 0.49971); //CB0[66] 从NDC变换到UV空间 
static float4 CameraPosWS = float4(-58625.35547, 27567.39453, -6383.71826, 0); //世界空间中摄像机的坐标值 

//cb1_v48 ~ cb1_v51
static float4x4 Matrix_Inv_VP = float4x4(
	float4(0.7495,			0.11887,	-0.5012,		-58625.35547),
	float4(-0.49857,		0.1787,		-0.75428,		27567.39453),
	float4(-2.68273E-08,	0.4585,		0.42411,		-6383.71826),
	float4(0,				0,			0,				1.00)
);

//------------------Per DC Com Variant End------------------



//------------------Declare Buffer Start------------------
TEXTURE2D_X_FLOAT(_Depth); SAMPLER(sampler_Depth);
TEXTURE2D(_Normal); SAMPLER(sampler_Normal);
TEXTURE2D(_Comp_M_D_R_F); SAMPLER(sampler_Comp_M_D_R_F);
TEXTURE2D(_Albedo); SAMPLER(sampler_Albedo);
TEXTURE2D(_Comp_F_R_X_I); SAMPLER(sampler_Comp_F_R_X_I);
TEXTURE2D(_SSAO); SAMPLER(sampler_SSAO);

TEXTURECUBE(_IBL); SAMPLER(sampler_IBL);
TEXTURECUBE(_Sky); SAMPLER(sampler_Sky);
TEXTURECUBE(_SkyLightBlend); SAMPLER(sampler_SkyLightBlend);
//------------------Declare Buffer End------------------



//------------------Math Lib Start------------------
#if 1 
static float acos(float a) {
    float a2 = a * a;   // a squared
    float a3 = a * a2;  // a cubed
    if (a >= 0) {
        return (float)sqrt(1.0 - a) * (1.5707288 - 0.2121144 * a + 0.0742610 * a2 - 0.0187293 * a3);
    }
    return 3.14159265358979323846
        - (float)sqrt(1.0 + a) * (1.5707288 + 0.2121144 * a + 0.0742610 * a2 + 0.0187293 * a3);
}

static float asin(float a) {
    float a2 = a * a;   // a squared
    float a3 = a * a2;  // a cubed
    if (a >= 0) {
        return 1.5707963267948966
            - (float)sqrt(1.0 - a) * (1.5707288 - 0.2121144 * a + 0.0742610 * a2 - 0.0187293 * a3);
    }
    return -1.5707963267948966 + (float)sqrt(1.0 + a) * (1.5707288 + 0.2121144 * a + 0.0742610 * a2 + 0.0187293 * a3);
}

// Relative error : < 0.7% over full
// Precise format : ~small float
// 1 ALU
float sqrtFast(float x)
{
	int i = asint(x);
	i = 0x1FBD1DF5 + (i >> 1);
	return asfloat(i);
}

// max absolute error 9.0x10^-3
// Eberly's polynomial degree 1 - respect bounds
// 4 VGPR, 12 FR (8 FR, 1 QR), 1 scalar
// input [-1, 1] and output [0, PI]
float acosFast(float inX)
{
	float x = abs(inX);
	float res = -0.156583f * x + (0.5 * PI);
	res *= sqrt(1.0f - x);
	return (inX >= 0) ? res : PI - res;
}

// Same cost as acosFast + 1 FR
// Same error
// input [-1, 1] and output [-PI/2, PI/2]
float asinFast(float x)
{
	return (0.5 * PI) - acosFast(x);
}

inline float Pow2(float a)
{
    return a * a;
}

inline float3 Pow2(float3 x)
{
    return x * x;
}

inline float Pow5(float x)
{
    float xx = x * x;
    return xx * xx * x;
}
#endif 
//------------------Math Lib End------------------



//------------------Utility Start------------------
#if 1
float Luminance(float3 aColor)
{
    return dot(aColor, float3(0.3, 0.59, 0.11));
}

float DielectricSpecularToF0(float Specular)
{
	return 0.08f * Specular;
}

float3 ComputeF0(float Specular, float3 BaseColor, float Metallic)
{
	return lerp(DielectricSpecularToF0(Specular).xxx, BaseColor, Metallic.xxx);
}

float3 DecodeNormal(float3 N)
{
    return N * 2 - 1;
}

uint DecodeShadingModelId(float InPackedChannel)
{
    return ((uint)round(InPackedChannel * (float)0xFF)) & SHADINGMODELID_MASK;
}

uint DecodeSelectiveOutputMask(float InPackedChannel)
{
    return ((uint)round(InPackedChannel * (float)0xFF)) & (~SHADINGMODELID_MASK);
}

float ConvertFromDeviceZ(float DeviceZ)
{
	// Supports ortho and perspective, see CreateInvDeviceZToWorldZTransform()
	return DeviceZ * InvDeviceZToWorldZTransform[0] + InvDeviceZToWorldZTransform[1] + 1.0f / (DeviceZ * InvDeviceZToWorldZTransform[2] - InvDeviceZToWorldZTransform[3]);
}

bool CheckerFromSceneColorUV(float2 UVSceneColor)
{
	// relative to left top of the rendertarget (not viewport)
	uint2 PixelPos = uint2(UVSceneColor * View_BufferSizeAndInvSize.xy);
	uint TemporalAASampleIndex = 3;
	return (PixelPos.x + PixelPos.y + TemporalAASampleIndex) & 1;
}

float3 ExtractSubsurfaceColor(FGBufferData BufferData)
{
	return Pow2(BufferData.CustomData.yzw);
}

uint ExtractSubsurfaceProfileInt(FGBufferData BufferData)
{
	// can be optimized
	return uint(BufferData.CustomData.y * 255 + 0.5f);
}

float ApproximateConeConeIntersection(float ArcLength0, float ArcLength1, float AngleBetweenCones)
{
	float AngleDifference = abs(ArcLength0 - ArcLength1);

	float Intersection = smoothstep(
		0,
		1.0,
		1.0 - saturate((AngleBetweenCones - AngleDifference) / (ArcLength0 + ArcLength1 - AngleDifference)));

	return Intersection;
}

#endif 
//------------------Utility End------------------



//------------------Gbuffer Start------------------
#if 1
bool UseSubsurfaceProfile(int ShadingModel)
{
	return ShadingModel == SHADINGMODELID_SUBSURFACE_PROFILE || ShadingModel == SHADINGMODELID_EYE;
}

void AdjustBaseColorAndSpecularColorForSubsurfaceProfileLighting(inout float3 BaseColor, inout float3 SpecularColor, inout float Specular, bool bChecker)
{
	// because we adjust the BaseColor here, we need StoredBaseColor
	BaseColor = bSubsurfacePostprocessEnabled ? float3(1, 1, 1) : BaseColor;
	// we apply the base color later in SubsurfaceRecombinePS()
	BaseColor = bChecker;
	// in SubsurfaceRecombinePS() does not multiply with Specular so we do it here
	SpecularColor *= !bChecker;
	Specular *= !bChecker;
}

FGBufferData DecodeGBufferData(float3 Normal_Raw, float4 Albedo_Raw, float4 Comp_M_D_R_F_Raw,
	float4 Comp_F_R_X_I_Raw, float4 ShadowTex_Raw, float SceneDepth, bool bChecker)
{
	FGBufferData GBuffer = (FGBufferData)0;

	GBuffer.WorldNormal = normalize(DecodeNormal(Normal_Raw));
	GBuffer.Metallic = Comp_M_D_R_F_Raw.r;
	GBuffer.Specular = Comp_M_D_R_F_Raw.g;
	GBuffer.Roughness = Comp_M_D_R_F_Raw.b;

	GBuffer.ShadingModelID = DecodeShadingModelId(Comp_M_D_R_F_Raw.a);
	GBuffer.SelectiveOutputMask = DecodeSelectiveOutputMask(Comp_M_D_R_F_Raw.a);

	GBuffer.BaseColor = Albedo_Raw.rgb;

	GBuffer.GBufferAO = Albedo_Raw.a; //非 static_lighting 模式下，使用传入的a通道作为 GBufferAO 
	GBuffer.IndirectIrradiance = 1;   //环境光强没有波动 

	GBuffer.Anisotropy = 0;   //不带有GBuffer Tangent的话，这里总是0 

	//GBuffer.CustomDepth = 1; 
	GBuffer.Depth = SceneDepth;

	//Kena里只有木+墙部分激活了 Skip_CustomData，其余部分均需要用到 Comp_F_R_X_I_Raw 这样用户定义的纹理和对应逻辑 
	GBuffer.CustomData = (!(GBuffer.SelectiveOutputMask & SKIP_CUSTOMDATA_MASK)) ? Comp_F_R_X_I_Raw.wxyz : float4(0, 0, 0, 0);

	UNITY_FLATTEN
	if (GBuffer.ShadingModelID == SHADINGMODELID_EYE)
	{
		GBuffer.Metallic = 0.0;
	}

	// derived from BaseColor, Metalness, Specular
	{
		GBuffer.SpecularColor = ComputeF0(GBuffer.Specular, GBuffer.BaseColor, GBuffer.Metallic);

		if (UseSubsurfaceProfile(GBuffer.ShadingModelID)) //对皮肤和眼睛来说，会进入此分支 
		{
			AdjustBaseColorAndSpecularColorForSubsurfaceProfileLighting(GBuffer.BaseColor,
				GBuffer.SpecularColor, GBuffer.Specular, bChecker);
		}

		GBuffer.DiffuseColor = GBuffer.BaseColor - GBuffer.BaseColor * GBuffer.Metallic;
	}

	return GBuffer;
}

#endif 
//------------------Gbuffer End------------------



//------------------HairShading Start------------------
#if 1
float Hair_g(float B, float Theta)
{
	return exp(-0.5 * Pow2(Theta) / (B * B)) / (sqrt(2 * PI) * B);
}

float Hair_F(float CosTheta)
{
	const float n = 1.55;
	const float F0 = Pow2((1 - n) / (1 + n));
	return F0 + (1 - F0) * Pow5(1 - CosTheta);
}

float3 KajiyaKayDiffuseAttenuation(FGBufferData GBuffer, float3 L, float3 Vp, half3 N, float Shadow)
{
	// Use soft Kajiya Kay diffuse attenuation
	float KajiyaDiffuse = 1 - abs(dot(N, L));

	float3 FakeNormal = normalize(Vp);

	N = FakeNormal;

	// Hack approximation for multiple scattering.
	float Wrap = 1;
	float NoL = saturate((dot(N, L) + Wrap) / Pow2(1 + Wrap));
	float DiffuseScatter = (1 / PI) * lerp(NoL, KajiyaDiffuse, 0.33) * GBuffer.Metallic;
	float Luma = Luminance(GBuffer.BaseColor);
	float3 ScatterTint = pow(GBuffer.BaseColor / Luma, 1 - Shadow);
	return sqrt(GBuffer.BaseColor) * DiffuseScatter * ScatterTint;
}

float3 HairShading(FGBufferData GBuffer, float3 L, float3 V, half3 N, float Shadow, FHairTransmittanceData HairTransmittance, float Backlit, float Area, uint2 Random, bool bEvalMultiScatter)
{
	float ClampedRoughness = clamp(GBuffer.Roughness, 1 / 255.0f, 1.0f);

	const float VoL = dot(V, L);
	const float SinThetaL = dot(N, L);
	const float SinThetaV = dot(N, V);
	float CosThetaD = cos(0.5 * abs(asinFast(SinThetaV) - asinFast(SinThetaL)));

	const float3 Lp = L - SinThetaL * N;
	const float3 Vp = V - SinThetaV * N;
	const float CosPhi = dot(Lp, Vp) * rsqrt(dot(Lp, Lp) * dot(Vp, Vp) + 1e-4);
	const float CosHalfPhi = sqrt(saturate(0.5 + 0.5 * CosPhi));

	float n = 1.55;

	float n_prime = 1.19 / CosThetaD + 0.36 * CosThetaD;

	float Shift = 0.035;
	float Alpha[] =
	{
		-Shift * 2,
		Shift,
		Shift * 4,
	};
	float B[] =
	{
		Area + Pow2(ClampedRoughness),
		Area + Pow2(ClampedRoughness) / 2,
		Area + Pow2(ClampedRoughness) * 2,
	};

	float3 S = 0;

	//R
	{
		const float sa = sin(Alpha[0]);
		const float ca = cos(Alpha[0]);
		float Shift = 2 * sa * (ca * CosHalfPhi * sqrt(1 - SinThetaV * SinThetaV) + sa * SinThetaV);

		float Mp = Hair_g(B[0] * sqrt(2.0) * CosHalfPhi, SinThetaL + SinThetaV - Shift);
		float Np = 0.25 * CosHalfPhi;
		float Fp = Hair_F(sqrt(saturate(0.5 + 0.5 * VoL)));
		S += Mp * Np * Fp * (GBuffer.Specular * 2) * lerp(1, Backlit, saturate(-VoL));
	}

	// TT
	{
		float Mp = Hair_g(B[1], SinThetaL + SinThetaV - Alpha[1]);

		float a = 1 / n_prime;

		float h = CosHalfPhi * (1 + a * (0.6 - 0.8 * CosPhi));

		float f = Hair_F(CosThetaD * sqrt(saturate(1 - h * h)));
		float Fp = Pow2(1 - f);

		float3 Tp = pow(GBuffer.BaseColor, 0.5 * sqrt(1 - Pow2(h * a)) / CosThetaD);

		float Np = exp(-3.65 * CosPhi - 3.98);

		S += Mp * Np * Fp * Tp * Backlit;
	}

	// TRT
	{
		float Mp = Hair_g(B[2], SinThetaL + SinThetaV - Alpha[2]);

		float f = Hair_F(CosThetaD * 0.5);
		float Fp = Pow2(1 - f) * f;

		float3 Tp = pow(GBuffer.BaseColor, 0.8 / CosThetaD);

		float Np = exp(17 * CosPhi - 16.78);

		S += Mp * Np * Fp * Tp;
	}

	S += KajiyaKayDiffuseAttenuation(GBuffer, L, Vp, N, Shadow);

	S = -min(-S, 0.0);

	return S;
}
#endif
//------------------HairShading End------------------



//------------------Reflection Share Start------------------
#if 1
#define REFLECTION_CAPTURE_ROUGHEST_MIP 1
#define REFLECTION_CAPTURE_ROUGHNESS_MIP_SCALE 1.2

half ComputeReflectionCaptureMipFromRoughness(half Roughness, half CubemapMaxMip)
{
	// Heuristic that maps roughness to mip level
	// This is done in a way such that a certain mip level will always have the same roughness, regardless of how many mips are in the texture
	// Using more mips in the cubemap just allows sharper reflections to be supported
	half LevelFrom1x1 = REFLECTION_CAPTURE_ROUGHEST_MIP - REFLECTION_CAPTURE_ROUGHNESS_MIP_SCALE * log2(Roughness);
	return CubemapMaxMip - 1 - LevelFrom1x1;
}

float3 GetSkyLightReflection(float3 ReflectionVector, float Roughness)
{
	float AbsoluteSpecularMip = ComputeReflectionCaptureMipFromRoughness(Roughness, ReflectionStruct_SkyLightParameters.x);
	//float3 Reflection = TextureCubeSampleLevel(ReflectionStruct.SkyLightCubemap, ReflectionStruct.SkyLightCubemapSampler, ReflectionVector, AbsoluteSpecularMip).rgb;
	half3 Reflection = SAMPLE_TEXTURECUBE_LOD(_Sky, sampler_Sky, ReflectionVector, AbsoluteSpecularMip).rgb;

	return Reflection * View_SkyLightColor.rgb;
}

float3 GetSkyLightReflectionSupportingBlend(float3 ReflectionVector, float Roughness)
{
	float3 Reflection = GetSkyLightReflection(ReflectionVector, Roughness);
	UNITY_BRANCH
	if (ReflectionStruct_SkyLightParameters.w > 0)
	{
		float AbsoluteSpecularMip = ComputeReflectionCaptureMipFromRoughness(Roughness, ReflectionStruct_SkyLightParameters.x);
		float3 BlendDestinationReflection = SAMPLE_TEXTURECUBE_LOD(_SkyLightBlend, sampler_SkyLightBlend, ReflectionVector, AbsoluteSpecularMip).rgb;
		Reflection = lerp(Reflection, BlendDestinationReflection * View_SkyLightColor.rgb, ReflectionStruct_SkyLightParameters.w);
	}
	return Reflection;
}

float3 GetLookupVectorForSphereCapture(float3 ReflectionVector, float3 WorldPosition,
	float4 SphereCapturePositionAndRadius, float NormalizedDistanceToCapture,
	float3 LocalCaptureOffset, inout float DistanceAlpha)
{
	float3 ProjectedCaptureVector = ReflectionVector;
	float ProjectionSphereRadius = SphereCapturePositionAndRadius.w;
	float SphereRadiusSquared = ProjectionSphereRadius * ProjectionSphereRadius;

	float3 LocalPosition = WorldPosition - SphereCapturePositionAndRadius.xyz;
	float LocalPositionSqr = dot(LocalPosition, LocalPosition);

	// Find the intersection between the ray along the reflection vector and the capture's sphere
	float3 QuadraticCoef = 0;
	QuadraticCoef.x = 1;
	QuadraticCoef.y = dot(ReflectionVector, LocalPosition);
	QuadraticCoef.z = LocalPositionSqr - SphereRadiusSquared;

	float Determinant = QuadraticCoef.y * QuadraticCoef.y - QuadraticCoef.z;

	// Only continue if the ray intersects the sphere
	UNITY_FLATTEN
	if (Determinant >= 0)
	{
		float FarIntersection = sqrt(Determinant) - QuadraticCoef.y;

		float3 LocalIntersectionPosition = LocalPosition + FarIntersection * ReflectionVector;
		ProjectedCaptureVector = LocalIntersectionPosition - LocalCaptureOffset;
		// Note: some compilers don't handle smoothstep min > max (this was 1, .6)
		//DistanceAlpha = 1.0 - smoothstep(.6, 1, NormalizedDistanceToCapture);

		float x = saturate(2.5 * NormalizedDistanceToCapture - 1.5);
		DistanceAlpha = 1 - x * x * (3 - 2 * x);
	}
	return ProjectedCaptureVector;
}

#endif
//------------------Reflection Share End------------------