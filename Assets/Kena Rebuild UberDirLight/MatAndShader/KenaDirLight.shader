﻿Shader "Kena/KenaDirLight"
{
	Properties
	{
		[NoScaleOffset] _SSS("SSS", 2D)						= "white" {}
		[NoScaleOffset] _Depth("Depth", 2D)					= "white" {}
		[NoScaleOffset] _Normal("Normal", 2D)				= "white" {}
		[NoScaleOffset] _Comp_M_D_R_F("Comp_M_D_R_F", 2D)	= "white" {}
		[NoScaleOffset] _Albedo("Albedo", 2D)				= "white" {}
		[NoScaleOffset] _Comp_F_R_X_I("Comp_F_R_X_I", 2D)	= "white" {}
		[NoScaleOffset] _SSAO("SSAO", 2D)					= "white" {}
		[NoScaleOffset] _ShadowTex("ShadowTex", 2D)			= "white" {}
		[NoScaleOffset] _LUT("LUT", 2D)						= "white" {}
	}

	SubShader
	{
		Tags {"RenderType"="Opaque"}
		LOD 100

		Pass
		{
			HLSLPROGRAM

			#pragma vertex vert
			#pragma fragment frag
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#define _pi 3.141593f 

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

			struct appdata
			{
				float4 positionOS	: POSITION;
				float2 uv			: TEXCOORD0;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct v2f
			{
				float4 vertex		: SV_POSITION;
				float2 uv			: TEXCOORD0;
				float3 viewDirWS	: TEXCOORD1;
				UNITY_VERTEX_OUTPUT_STEREO
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
				float Metallic; // 0..1
				float Specular; // 0..1
				float Roughness;
				uint ShadingModelID;
				float Depth;
			};

			TEXTURE2D(_SSS); SAMPLER(sampler_SSS);
			TEXTURE2D(_Depth); SAMPLER(sampler_Depth);
			TEXTURE2D(_Normal); SAMPLER(sampler_Normal);
			TEXTURE2D(_Comp_M_D_R_F); SAMPLER(sampler_Comp_M_D_R_F);
			TEXTURE2D(_Albedo); SAMPLER(sampler_Albedo);
			TEXTURE2D(_Comp_F_R_X_I); SAMPLER(sampler_Comp_F_R_X_I);
			TEXTURE2D(_SSAO); SAMPLER(sampler_SSAO);
			TEXTURE2D(_ShadowTex); SAMPLER(sampler_ShadowTex);
			TEXTURE2D(_LUT); SAMPLER(sampler_LUT);


			static float FrameId = 3; 
			const static float LightData_ShadowedBits = 3;
			const static float LightData_ContactShadowLength = 0.2;
			static float4 screen_param = float4(1707, 960, 0.00059, 0.00104); 
			static float3 light_direction = float3(0.51555, -0.29836, 0.80324); //光方向(指向光源) 
			static float4 LightData_ShadowMapChannelMask = float4(0,0,0,0);
			static float4 InvDeviceZToWorldZTransform = float4(0.00, 0.00, 0.10, -1.00000E-08); //CB0[65] 对应Unity的zBufferParams  
			static float4 ScreenPositionScaleBias = float4(0.49971, -0.50, 0.50, 0.49971); //CB0[66] 从NDC变换到UV空间 
			static float4 CameraPosWS = float4(-58625.35547, 27567.39453, -6383.71826, 0); //世界空间中摄像机的坐标值 
			static float4x4 Matrix_VP = float4x4(
				float4(0.9252,		-0.61489,	-0.00021,	0.00),
				float4(0.46399,		0.69752,	1.78886,	0.00),
				float4(0.00,		0.00,		0.00,		10.00),
				float4(-0.50162,	-0.75408,	0.42396,	0.00)
				);
			static float3x3 Matrix_Inv_VP = float3x3(
				float3(0.7495,			0.11887,	-0.5012),
				float3(-0.49857,		0.1787,		-0.75428),
				float3(-2.68273E-08,	0.4585,		0.42411)
				);
			static float4x4 Matrix_Inv_P = float4x4(			//CB0[36] ~ CB0[39]
				float4(0.90018, 0,			0,		0.00045	),
				float4(0,	    0.50625,	0,		0.00017	),
				float4(0,		0,			0,		1		),
				float4(0,		0,			0.10,	0		)
				);
			static float4x4 Matrix_P = float4x4(				//CB0[32] ~ CB0[35]
				float4(1.11089,		0,			0,		0),
				float4(0,			1.97531,	0,		0),
				float4(0,			0,			0,		10),
				float4(0,			0,			1,		0)
				);


			bool CheckerFromSceneColorUV(float2 UVSceneColor)
			{
				// relative to left top of the rendertarget (not viewport)
				uint2 PixelPos = uint2(UVSceneColor * screen_param.xy);
				uint TemporalAASampleIndex = 3; 
				return (PixelPos.x + PixelPos.y + TemporalAASampleIndex) & 1;
			}

			uint DecodeShadingModelId(float InPackedChannel)
			{
				return ((uint)round(InPackedChannel * (float)0xFF)) & SHADINGMODELID_MASK;
			}

			float ConvertFromDeviceZ(float DeviceZ)
			{
				// Supports ortho and perspective, see CreateInvDeviceZToWorldZTransform()
				return DeviceZ * InvDeviceZToWorldZTransform[0] + InvDeviceZToWorldZTransform[1] + 1.0f / (DeviceZ * InvDeviceZToWorldZTransform[2] - InvDeviceZToWorldZTransform[3]);
			}

			FGBufferData DecodeGBufferData(float3 Normal_Raw, float4 Albedo_Raw, float4 Comp_M_D_R_F_Raw, float4 Comp_F_R_X_I_Raw, float4 ShadowTex_Raw, float SceneDepth)
			{
				FGBufferData Out = (FGBufferData)0;




				return Out;
			}

			FGBufferData GetGBufferData(float2 UV, bool bGetNormalizedNormal = true)
			{
				FGBufferData Out = (FGBufferData)0;
				float DeviceZ = SAMPLE_TEXTURE2D(_Depth, sampler_Depth, UV).r;
				float3 Normal_Raw = SAMPLE_TEXTURE2D(_Normal, sampler_Normal, UV).xyz;
				float4 Albedo_Raw = SAMPLE_TEXTURE2D(_Albedo, sampler_Albedo, UV).xyzw;
				float4 Comp_M_D_R_F_Raw = SAMPLE_TEXTURE2D(_Comp_M_D_R_F, sampler_Comp_M_D_R_F, UV).xyzw;
				float4 Comp_F_R_X_I_Raw = SAMPLE_TEXTURE2D(_Comp_F_R_X_I, sampler_Comp_F_R_X_I, UV).xyzw;
				float4 ShadowTex_Raw = SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, UV).xyzw;

				float SceneDepth = ConvertFromDeviceZ(DeviceZ);

				return DecodeGBufferData(Normal_Raw, Albedo_Raw, Comp_M_D_R_F_Raw, Comp_F_R_X_I_Raw, ShadowTex_Raw, SceneDepth);
			}

			float InterleavedGradientNoise(float2 uv, float frameId)
			{
				uv += frameId * float2(32.665f, 11.815f);
				const float3 magic = float3(0.06711056f, 0.00583715f, 52.9829189f);
				return frac(magic.z * frac(dot(uv, magic.xy)));
			}

			/** Returns 0 for positions closer than the fade near distance from the camera, and 1 for positions further than the fade far distance. */
			float DistanceFromCameraFade(float SceneDepth)
			{
				float2 LightData_DistanceFadeMAD = float2(0.00003, -9); 
				// depth (non radial) based fading over distance
				float Fade = saturate(SceneDepth * LightData_DistanceFadeMAD.x + LightData_DistanceFadeMAD.y);
				return Fade * Fade;
			}

			float4 GetPerPixelLightAttenuation(float2 UV)
			{
				float4 raw_light_atten = SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, UV).xyzw;
				return raw_light_atten * raw_light_atten;
			}

			float ShadowRayCast(float3 RayOriginTranslatedWorld, float3 RayDirection,
				float RayLength, int NumSteps, float StepOffset)
			{
				float4 RayStartClip = mul(Matrix_VP, float4(RayOriginTranslatedWorld.xyz, 1));
				float4 RayDirClip = mul(Matrix_VP, float4(RayDirection.xyz * RayLength, 0));
				float4 RayEndClip = RayStartClip + RayDirClip;

				float3 RayStartScreen = RayStartClip.xyz / RayStartClip.w;
				float3 RayEndScreen = RayEndClip.xyz / RayEndClip.w;

				float3 RayStepScreen = RayEndScreen - RayStartScreen;

				float3 RayStartUVz = float3(RayStartScreen.xy * ScreenPositionScaleBias.xy + ScreenPositionScaleBias.zw, RayStartScreen.z);
				float3 RayStepUVz = float3(RayStepScreen.xy * ScreenPositionScaleBias.xy, RayStepScreen.z); //处理朝向无需平移 

				float4 RayDepthClip = RayStartClip + mul(Matrix_P, float4(0, 0, RayLength, 0));
				float3 RayDepthScreen = RayDepthClip.xyz / RayDepthClip.w;

				const float Step = 1.0 / NumSteps;

				const float CompareTolerance = abs(RayDepthScreen.z - RayStartScreen.z) * Step * 2;

				//在相邻的一块屏幕像素区域内，StepOffset彼此不同
				//可用于消除采样误差导致的Alias -> AKA Morie pattern 
				float SampleTime = StepOffset * Step + Step; 

				float FirstHitTime = -1.0;

				UNITY_UNROLL
				for (int i = 0; i < NumSteps; i++)
				{
					float3 SampleUVz = RayStartUVz + RayStepUVz * SampleTime;

					//TODO: 判断是否 DeviceZ == NDC.z， 已知 DeviceZ 近处数值大，远处数值小 
					float DeviceZ = SAMPLE_TEXTURE2D(_Depth, sampler_Depth, SampleUVz.xy).r; 

					float DepthDiff = SampleUVz.z - DeviceZ; //采样光线深度 - 采样点实际深度 

					//当DepthDiff落在(-2*CompareTolerance, 0)区间时，Hit成立 
					bool Hit = abs(DepthDiff + CompareTolerance) < CompareTolerance; 

					//负责记录第一次集中时的位置偏移，如果没击中任何物体，FirstHitTime 始终等于 -1 
					FirstHitTime = (Hit && FirstHitTime < 0.0) ? SampleTime : FirstHitTime; 

					SampleTime += Step; //步进一下 
				}

				float Shadow = FirstHitTime > 0.0 ? 1.0 : 0.0;

				float2 Vignette = max(6.0 * abs(RayStartScreen.xy + RayStepScreen.xy * FirstHitTime) - 5.0, 0.0);
				Shadow *= saturate(1.0 - dot(Vignette, Vignette));

				return 1 - Shadow;
			}


			v2f vert(appdata IN)
			{
				v2f OUT = (v2f)0;
				UNITY_SETUP_INSTANCE_ID(IN);
				//OUT.uv = (IN.uv * screen_param.xy) * screen_param.zw;
				OUT.uv = IN.uv;
				OUT.vertex = TransformObjectToHClip(IN.positionOS);

				float2 ndc_xy = IN.uv * 2 - 1;  //放到[-1,1]区间 
				ndc_xy = ndc_xy * float2(1.0, -1.0);

				OUT.viewDirWS = mul(Matrix_Inv_VP, float3(ndc_xy.xy, 1));

				return OUT;
			}

			half4 frag(v2f IN) : SV_Target
			{
				half4 test = half4(0,0,0,1);  //用于测试输出 
				float tmp1 = 0;

				//采样Comp，提取Flag位 
				half4 comp_m_d_r_f = SAMPLE_TEXTURE2D(_Comp_M_D_R_F, sampler_Comp_M_D_R_F, IN.uv);

				uint raw_flag = (uint)round(comp_m_d_r_f.w * 0xFF); // Decode ShadingModelId
				uint mat_type = raw_flag & SHADINGMODELID_MASK; 
				//uint see_flag = mat_type == (uint)8; //(0)显示天空,此外(9)眼, (8)衣服,(7)头发,(5)皮肤,(6)草,(1)木等 

				if (mat_type)  //不是天空的进入 
				{
					//首先重构世界坐标 
					float deviceZ = SAMPLE_TEXTURE2D(_Depth, sampler_Depth, IN.uv);
					float sceneDepth = deviceZ * InvDeviceZToWorldZTransform[0] + InvDeviceZToWorldZTransform[1] + 1.0 / (deviceZ * InvDeviceZToWorldZTransform[2] - InvDeviceZToWorldZTransform[3]);
					half3 ViewDirWS = normalize(IN.viewDirWS);
					float3 posWS = ViewDirWS * sceneDepth + CameraPosWS.xyz;
					test.xyz = abs(posWS - CameraPosWS.xyz) / 35000; //用于验证世界坐标解码后的正确性 

					//在一定屏幕空间范围内的随机变量，一般用于模糊摩尔纹或其他异样 
					float Dither = InterleavedGradientNoise(IN.vertex, FrameId); 

					//get shadow terms
					float4 LightAttenuation = GetPerPixelLightAttenuation(IN.uv);
					const float ContactShadowLengthScreenScale = Matrix_Inv_P[1][1] * sceneDepth;

					uint2 flag = raw_flag.xx & uint2(32, 64);
					float PrecomputedShadowFactors = flag.y ? 0 : 1;
					PrecomputedShadowFactors = flag.x ? PrecomputedShadowFactors : 1;

					float UsesStaticShadowMap = dot(LightData_ShadowMapChannelMask, float4(1, 1, 1, 1));
					float StaticShadowing = lerp(1, dot(PrecomputedShadowFactors, LightData_ShadowMapChannelMask), UsesStaticShadowMap);

					float DynamicShadowFraction = DistanceFromCameraFade(sceneDepth); //依据距离远近 

					// For a directional light, fade between static shadowing and the whole scene dynamic shadowing based on distance + per object shadows
					float SurfaceShadow = lerp(LightAttenuation.x, StaticShadowing, DynamicShadowFraction); //调和动态和静态阴影 
					// Fade between SSS dynamic shadowing and static shadowing based on distance
					float TransmissionShadow = min(lerp(LightAttenuation.y, StaticShadowing, DynamicShadowFraction), LightAttenuation.w);
					
					SurfaceShadow *= LightAttenuation.z;
					TransmissionShadow *= LightAttenuation.z;

					float ContactShadowLength = 0;
					UNITY_FLATTEN
					if (LightData_ShadowedBits > 1 && LightData_ContactShadowLength > 0)
					{
						ContactShadowLength = LightData_ContactShadowLength * ContactShadowLengthScreenScale; 
					}

					float StepOffset = Dither - 0.5;
					float ContactShadow = ShadowRayCast(
						posWS - CameraPosWS.xyz, 
						light_direction, 
						ContactShadowLength, 
						8, 
						StepOffset);

					SurfaceShadow *= ContactShadow;

					uint2 IsEyeHair = mat_type.xx == uint2(9, 7);
					TransmissionShadow = IsEyeHair.y ? 
						TransmissionShadow * ContactShadow : 
						(IsEyeHair.x ? TransmissionShadow : TransmissionShadow * (ContactShadow * 0.5 + 0.5)); 

					//test.x = SurfaceShadow;

					//test.x = CheckerFromSceneColorUV(IN.uv);

				}
				


				return half4(test.xxx, 1);
			}

			ENDHLSL
		}
	}
}