Shader "Kena/KenaDirLight"
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

			// The flags are defined so that 0 value has no effect!
			// These occupy the 4 high bits in the same channel as the SHADINGMODELID_*
			#define SKIP_CUSTOMDATA_MASK			(1 << 4)	// TODO remove. Can be inferred from shading model.
			#define SKIP_PRECSHADOW_MASK			(1 << 5)
			#define ZERO_PRECSHADOW_MASK			(1 << 6)
			#define SKIP_VELOCITY_MASK				(1 << 7)

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
				float4 CustomData;
				float Metallic; // 0..1
				float Specular; // 0..1
				float Roughness; // 0..1
				float GBufferAO; // 0..1
				float IndirectIrradiance; // 0..1
				uint ShadingModelID; // 0..15 
				uint SelectiveOutputMask; // 0..255 
				// in unreal units (linear), can be used to reconstruct world position,
				// only valid when decoding the GBuffer as the value gets reconstructed from the Z buffer
				float Depth; 
			};

			struct FShadowTerms
			{
				float	SurfaceShadow;
				float	TransmissionShadow;
				float	TransmissionThickness;
				//FHairTransmittanceData HairTransmittance;
			};

			struct FCapsuleLight
			{
				float3	LightPos[2];
				float	Length;
				float	Radius;
				float	SoftRadius;
				float	DistBiasSqr;
			};

			struct FDeferredLightingSplit
			{
				float4 DiffuseLighting;
				float4 SpecularLighting;
			};

			struct FDirectLighting
			{
				float3	Diffuse;
				float3	Specular;
				float3	Transmission;
			};

			struct FDeferredLightData
			{
				float3 Direction;
				float3 Tangent;
				float ContactShadowLength;
				float4 ShadowMapChannelMask;
				uint ShadowedBits;
				float SourceLength;
				float SourceRadius;
				float SoftSourceRadius;
				bool bInverseSquared;
			};

			struct FRectTexture
			{
				uint Dummy;
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
			static bool bSubsurfacePostprocessEnabled = true;

			static FDeferredLightData kena_LightData = (FDeferredLightData)0;


			//const static float LightData_ShadowedBits = 3;
			//const static float LightData_ContactShadowLength = 0.2;
			//static float3 light_direction = float3(0.51555, -0.29836, 0.80324); //光方向(指向光源) 
			//static float4 LightData_ShadowMapChannelMask = float4(0,0,0,0);

			static float4 screen_param = float4(1707, 960, 0.00059, 0.00104); 

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

			FCapsuleLight GetCapsule(float3 ToLight, FDeferredLightData LightData)
			{
				FCapsuleLight Capsule;
				Capsule.Length = LightData.SourceLength;
				Capsule.Radius = LightData.SourceRadius;
				Capsule.SoftRadius = LightData.SoftSourceRadius;
				Capsule.DistBiasSqr = 1;
				Capsule.LightPos[0] = ToLight - 0.5 * Capsule.Length * LightData.Tangent;
				Capsule.LightPos[1] = ToLight + 0.5 * Capsule.Length * LightData.Tangent;
				return Capsule;
			}

			bool UseSubsurfaceProfile(int ShadingModel)
			{
				return ShadingModel == SHADINGMODELID_SUBSURFACE_PROFILE || ShadingModel == SHADINGMODELID_EYE;
			}

			float DielectricSpecularToF0(float Specular)
			{
				return 0.08f * Specular;
			}

			float3 ComputeF0(float Specular, float3 BaseColor, float Metallic)
			{
				return lerp(DielectricSpecularToF0(Specular).xxx, BaseColor, Metallic.xxx);
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

			float3 DecodeNormal(float3 N)
			{
				return N * 2 - 1;
			}

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

			uint DecodeSelectiveOutputMask(float InPackedChannel)
			{
				return ((uint)round(InPackedChannel * (float)0xFF)) & ~SHADINGMODELID_MASK;
			}

			float ConvertFromDeviceZ(float DeviceZ)
			{
				// Supports ortho and perspective, see CreateInvDeviceZToWorldZTransform()
				return DeviceZ * InvDeviceZToWorldZTransform[0] + InvDeviceZToWorldZTransform[1] + 1.0f / (DeviceZ * InvDeviceZToWorldZTransform[2] - InvDeviceZToWorldZTransform[3]);
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

				//GBuffer.CustomDepth = 1; 
				GBuffer.Depth = SceneDepth; 

				//Kena里只有木+墙部分激活了 Skip_CustomData，其余部分均需要用到 Comp_F_R_X_I_Raw 这样用户定义的纹理和对应逻辑 
				GBuffer.CustomData = (!(GBuffer.SelectiveOutputMask & SKIP_CUSTOMDATA_MASK)) ? Comp_F_R_X_I_Raw.xyzw : float4(0, 0, 0, 0);

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

			FGBufferData GetGBufferData(float2 UV, bool bGetNormalizedNormal = true)
			{
				float DeviceZ = SAMPLE_TEXTURE2D(_Depth, sampler_Depth, UV).r;
				float3 Normal_Raw = SAMPLE_TEXTURE2D(_Normal, sampler_Normal, UV).xyz;
				float4 Albedo_Raw = SAMPLE_TEXTURE2D(_Albedo, sampler_Albedo, UV).xyzw;
				float4 Comp_M_D_R_F_Raw = SAMPLE_TEXTURE2D(_Comp_M_D_R_F, sampler_Comp_M_D_R_F, UV).xyzw;
				float4 Comp_F_R_X_I_Raw = SAMPLE_TEXTURE2D(_Comp_F_R_X_I, sampler_Comp_F_R_X_I, UV).xyzw;
				float4 ShadowTex_Raw = SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, UV).xyzw;

				float SceneDepth = ConvertFromDeviceZ(DeviceZ);

				return DecodeGBufferData(Normal_Raw, Albedo_Raw, Comp_M_D_R_F_Raw, 
					Comp_F_R_X_I_Raw, ShadowTex_Raw, SceneDepth, CheckerFromSceneColorUV(UV));
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

			void GetShadowTerms(FGBufferData GBuffer, FDeferredLightData LightData, float3 WorldPosition,
				float3 L, float4 LightAttenuation, float Dither, inout FShadowTerms Shadow)
			{
				const float ContactShadowLengthScreenScale = Matrix_Inv_P[1][1] * GBuffer.Depth;

				uint2 flag = GBuffer.SelectiveOutputMask & uint2(SKIP_PRECSHADOW_MASK, ZERO_PRECSHADOW_MASK);
				float PrecomputedShadowFactors = flag.y ? 0 : 1;
				PrecomputedShadowFactors = flag.x ? PrecomputedShadowFactors : 1;

				float UsesStaticShadowMap = dot(LightData.ShadowMapChannelMask, float4(1, 1, 1, 1));
				float StaticShadowing = lerp(1, dot(PrecomputedShadowFactors, LightData.ShadowMapChannelMask), UsesStaticShadowMap);

				float DynamicShadowFraction = DistanceFromCameraFade(GBuffer.Depth); //依据距离远近 

				// For a directional light, fade between static shadowing and the whole scene dynamic shadowing based on distance + per object shadows
				float SurfaceShadow = lerp(LightAttenuation.x, StaticShadowing, DynamicShadowFraction); //调和动态和静态阴影 
				// Fade between SSS dynamic shadowing and static shadowing based on distance
				float TransmissionShadow = min(lerp(LightAttenuation.y, StaticShadowing, DynamicShadowFraction), LightAttenuation.w);

				SurfaceShadow *= LightAttenuation.z;
				TransmissionShadow *= LightAttenuation.z;

				float ContactShadowLength = 0;
				UNITY_FLATTEN
				if (LightData.ShadowedBits > 1 && LightData.ContactShadowLength > 0)
				{
					ContactShadowLength = LightData.ContactShadowLength * ContactShadowLengthScreenScale;
				}

				float StepOffset = Dither - 0.5;
				float ContactShadow = ShadowRayCast(
					WorldPosition - CameraPosWS.xyz,  //对应UE4源码: WorldPosition + View.PreViewTranslation 
					L,
					ContactShadowLength,
					8,
					StepOffset);

				SurfaceShadow *= ContactShadow;

				uint2 IsEyeHair = GBuffer.ShadingModelID == uint2(SHADINGMODELID_EYE, SHADINGMODELID_HAIR);
				TransmissionShadow = IsEyeHair.y ?
					TransmissionShadow * ContactShadow :
					(IsEyeHair.x ? TransmissionShadow : TransmissionShadow * (ContactShadow * 0.5 + 0.5));

				Shadow.SurfaceShadow = SurfaceShadow;
				Shadow.TransmissionShadow = TransmissionShadow;
			}

			FDirectLighting IntegrateBxDF(FGBufferData GBuffer, half3 N, half3 V, FCapsuleLight Capsule, 
				FShadowTerms Shadow, bool bInverseSquared)
			{
				float NoL = 0;
				float Falloff = 0;
				float LineCosSubtended = 1;

				if (Capsule.Length <= 0 ) // -> Kena 的CapsuleLight.len总是为0
				{
					float DistSqr = dot(Capsule.LightPos[0], Capsule.LightPos[0]); //LightPos里存的其实是LightDir 
					Falloff = rcp(DistSqr + Capsule.DistBiasSqr);	//todo  
					float3 L = Capsule.LightPos[0] * rsqrt(DistSqr);  //可以直接拿Capsule.LightPos[0]替代，Kena中，这个值本身已经被归一化了 
					NoL = dot(N, L);
				}

				if (Capsule.Radius > 0)
				{
					// TODO Use capsule area?
					float SinAlphaSqr = saturate(Pow2(Capsule.Radius) * Falloff);
					NoL = SphereHorizonCosWrap(NoL, SinAlphaSqr);
				}


				FDirectLighting BxDF_output = (FDirectLighting)0; 
				return BxDF_output;
			}

			/** Calculates lighting for a given position, normal, etc with a fully featured lighting model designed for quality. */ 
			FDeferredLightingSplit GetDynamicLightingSplit(
				float3 WorldPosition, float3 CameraVector, FGBufferData GBuffer, float AmbientOcclusion, uint ShadingModelID,
				FDeferredLightData LightData, float4 LightAttenuation, float Dither, uint2 SVPos, FRectTexture SourceTexture,
				inout float SurfaceShadow)
			{
				float3 V = -CameraVector;
				float3 N = GBuffer.WorldNormal;

				float3 L = LightData.Direction;	// Already normalized -> 这里是引擎提供的主光方向 
				float3 ToLight = L;

				float LightMask = 1;

				//if (LightMask > 0)		//TRUE -> 假设任何位置都能被 RadialLight 照射到 
				{
					FShadowTerms Shadow = (FShadowTerms)0;
					Shadow.SurfaceShadow = AmbientOcclusion;
					Shadow.TransmissionShadow = 1;
					Shadow.TransmissionThickness = 1;
					//Shadow.HairTransmittance.Transmittance = 1; 
					//Shadow.HairTransmittance.OpaqueVisibility = 1; //todo 
					GetShadowTerms(GBuffer, LightData, WorldPosition, L, LightAttenuation, Dither, Shadow); 
					SurfaceShadow = Shadow.SurfaceShadow; 

					UNITY_BRANCH
					if (Shadow.SurfaceShadow + Shadow.TransmissionShadow > 0)  //不处于完全黑暗的地方，都需要计算光照！ 
					{
						//todo 
						// const bool bNeedsSeparateSubsurfaceLightAccumulation = UseSubsurfaceProfile(GBuffer.ShadingModelID);
						// float3 LightColor = LightData.Color;
						
						// Kena 进入 ~NON_DIRECTIONAL_DIRECT_LIGHTING 分支，既，有直接光
						FDirectLighting Lighting;
						//Kena 进入 Capsule light 分支 
						FCapsuleLight Capsule = GetCapsule(ToLight, LightData);
						Lighting = IntegrateBxDF(GBuffer, N, V, Capsule, Shadow, LightData.bInverseSquared);

					}


				}

				FDeferredLightingSplit OUT = (FDeferredLightingSplit)0;
				return OUT;
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
				//init all local buffer data
				kena_LightData.ShadowedBits = 3;		  //cb1[2].x=3 -> 需用uint4查看 
				kena_LightData.ContactShadowLength = 0.2; //cb1[1].z=0.2 
				kena_LightData.Direction = float3(0.51555, -0.29836, 0.80324);  //cb1[5].xyz
				kena_LightData.Tangent = float3(0.51555, -0.29836, 0.80324);    //cb1[6].xyz
				kena_LightData.ShadowMapChannelMask = float4(0, 0, 0, 0);	    //cb1[0].xyzw 
				kena_LightData.SourceLength = 0;		//cb1[7].w=0
				kena_LightData.SourceRadius = 0.00467;	//cb1[6].w=0.00467
				kena_LightData.SoftSourceRadius = 0;	//todo 
				kena_LightData.bInverseSquared = true;	//todo  uint4
				//LightColor -> 推测为 cb1[4].rgb 
				//init done! 

				half4 test = half4(0,0,0,1);  //用于测试输出 
				//float tmp1 = 0;

				FGBufferData GBuffer = GetGBufferData(IN.uv);
				
				//uint see_flag = GBuffer.ShadingModelID == (uint)5; //(0)显示天空,此外(9)眼, (8)衣服,(7)头发,(5)皮肤,(6)草,(1)木等 

				if (GBuffer.ShadingModelID)  //不是天空的进入 
				{
					//首先重构世界坐标 
					half3 ViewDirWS = normalize(IN.viewDirWS);
					float3 WorldPosition = ViewDirWS * GBuffer.Depth + CameraPosWS.xyz;
					float3 CameraVector = normalize(WorldPosition - CameraPosWS.xyz);
					//test.xyz = abs(posWS - CameraPosWS.xyz) / 35000; //用于验证世界坐标解码后的正确性 

					//在一定屏幕空间范围内的随机变量，一般用于模糊摩尔纹或其他异样 
					float Dither = InterleavedGradientNoise(IN.vertex, FrameId); 

					//get shadow terms
					float4 LightAttenuation = GetPerPixelLightAttenuation(IN.uv);

					//get ssao 
					float AmbientOcclusion = SAMPLE_TEXTURE2D(_SSAO, sampler_SSAO, IN.uv).r;

					//get dumy rect texture 
					FRectTexture SourceTexture = (FRectTexture)0;

					float SurfaceShadow = 1.0f;

					FDeferredLightingSplit light_output = GetDynamicLightingSplit(
						WorldPosition, CameraVector, GBuffer, AmbientOcclusion, GBuffer.ShadingModelID,
						kena_LightData, LightAttenuation, Dither, uint2(IN.vertex.xy), SourceTexture,
						SurfaceShadow
					);

					test.x = SurfaceShadow;

					//test.x = CheckerFromSceneColorUV(IN.uv);

				}
				


				return half4(test.xxx, 1);
			}

			ENDHLSL
		}
	}
}