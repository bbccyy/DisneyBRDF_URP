Shader "Unlit/Kena_GI_Rebuild"
{
    Properties
    {
        [NoScaleOffset] _Albedo("Albedo", 2D) = "white" {}
        [NoScaleOffset] _Depth("Depth", 2D) = "white" {}
        [NoScaleOffset] _SSAO("SSAO", 2D) = "white" {}
        [NoScaleOffset] _Comp_F_R_X_I("Comp_F_R_X_I", 2D) = "white" {}
        [NoScaleOffset] _Comp_M_D_R_F("Comp_M_D_R_F", 2D) = "white" {}
        [NoScaleOffset] _Normal("Normal", 2D) = "white" {}

        [NoScaleOffset] _GNorm("GNorm", 2D) = "white" {}
        [NoScaleOffset] _IBL("IBL", CUBE) = "white" {}
        [NoScaleOffset] _Sky("Sky", CUBE) = "white" {}
        [NoScaleOffset] _LUT("LUT", 2D) = "white" {}
        [NoScaleOffset] _SSR("SSR", 2D) = "white" {}  //ScreenSpaceReflectionsTexture 

    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Blend One One
        ZTest Off

        LOD 100

        Pass
        {
            HLSLPROGRAM 
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets\Kena Rebuild Com\Shader\KenaDefferedCommon.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };


            TEXTURE2D(_GNorm); SAMPLER(sampler_GNorm);
            TEXTURE2D(_LUT); SAMPLER(sampler_LUT);
            TEXTURE2D(_SSR); SAMPLER(sampler_SSR);


#ifndef NUM_CULLED_LIGHTS_GRID_STRIDE
    #define NUM_CULLED_LIGHTS_GRID_STRIDE 2
#endif

#define ALLOW_STATIC_LIGHTING false


            static float4 View_ViewRectMin = float4(0, 0, 0, 0);
            static uint View_DistanceFieldAOSpecularOcclusionMode = 1;
            static float2 AOBufferBilinearUVMax = float2(0.99823, 0.99894);
            static float AOMaxViewDistance = 20000.0f;
            static float DistanceFadeScale = 0.00017f;
            static float OcclusionExponent = 0.7f;
            static uint ForwardLightData_NumGridCells = 12960;
            static uint ForwardLightData_NumReflectionCaptures = 44;
            static float InvSkySpecularOcclusionStrength = 1;
            static float ApplyBentNormalAO = 1;
            static half View_ReflectionCubemapMaxMip = 7;
            static float4 _CapturePositionAndRadius = float4(-59984.22266, 25498.43164, -6413.56885, 1686.55786);
            static float4 _CaptureProperties = float4(1.00, 27.00, 0.00, 0.00);


            float2 SvPositionToBufferUV(float4 SvPosition)
            {
                return SvPosition.xy * View_BufferSizeAndInvSize.zw;
            }

            float4 SvPositionToScreenPosition(float4 SvPosition)
            {
                float2 PixelPos = SvPosition.xy - View_ViewRectMin.xy;
                // NDC (NormalizedDeviceCoordinates, after the perspective divide) 
                // 备注: 原式乘子float2(2, -2),带有y的翻转 
                float3 NDCPos = float3((PixelPos * View_ViewSizeAndInvSize.zw - 0.5f) * float2(2, 2), SvPosition.z);
                // SvPosition.w: so .w has the SceneDepth, some mobile code and the DepthFade material expression wants that
                return float4(NDCPos.xyz, 1) * SvPosition.w;
            }

            half3 EnvBRDF(half3 SpecularColor, half Roughness, half NoV)
            {
                // Importance sampled preintegrated G * F
                //float2 AB = Texture2DSampleLevel(PreIntegratedGF, PreIntegratedGFSampler, float2(NoV, Roughness), 0).rg;
                float2 AB = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, float2(NoV, Roughness)).rg;
                // Anything less than 2% is physically impossible and is instead considered to be shadowing 
                float3 GF = SpecularColor * AB.x + saturate(50.0 * SpecularColor.g) * AB.y;
                return GF;
            }

            float3 UpsampleDFAO(float2 BufferUV, float SceneDepth, float3 WorldNormal)
            {
                // Distance field AO was computed at 0,0 regardless of viewrect min
                float2 DistanceFieldUVs = BufferUV - View_ViewRectMin.xy * View_BufferSizeAndInvSize.zw;
                DistanceFieldUVs = min(DistanceFieldUVs, AOBufferBilinearUVMax);
#define BILATERAL_UPSAMPLE 0
#if BILATERAL_UPSAMPLE
                float2 LowResBufferSize = floor(View_BufferSizeAndInvSize.xy / AO_DOWNSAMPLE_FACTOR);
                float2 LowResTexelSize = 1.0f / LowResBufferSize;
                float2 Corner00UV = floor(DistanceFieldUVs * LowResBufferSize - .5f) / LowResBufferSize + .5f * LowResTexelSize;
                float2 BilinearWeights = (DistanceFieldUVs - Corner00UV) * LowResBufferSize;

                float4 TextureValues00 = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, Corner00UV);
                float4 TextureValues10 = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, Corner00UV + float2(LowResTexelSize.x, 0));
                float4 TextureValues01 = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, Corner00UV + float2(0, LowResTexelSize.y));
                float4 TextureValues11 = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, Corner00UV + LowResTexelSize);

                float4 CornerWeights = float4(
                    (1 - BilinearWeights.y) * (1 - BilinearWeights.x),
                    (1 - BilinearWeights.y) * BilinearWeights.x,
                    BilinearWeights.y * (1 - BilinearWeights.x),
                    BilinearWeights.y * BilinearWeights.x);

                float Epsilon = .0001f;

                float4 CornerDepths = float4(TextureValues00.w, TextureValues10.w, TextureValues01.w, TextureValues11.w);
                float4 DepthWeights = 1.0f / (abs(CornerDepths - SceneDepth.xxxx) + Epsilon);
                float4 FinalWeights = CornerWeights * DepthWeights;

                float InvWeight = 1.0f / dot(FinalWeights, 1);

                float3 InterpolatedResult =
                    (FinalWeights.x * TextureValues00.xyz
                        + FinalWeights.y * TextureValues10.xyz
                        + FinalWeights.z * TextureValues01.xyz
                        + FinalWeights.w * TextureValues11.xyz)
                    * InvWeight;

                float3 BentNormal = InterpolatedResult.xyz;
