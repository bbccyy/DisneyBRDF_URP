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
        [NoScaleOffset] _Spec("Spec", 2D) = "white" {}

    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Blend One One

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
            TEXTURE2D(_Spec); SAMPLER(sampler_Spec);
            TEXTURECUBE(_IBL); SAMPLER(sampler_IBL);
            TEXTURECUBE(_Sky); SAMPLER(sampler_Sky);


            static float4 View_ViewRectMin = float4(0, 0, 0, 0);
            static float2 AOBufferBilinearUVMax = float2(0.99823, 0.99894);
            static float AOMaxViewDistance = 20000;
            static float DistanceFadeScale = 0.00017;


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


            float3 UpsampleDFAO(float2 BufferUV, float SceneDepth, float3 WorldNormal)
            {
                // Distance field AO was computed at 0,0 regardless of viewrect min
                float2 DistanceFieldUVs = BufferUV - View_ViewRectMin.xy * View_BufferSizeAndInvSize.zw;
                DistanceFieldUVs = min(DistanceFieldUVs, AOBufferBilinearUVMax);

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

                // Fade to unoccluded in the distance
                float FadeAlpha = saturate((AOMaxViewDistance - SceneDepth) * DistanceFadeScale);
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

                test.xyz = BentNormal;

                return test;
            }
            ENDHLSL 
        }
    }
}
