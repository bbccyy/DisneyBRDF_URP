Shader "Example/Preintegrated skin base"
{
    Properties
    {
        _Color("Main Color", Color) = (1,1,1,1)
        _BaseMap("Albedo", 2D) = "white" {}
        _BumpMap("Normal Map", 2D) = "bump" {}
        _SpecGlosDepthMap("Specular (R) Glosiness(G) Depth (B)", 2D) = "white" {}
        _Bumpiness("Bumpiness", Range(0,1)) = 0.9
        _SpecIntensity("Specular Intensity", Range(0,100)) = 1.0
        _SpecRoughness("Specular Roughness", Range(0.3,1)) = 0.7
        _LookupDiffuseSpec("Lookup Map: Diffuse Falloff(RGB) Specular(A)", 2D) = "gray" {}
        _ScatteringOffset("Scattering Boost", Range(0,1)) = 0.0
        _ScatteringPower("Scattering Power", Range(0,2)) = 1.0
        [NoScaleOffset]_AO("AO", 2D) = "white" {}
        _GIIntensity("GI Inetensity", Range(0, 1)) = 0   
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True" }
        LOD 100

        Pass
        {
            Name "Skin base"
            Tags {"LightMode" = "UniversalForward"}

            CULL Off
            //Blend One Zero
            //ZTest LEqual
            //ZWrite On

            HLSLPROGRAM

            #pragma prefer_hlslcc gles          
            #pragma exclude_renderers d3d11_9x   
            #pragma target 2.0                  

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

            #pragma shader_feature _NORMALMAP

            #define _NORMALMAP
            #define _MAIN_LIGHT_SHADOWS
            #define _MAIN_LIGHT_SHADOWS_CASCADE
            #define _SHADOWS_SOFT
            #define _ALPHATEST_ON
            #define _ADDITIONAL_LIGHTS

            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"

            TEXTURE2D(_SpecGlosDepthMap); SAMPLER(sampler_SpecGlosDepthMap);
            TEXTURE2D(_LookupDiffuseSpec); SAMPLER(sampler_LookupDiffuseSpec);
            TEXTURE2D(_AO); SAMPLER(sampler_AO);

            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
                float4 _BaseMap_ST;
                float _Bumpiness;
                float _SpecIntensity;
                float _SpecRoughness;
                float _ScatteringOffset;
                float _ScatteringPower;
                float _GIIntensity;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 tangentWS : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
                float4 viewDirWS : TEXCOORD5;
                float  fogCoord : TEXCOORD6;  

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct PerLightOutput
            {
                float3 diff;
                float spec;
            };


            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionCS = TransformWorldToHClip(OUT.positionWS);

                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);

                VertexNormalInputs tbn = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);
                OUT.normalWS = tbn.normalWS;
                OUT.tangentWS = tbn.tangentWS;
                OUT.bitangentWS = tbn.bitangentWS;

                OUT.fogCoord = ComputeFogFactor(OUT.positionCS.z);
                return OUT;
            }

            PerLightOutput SkinPerLight(Light light, half3 viewDirWS, half3 NormalWS, float Specular, float Gloss, float Scattering)
            {
                PerLightOutput output = (PerLightOutput)0;

                //light dir
                half3 lightDirWS = normalize(TransformObjectToWorldDir(light.direction));

                //ligth col
                float3 lightColor = light.color;

                //H
                float3 h = lightDirWS + viewDirWS;
                float3 H = normalize(h);

                float NdotL = max(saturate(dot(NormalWS, lightDirWS)), 0.000001);
                float VdotH = max(saturate(dot(viewDirWS, H)), 0.000001);
                float NdotH = max(saturate(dot(NormalWS, H)), 0.000001);

                //float atten = saturate(light.shadowAttenuation * 1.5);
                float atten = 1;//temporarily block any receiving shadow 
                float diffNdotL = 0.5 + 0.5 * NdotL;

                //LookupDiffuseSpec 
                float3 diff = 2.0 * SAMPLE_TEXTURE2D(_LookupDiffuseSpec, sampler_LookupDiffuseSpec, float2(diffNdotL, Scattering)).rgb;
                diff *= atten;
                diff *= lightColor;

                //specluar
                float specDiff = 2.0 * SAMPLE_TEXTURE2D(_LookupDiffuseSpec, sampler_LookupDiffuseSpec, float2(NdotH, Specular)).a;
                float PH = pow(abs(specDiff), 10.0);

                //Schlick Fresnel term
                float exponential = pow(1.0 - VdotH, 5.0);
                float fresnelReflectance = exponential + 0.028 * (1.0 - exponential);  //0.028 -> Skin's Fresnel reflectance at normal incidence 

                float frSpec = max(PH * fresnelReflectance / dot(h, h), 0);
                float specLevel = saturate(NdotL * Gloss * frSpec);

                output.diff = diff;
                output.spec = specLevel;

                return output;
            }

            //refers to:https://zhuanlan.zhihu.com/p/56052015 
            //also refers to:https://zhuanlan.zhihu.com/p/56052015 
            float4 frag(Varyings IN) : SV_Target
            {
                //adjust uv
                IN.uv = min(IN.uv, float2(0.99, 0.99));
                IN.uv = max(IN.uv, float2(0.01, 0.01));


                //mainlight & shadow 
                float4 SHADOW_COORDS = TransformWorldToShadowCoord(IN.positionWS);
                Light mainlight = GetMainLight(SHADOW_COORDS);

                //view dir
                half3 viewDirWS = normalize(_WorldSpaceCameraPos.xyz - IN.positionWS);

                //Spec + Roughness + Depth
                float3 SpecGlosDepth = SAMPLE_TEXTURE2D(_SpecGlosDepthMap, sampler_SpecGlosDepthMap, IN.uv).rgb;

                //normal
                half3 normalTS = SampleNormal(IN.uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _Bumpiness);
                half3 modelNormalWS = IN.normalWS.xyz;
                half3 NormalWS = TransformTangentToWorld(normalTS, half3x3(IN.tangentWS.xyz, IN.bitangentWS.xyz, IN.normalWS.xyz));

                //albedo 
                half4 albedoAlpha = SampleAlbedoAlpha(IN.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
                half3 Albedo = albedoAlpha.rgb * _Color.rgb;

                float Specular = SpecGlosDepth.g * _SpecRoughness; //roughness -> specular
                float Gloss = SpecGlosDepth.r * _SpecIntensity;

                half depth = SpecGlosDepth.b;
                float Scattering = saturate((depth + _ScatteringOffset) * _ScatteringPower);

                //AO 
                half AO = SAMPLE_TEXTURE2D(_AO, sampler_AO, IN.uv).r;

                //main light atten
                //float atten = saturate(mainlight.shadowAttenuation * 1.5);
                float atten = 1;  //temporarily block any receiving shadow 

                //mainlight contribution
                PerLightOutput diffspec = SkinPerLight(mainlight, viewDirWS, NormalWS, Specular, Gloss, Scattering);
                float3 diff = diffspec.diff;
                float specLevel = diffspec.spec;
                
#ifdef _ADDITIONAL_LIGHTS
                uint pixelLightCount = GetAdditionalLightsCount();
                for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
                {
                    Light light = GetAdditionalLight(lightIndex, IN.positionWS);
                    PerLightOutput tmp = SkinPerLight(light, viewDirWS, NormalWS, Specular, Gloss, Scattering);
                    diff += tmp.diff;
                    specLevel += tmp.spec;
                }
#endif

                //GI  todo...
                float3 indiff = Albedo * _GIIntensity * AO;

                //ALL IN ONE
                float4 col = float4(0,0,0,1);
                col.rgb = indiff + Albedo * diff * AO + (specLevel * atten).xxx;

                // apply fog
                col.xyz = MixFog(col.xyz, IN.fogCoord);
                //col.rgb = diffNdotL;

                return col;
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags {"LightMode" = "ShadowCaster"}

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature _ALPHATEST_ON
            //#pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float3 _LightDirection;
            float4 _ShadowBias;  //x:depth bias; y:normal bias
            half4 _MainLightShadowParams; //x:shadow strength; y:1->soft shadow, 0->otherwise

            float3 ApplyShadowBias(float3 positionWS, float3 normalWS, float3 lightDirection)
            {
                float inverseNdotL = 1.0 - saturate(dot(lightDirection, normalWS)); //theta 0 -> 90 : val 0 -> 1
                float scale = inverseNdotL * _ShadowBias.y;
                positionWS = lightDirection * _ShadowBias.xxx + positionWS;  //apply depth bias
                positionWS = normalWS * scale.xxx + positionWS;              //apply normal bias
                return positionWS;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                half3 normalWS = TransformObjectToWorldNormal(IN.normal);
                positionWS = ApplyShadowBias(positionWS, normalWS, _LightDirection);
                OUT.positionCS = TransformWorldToHClip(positionWS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                return OUT;
            }
            float4 frag(Varyings IN) : SV_Target
            {
#if _ALPHATEST_ON
                half4 col = tex2D(_BaseMap, IN.uv);
                clip(col.a - 0.001);
#endif
                return 0;
            }
            ENDHLSL
        }

        Pass{
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature _ALPHATEST_ON
            #pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half _Cutoff;
            CBUFFER_END

            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"

            ENDHLSL
        }
    }
}