#else
                float3 BentNormal = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, DistanceFieldUVs).xyz;
                //float3 BentNormal = SAMPLE_TEXTURE2D(_Normal, sampler_Normal, DistanceFieldUVs).xyz; 
#endif
                // Fade to unoccluded in the distance
                float FadeAlpha = saturate((AOMaxViewDistance - SceneDepth) * DistanceFadeScale);
                //FadeAlpha = 0;  //for test 
                BentNormal = lerp(WorldNormal, BentNormal, FadeAlpha);

                return BentNormal;
            }

            void RemapClearCoatDiffuseAndSpecularColor(FGBufferData GBuffer, float2 ScreenPosition, inout float3 DiffuseColor, inout float3 SpecularColor)
            {
                if (GBuffer.ShadingModelID == SHADINGMODELID_CLEAR_COAT)
                {
                    // Attenuate base color and recompute diffuse color
                    //float3 WorldPosition = mul(float4(ScreenPosition * GBuffer.Depth, GBuffer.Depth, 1), View.ScreenToWorld).xyz;
                    float3 WorldPosition = mul(Matrix_Inv_VP, float4(ScreenPosition * GBuffer.Depth, GBuffer.Depth, 1)).xyz;

                    float3 CameraToPixel = normalize(WorldPosition - CameraPosWS);
                    float3 V = -CameraToPixel;
                    float NoV = saturate(dot(GBuffer.WorldNormal, V));
                    float RefractionScale = ((NoV * 0.5 + 0.5) * NoV - 1) * saturate(1.25 - 1.25 * GBuffer.Roughness) + 1;

                    float MetalSpec = 0.9;
                    float3 AbsorptionColor = GBuffer.BaseColor * (1 / MetalSpec);
                    float3 Absorption = AbsorptionColor * ((NoV - 1) * 0.85 * (1 - lerp(AbsorptionColor, Pow2(AbsorptionColor), -0.78)) + 1);

                    float F0 = 0.04;
                    float Fc = Pow5(1 - NoV);
                    float F = Fc + (1 - Fc) * F0;
                    float ClearCoat = GBuffer.CustomData.x;
                    float LayerAttenuation = lerp(1, (1 - F), ClearCoat);

                    float3 BaseColor = lerp(GBuffer.BaseColor * LayerAttenuation, MetalSpec * Absorption * RefractionScale, GBuffer.Metallic * ClearCoat);
                    //BaseColor += Dither / 255.f;
                    DiffuseColor = BaseColor - BaseColor * GBuffer.Metallic;

                    float3 Specular = lerp(1, RefractionScale, ClearCoat);
                    SpecularColor = ComputeF0(Specular, BaseColor, GBuffer.Metallic);
                }
            }

            FGBufferData GetGBufferDataFromSceneTextures(float2 UV, bool bGetNormalizedNormal = true)
            {
                float DeviceZ = SAMPLE_TEXTURE2D(_Depth, sampler_Depth, UV).r;
                float3 Normal_Raw = SAMPLE_TEXTURE2D(_Normal, sampler_Normal, UV).xyz;                      //GBufferA
                float4 Albedo_Raw = SAMPLE_TEXTURE2D(_Albedo, sampler_Albedo, UV).xyzw;                     //GBufferB
                float4 Comp_M_D_R_F_Raw = SAMPLE_TEXTURE2D(_Comp_M_D_R_F, sampler_Comp_M_D_R_F, UV).xyzw;   //GBufferC
                float4 Comp_F_R_X_I_Raw = SAMPLE_TEXTURE2D(_Comp_F_R_X_I, sampler_Comp_F_R_X_I, UV).xyzw;   //GBufferD
                float4 ShadowTex_Raw = 0;   //GBufferE: Shadow 
                //float4 GBufferF = 0.5f;     //GBufferF: TANGENT 

                float SceneDepth = ConvertFromDeviceZ(DeviceZ);

                return DecodeGBufferData(Normal_Raw, Albedo_Raw, Comp_M_D_R_F_Raw, Comp_F_R_X_I_Raw, ShadowTex_Raw,
                    SceneDepth, CheckerFromSceneColorUV(UV));
            }

            float3 GetSkySHDiffuse(float3 Normal)
            {
                float4 NormalVector = float4(Normal, 1);

                float3 Intermediate0, Intermediate1, Intermediate2;
                Intermediate0.x = dot(View_SkyIrradianceEnvironmentMap[0], NormalVector);
                Intermediate0.y = dot(View_SkyIrradianceEnvironmentMap[1], NormalVector);
                Intermediate0.z = dot(View_SkyIrradianceEnvironmentMap[2], NormalVector);

                float4 vB = NormalVector.xyzz * NormalVector.yzzx;
                Intermediate1.x = dot(View_SkyIrradianceEnvironmentMap[3], vB);
                Intermediate1.y = dot(View_SkyIrradianceEnvironmentMap[4], vB);
                Intermediate1.z = dot(View_SkyIrradianceEnvironmentMap[5], vB);

                float vC = NormalVector.x * NormalVector.x - NormalVector.y * NormalVector.y;
                Intermediate2 = View_SkyIrradianceEnvironmentMap[6].xyz * vC;

                // max to not get negative colors
                return max(0, Intermediate0 + Intermediate1 + Intermediate2);
            }

            float3 SkyLightDiffuse(FGBufferData GBuffer, float AmbientOcclusion, float2 BufferUV, float2 ScreenPosition, float3 BentNormal, float3 DiffuseColor)
            {
                float2 UV = BufferUV;
                float3 Lighting = 0;

                // Always USE_DIRECTIONAL_OCCLUSION_ON_SKY_DIFFUSE 
                float SkyVisibility = length(BentNormal);;
                float3 NormalizedBentNormal = BentNormal / (max(SkyVisibility, .00001f));
                float BentNormalWeightFactor = SkyVisibility;// Use more bent normal in corners
                float3 SkyLightingNormal = lerp(NormalizedBentNormal, GBuffer.WorldNormal, BentNormalWeightFactor);
                float DotProductFactor = lerp(dot(NormalizedBentNormal, GBuffer.WorldNormal), 1, BentNormalWeightFactor);

                float ContrastCurve = 1 / (1 + exp(-ContrastAndNormalizeMulAdd.x * (SkyVisibility * 10 - 5)));
                SkyVisibility = saturate(ContrastCurve * ContrastAndNormalizeMulAdd.y + ContrastAndNormalizeMulAdd.z);

                SkyVisibility = pow(SkyVisibility, OcclusionExponent);
                SkyVisibility = lerp(SkyVisibility, 1, OcclusionTintAndMinOcclusion.w);

                // Combine with mul, which continues to add SSAO depth even indoors.  SSAO will need to be tweaked to be less strong.
                SkyVisibility = SkyVisibility * min(GBuffer.GBufferAO, AmbientOcclusion);

                float ScalarFactors = SkyVisibility;

                UNITY_BRANCH
                if (GBuffer.ShadingModelID == SHADINGMODELID_TWOSIDED_FOLIAGE)
                {
                    float3 SubsurfaceLookup = GetSkySHDiffuse(-GBuffer.WorldNormal) * View_SkyLightColor.rgb;
                    float3 SubsurfaceColor = ExtractSubsurfaceColor(GBuffer);
                    Lighting += ScalarFactors * SubsurfaceLookup * SubsurfaceColor;
                }

                if (GBuffer.ShadingModelID == SHADINGMODELID_SUBSURFACE || GBuffer.ShadingModelID == SHADINGMODELID_PREINTEGRATED_SKIN)
                {
                    float3 SubsurfaceColor = ExtractSubsurfaceColor(GBuffer);
                    // Add subsurface energy to diffuse
                    DiffuseColor += SubsurfaceColor;
                }

                UNITY_BRANCH
                if (GBuffer.ShadingModelID == SHADINGMODELID_HAIR)
                {
                    float3 N = GBuffer.WorldNormal;
                    //float3 V = -normalize(mul(float4(ScreenPosition, 1, 0), View_ScreenToWorld).xyz);
                    float3 V = -normalize(mul(Matrix_Inv_VP, float4(ScreenPosition, 1, 0)).xyz);

                    float3 L = normalize(V - N * dot(V, N));
                    SkyLightingNormal = L;

                    //InitHairTransmittanceData -> dummy 
                    FHairTransmittanceData TransmittanceData = (FHairTransmittanceData)0;
                    bool bEvalMultiScatter = true;
                    DiffuseColor = PI * HairShading(GBuffer, L, V, N, 1, TransmittanceData, 0, 0.2, uint2(0, 0), bEvalMultiScatter);
                }

                if (GBuffer.ShadingModelID == SHADINGMODELID_CLOTH)
                {
                    float3 ClothFuzz = ExtractSubsurfaceColor(GBuffer);
                    DiffuseColor += ClothFuzz * GBuffer.CustomData.a;
                }

                // Compute the preconvolved incoming lighting with the bent normal direction
                float3 DiffuseLookup = GetSkySHDiffuse(SkyLightingNormal) * View_SkyLightColor.rgb;

                // Apply AO to the sky diffuse and account for darkening due to the geometry term
                // apply the Diffuse color to the lighting (including OcclusionTintAndMinOcclusion as it's considered another light, that fixes SubsurfaceProfile being too dark)
                Lighting += ((ScalarFactors * DotProductFactor) * DiffuseLookup + (1 - SkyVisibility) * OcclusionTintAndMinOcclusion.xyz) * DiffuseColor;

                return Lighting;
            }

            // Point lobe in off-specular peak direction
            float3 GetOffSpecularPeakReflectionDir(float3 Normal, float3 ReflectionVector, float Roughness)
            {
                float a = Pow2(Roughness);
                return lerp(Normal, ReflectionVector, (1 - a) * (sqrt(1 - a) + a));
            }

            float GetSpecularOcclusion(float NoV, float RoughnessSq, float AO)
            {
                return saturate(pow(NoV + AO, RoughnessSq) - 1 + AO);
            }

            uint ComputeLightGridCellIndex(uint2 PixelPos, float SceneDepth)
            {
                /*
                const FLightGridData GridData = GetLightGridData(EyeIndex);
                uint ZSlice = (uint)(max(0, log2(SceneDepth * GridData.LightGridZParams.x + GridData.LightGridZParams.y) * GridData.LightGridZParams.z));
                ZSlice = min(ZSlice, (uint)(GridData.CulledGridSize.z - 1));  //CulledGridSize.z 存放深度z的上界，更远处的LightGrid就被Cull了
                uint3 GridCoordinate = uint3(PixelPos >> GridData.LightGridPixelSizeShift, ZSlice); //GridData.LightGridPixelSizeShift==6 
                uint GridIndex = (GridCoordinate.z * GridData.CulledGridSize.y + GridCoordinate.y) * GridData.CulledGridSize.x + GridCoordinate.x;
                */

                //  CulledGridSize.xyzw=[27, 15, 32, 32] -> [宽，高，深度] 单位是"个" 
                //      其中拿出x轴向的cell数，乘以一个cell占用的pixels数 -> 27 * 2^6 = 1728 
                //      1728 pixels == screen width resolution 
                // 
                //  这个GridIndex是按照先x轴增加，满27个cell后再增加一个y轴，
                //  满了15个y轴(既满了27 * 15个cell组成的一面屏幕墙)之后，
                //  再往深度挖掘一个z轴单位，以此类推，将3D的cell立方块进行一维化编码 

                uint GridIndex = 0;
                return GridIndex;
            }

            void GetAffectedReflectionCapturesAndNextJumpIndex(FGBufferData GBuffer, float4 SvPosition, inout uint DataStartIndex, inout uint NumCulledReflectionCaptures)
            {
                float2 LocalPosition = SvPosition.xy - View_ViewRectMin.xy;
                uint GridIndex = ComputeLightGridCellIndex(uint2(LocalPosition.x, LocalPosition.y), GBuffer.Depth);

                // NUM_CULLED_LIGHTS_GRID_STRIDE==2 -> "2" 个一组，分别记录 NumCulledReflectionCaptures 和 DataStartIndex 这一成对的数据 
                // ForwardLightData.NumGridCells==12960 -> 27(x轴向) * 15(y轴向) * 32(z轴向) == 12960 cells -> 屏幕空间拆解成这么多个cell 
                uint NumCulledEntryIndex = (ForwardLightData_NumGridCells + GridIndex) * NUM_CULLED_LIGHTS_GRID_STRIDE;

                // ForwardLightData.NumReflectionCaptures==44 -> 一共有44张IBL纹理，这是上限 
                // ForwardLightData.NumCulledLightsGrid存放了当前cell受影响的IBL纹理个数，以及下一步寻找具体是哪些纹理的新索引
                // NumCulledReflectionCaptures = min(ForwardLightData.NumCulledLightsGrid[NumCulledEntryIndex + 0], ForwardLightData.NumReflectionCaptures);
                NumCulledReflectionCaptures = 1;  //糊弄用，目前不打算在Unity里构建ForwardLightData.NumCulledLightsGrid等数据结构 

                // DataStartIndex = ForwardLightData.NumCulledLightsGrid[NumCulledEntryIndex + 1];
                DataStartIndex = 0; //同糊弄用，这个索引用于查找下一张映射表，毕竟我们最终是需要得到IBL的具体位置，目前还差2次跳转哩 
            }

            void GetDistanceFieldAOSpecularOcclusion(float3 BentNormalAO, float3 ReflectionVector, float Roughness, bool bTwoSidedFoliage, out float IndirectSpecularOcclusion, out float IndirectDiffuseOcclusion, out float3 ExtraIndirectSpecular)
            {
                IndirectSpecularOcclusion = 1;
                IndirectDiffuseOcclusion = 1;
                ExtraIndirectSpecular = 0;

                UNITY_BRANCH 
                if (ApplyBentNormalAO > 0)
                {
                    float BentNormalLength = length(BentNormalAO);

                    UNITY_BRANCH
                    if (View_DistanceFieldAOSpecularOcclusionMode == 0)
                    {
                        IndirectSpecularOcclusion = BentNormalLength;
                    }
                    else
                    {
                        UNITY_BRANCH
                        if (bTwoSidedFoliage)
                        {
                            IndirectSpecularOcclusion = BentNormalLength;
                        }
                        else
                        {
                            float ReflectionConeAngle = max(Roughness, .1f) * PI;
                            float UnoccludedAngle = BentNormalLength * PI * InvSkySpecularOcclusionStrength;
                            float AngleBetween = acos(dot(BentNormalAO, ReflectionVector) / max(BentNormalLength, .001f));
                            IndirectSpecularOcclusion = ApproximateConeConeIntersection(ReflectionConeAngle, UnoccludedAngle, AngleBetween);

                            // Can't rely on the direction of the bent normal when close to fully occluded, lerp to shadowed
                            IndirectSpecularOcclusion = lerp(0, IndirectSpecularOcclusion, saturate((UnoccludedAngle - .1f) / .2f));
                        }
                    }

                    IndirectSpecularOcclusion = lerp(IndirectSpecularOcclusion, 1, OcclusionTintAndMinOcclusion.w);
                    ExtraIndirectSpecular = (1 - IndirectSpecularOcclusion) * OcclusionTintAndMinOcclusion.xyz;
                }
            }

            float3 CompositeReflectionCapturesAndSkylight(
                float CompositeAlpha,
                float3 WorldPosition,
                float3 RayDirection,
                float Roughness,
                float IndirectIrradiance,
                float IndirectSpecularOcclusion,
                float3 ExtraIndirectSpecular,
                uint NumCapturesAffectingTile,
                uint CaptureDataStartIndex,
                int SingleCaptureIndex,
                bool bCompositeSkylight)
            {
                float Mip = ComputeReflectionCaptureMipFromRoughness(Roughness, View_ReflectionCubemapMaxMip);
                float4 ImageBasedReflections = float4(0, 0, 0, CompositeAlpha);
                float2 CompositedAverageBrightness = float2(0.0f, 1.0f);

                float4 test = 0;  //for test 

                UNITY_LOOP
                for (uint TileCaptureIndex = 0; TileCaptureIndex < 1; TileCaptureIndex++)
                {
                    /*UNITY_BRANCH
                    if (ImageBasedReflections.a < 0.001)
                    {
                        break;
                    }*/

                    uint CaptureIndex = 0;
                    //我有理由相信这里的CaptureIndex是属于世界空间（而不是基于屏幕空间）中的预计算得到的数据结构所属的Index 
                    //而以ForwardLightData开头的数据结构，存储的是动态数据，由CPU/GPU针对当前帧计算和覆写，记录的是屏幕空间信息 
                    //具体而言ForwardLightData.CulledLightDataGrid存放了一张映射表，从屏幕空间中划分的cell blocks 映射到 时间空间中的cell blocks索引 
                    //CaptureIndex = ForwardLightData.CulledLightDataGrid[CaptureDataStartIndex + TileCaptureIndex];
                    CaptureIndex = 0; //这里糊弄过去，不想在Unity里重建UE才有的CulledLightDataGrid数据结构 

                    //ReflectionCapture.PositionAndRadius对应预计算好的隶属于世界空间中的数据结构，存放位置和范围 
                    //float4 CapturePositionAndRadius = ReflectionCapture.PositionAndRadius[CaptureIndex]; 
                    //ReflectionCapture.CaptureProperties同上，存放TexCubeArray的第三维坐标（指定是第几个Cube) 
                    //float4 CaptureProperties = ReflectionCapture.CaptureProperties[CaptureIndex]; 
                    
                    float4 CapturePositionAndRadius = _CapturePositionAndRadius;  //这里使用固定值替代 
                    float4 CaptureProperties = _CaptureProperties;

                    float3 CaptureVector = WorldPosition - CapturePositionAndRadius.xyz;
                    float CaptureVectorLength = sqrt(dot(CaptureVector, CaptureVector));
                    float NormalizedDistanceToCapture = saturate(CaptureVectorLength / CapturePositionAndRadius.w);

                    UNITY_BRANCH
                    if (CaptureVectorLength < CapturePositionAndRadius.w)
                    //if (true)
                    {
                        //float3 ProjectedCaptureVector = RayDirection;
                        float4 CaptureOffsetAndAverageBrightness = 0;
                        // Fade out based on distance to capture
                        float DistanceAlpha = 0;

                        float3 ProjectedCaptureVector = GetLookupVectorForSphereCapture(RayDirection, WorldPosition,
                            CapturePositionAndRadius, NormalizedDistanceToCapture, 
                            CaptureOffsetAndAverageBrightness.xyz, DistanceAlpha);

                        //float CaptureArrayIndex = CaptureProperties.g; //没用CubeArray，所以这个参数这里暂时不需要 

                        float4 Sample = SAMPLE_TEXTURECUBE_LOD(_IBL, sampler_IBL, ProjectedCaptureVector, Mip).rgba;
                        
                        Sample.rgb *= CaptureProperties.r;
                        Sample *= DistanceAlpha;

                        // Under operator (back to front)
                        ImageBasedReflections.rgb += Sample.rgb *
                            ImageBasedReflections.a * IndirectSpecularOcclusion;
                        ImageBasedReflections.a *= 1 - Sample.a;
                        //test = ImageBasedReflections;
                    }
                }

                UNITY_BRANCH
                if (ReflectionStruct_SkyLightParameters.y > 0 && bCompositeSkylight)
                {
                    float SkyAverageBrightness = 1.0f;
                    //TODO: 如下 * 0.05 是我加上的，目前采样返回值SkyLighting亮度很高，经过后续逻辑迭代会导致
                    //SkyLight过饱和，影响显示效果。在没有彻底搞清楚原因的前提下，先用此魔法数字手动进行调节。
                    float3 SkyLighting = GetSkyLightReflectionSupportingBlend(RayDirection, Roughness) * 0.02;
                    
                    // Normalize for static skylight types which mix with lightmaps
                    bool bNormalize = ReflectionStruct_SkyLightParameters.z < 1 && ALLOW_STATIC_LIGHTING;

                    UNITY_FLATTEN
                    if (bNormalize)
                    {
                        ImageBasedReflections.rgb += ImageBasedReflections.a * SkyLighting * IndirectSpecularOcclusion;
                        CompositedAverageBrightness.x += SkyAverageBrightness * CompositedAverageBrightness.y;
                    }
                    else
                    {
                        ExtraIndirectSpecular += SkyLighting * IndirectSpecularOcclusion;
                    }
                }

                ImageBasedReflections.rgb += ImageBasedReflections.a * ExtraIndirectSpecular;

                //ImageBasedReflections.rgb = IndirectSpecularOcclusion;  //for test 
                return ImageBasedReflections.rgb;
            }

            float3 GatherRadiance(float CompositeAlpha, float3 WorldPosition, float3 RayDirection, float Roughness, float3 BentNormal,
                float IndirectIrradiance, uint ShadingModelID, uint NumCulledReflectionCaptures, uint CaptureDataStartIndex)
            {
                // Indirect occlusion from DFAO, which should be applied to reflection captures and skylight specular, but not SSR
                float IndirectSpecularOcclusion = 1.0f;
                float3 ExtraIndirectSpecular = 0;

                float IndirectDiffuseOcclusion = 0;
                GetDistanceFieldAOSpecularOcclusion(BentNormal, RayDirection, Roughness, 
                    ShadingModelID == SHADINGMODELID_TWOSIDED_FOLIAGE, IndirectSpecularOcclusion, 
                    IndirectDiffuseOcclusion, ExtraIndirectSpecular);
                // Apply DFAO to IndirectIrradiance before mixing with indirect specular
                IndirectIrradiance *= IndirectDiffuseOcclusion;

                const bool bCompositeSkylight = true;  //需要将天空盒考虑进来 
                return CompositeReflectionCapturesAndSkylight(
                    CompositeAlpha,
                    WorldPosition,
                    RayDirection,
                    Roughness,
                    IndirectIrradiance,
                    IndirectSpecularOcclusion,
                    ExtraIndirectSpecular,
                    NumCulledReflectionCaptures,
                    CaptureDataStartIndex,
                    0,
                    bCompositeSkylight);
            }

            float3 ReflectionEnvironment(FGBufferData GBuffer, float AmbientOcclusion, float2 BufferUV, float2 ScreenPosition, float4 SvPosition, float3 BentNormal, float3 SpecularColor)
            {
                const float PreExposure = 1.f;  //开放系数 

                float4 Color = float4(0, 0, 0, 1);
                float3 WorldPosition = mul(Matrix_Inv_VP, float4(ScreenPosition * GBuffer.Depth, GBuffer.Depth, 1)).xyz;
                float3 CameraToPixel = normalize(WorldPosition - CameraPosWS);
                float IndirectIrradiance = GBuffer.IndirectIrradiance;  //总是1 

                float3 N = GBuffer.WorldNormal;
                float3 V = -CameraToPixel;

                float3 R = 2 * dot(V, N) * N - V;
                float NoV = saturate(dot(N, V));

                // Point lobe in off-specular peak direction
                R = GetOffSpecularPeakReflectionDir(N, R, GBuffer.Roughness);

                // Note: this texture may also contain planar reflections
                float4 SSR = SAMPLE_TEXTURE2D(_SSR, sampler_SSR, BufferUV);
                
                Color.rgb = SSR.rgb;
                Color.a = 1 - SSR.a;

                UNITY_BRANCH 
                if (GBuffer.ShadingModelID == SHADINGMODELID_CLEAR_COAT)
                {
                    const float ClearCoat = GBuffer.CustomData.x;
                    Color = lerp(Color, float4(0, 0, 0, 1), ClearCoat);
                }

                float AO = GBuffer.GBufferAO * AmbientOcclusion;
                float RoughnessSq = GBuffer.Roughness * GBuffer.Roughness;
                float SpecularOcclusion = GetSpecularOcclusion(NoV, RoughnessSq, AO);
                Color.a *= SpecularOcclusion;
                
                //获取采样IBL必须的跳转Index，以及多少张IBL能影响当前像素  
                uint DataStartIndex = 0;
                uint NumCulledReflectionCaptures = 0;
                GetAffectedReflectionCapturesAndNextJumpIndex(GBuffer, SvPosition, DataStartIndex, NumCulledReflectionCaptures);

                //Top of regular reflection or bottom layer of clear coat.
                Color.rgb += PreExposure * GatherRadiance(Color.a, WorldPosition, R, GBuffer.Roughness, BentNormal,
                    IndirectIrradiance, GBuffer.ShadingModelID, NumCulledReflectionCaptures, DataStartIndex);

                UNITY_BRANCH
                if (GBuffer.ShadingModelID == SHADINGMODELID_CLEAR_COAT)
                {
                    //todo 
                }
                else
                {
                    Color.rgb *= EnvBRDF(SpecularColor, GBuffer.Roughness, NoV);
                }

                // Transform NaNs to black, transform negative colors to black.
                return -min(-Color.rgb, 0.0);
            }

            v2f vert (appdata IN)
            {
                v2f OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                //UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
                OUT.vertex = TransformObjectToHClip(IN.vertex);
                OUT.uv = IN.uv;

                return OUT;
            }

            half4 frag (v2f IN) : SV_Target
            {
                half4 test = half4(0, 0, 0, 0);  //JUST FOR SHOW CASE 

                float2 BufferUV = SvPositionToBufferUV(IN.vertex);
                float2 ScreenPosition = SvPositionToScreenPosition(IN.vertex).xy;

                FGBufferData GBuffer = GetGBufferDataFromSceneTextures(IN.uv);

                float3 DiffuseColor = GBuffer.DiffuseColor;
                float3 SpecularColor = GBuffer.SpecularColor;

                //RemapClearCoatDiffuseAndSpecularColor(GBuffer, ScreenPosition, DiffuseColor, SpecularColor);
                float AmbientOcclusion = SAMPLE_TEXTURE2D(_SSAO, sampler_SSAO, IN.uv).r;

                uint ShadingModelID = GBuffer.ShadingModelID;
                float3 BentNormal = UpsampleDFAO(BufferUV, GBuffer.Depth, GBuffer.WorldNormal);

                float4 OutColor = 0; 

                UNITY_BRANCH
                if (ShadingModelID != SHADINGMODELID_UNLIT)
                {
                    float3 SkyLighting = SkyLightDiffuse(GBuffer, AmbientOcclusion, BufferUV, ScreenPosition, BentNormal, DiffuseColor);

                    OutColor.rgb = SkyLighting;
                    OutColor.a = 0;
                }

                float3 ref = 0;

                UNITY_BRANCH
                if (ShadingModelID != SHADINGMODELID_UNLIT && ShadingModelID != SHADINGMODELID_HAIR)
                {
                    ref = ReflectionEnvironment(GBuffer, AmbientOcclusion, BufferUV, ScreenPosition, IN.vertex, BentNormal, SpecularColor);
                    OutColor.rgb += ref;
                }

                test.xyz = (OutColor.rgb);
                // test.xyz = (ref.rgb); //用于输出 ReflectionEnvironment 

                return test;
            }
            ENDHLSL 
        }
    }
}
