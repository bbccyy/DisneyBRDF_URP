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

static float4 InvDeviceZToWorldZTransform = float4(0.00, 0.00, 0.10, -1.00000E-08); //CB0[65] ��ӦUnity��zBufferParams  
static float4 ScreenPositionScaleBias = float4(0.49971, -0.50, 0.50, 0.49971); //CB0[66] ��NDC�任��UV�ռ� 
static float4 CameraPosWS = float4(-58625.35547, 27567.39453, -6383.71826, 0); //����ռ��������������ֵ 

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

	GBuffer.GBufferAO = Albedo_Raw.a; //�� static_lighting ģʽ�£�ʹ�ô����aͨ����Ϊ GBufferAO 
	GBuffer.IndirectIrradiance = 1;   //������ǿû�в��� 

	GBuffer.Anisotropy = 0;   //������GBuffer Tangent�Ļ�����������0 

	//GBuffer.CustomDepth = 1; 
	GBuffer.Depth = SceneDepth;

	//Kena��ֻ��ľ+ǽ���ּ����� Skip_CustomData�����ಿ�־���Ҫ�õ� Comp_F_R_X_I_Raw �����û�����������Ͷ�Ӧ�߼� 
	GBuffer.CustomData = (!(GBuffer.SelectiveOutputMask & SKIP_CUSTOMDATA_MASK)) ? Comp_F_R_X_I_Raw.wxyz : float4(0, 0, 0, 0);

	UNITY_FLATTEN
	if (GBuffer.ShadingModelID == SHADINGMODELID_EYE)
	{
		GBuffer.Metallic = 0.0;
	}

	// derived from BaseColor, Metalness, Specular
	{
		GBuffer.SpecularColor = ComputeF0(GBuffer.Specular, GBuffer.BaseColor, GBuffer.Metallic);

		if (UseSubsurfaceProfile(GBuffer.ShadingModelID)) //��Ƥ�����۾���˵�������˷�֧ 
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