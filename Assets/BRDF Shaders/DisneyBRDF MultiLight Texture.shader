Shader "Example/DisneyBRDF MultiLight Texture"
{
    Properties
    {
        //Disney coefficients
        [MainTexture] _BaseMap  ("Base Color", 2D)              = "white" {}
        _Subsurface             ("Subsurface", Range(0, 1))     = 0.0
        _Specular               ("Specular", Range(0, 1))       = 0.5
        _SpecularTint           ("SpecularTint", Range(0, 1))   = 0.0
        _Anisotropic            ("Anisotropic", Range(0, 1))    = 0.0
        _Sheen                  ("Sheen", Range(0, 1))          = 0.0
        _SheenTint              ("SheenTint", Range(0, 1))      = 0.5
        _Clearcoat              ("Clearcoat", Range(0, 1))      = 0.0
        _ClearcoatGloss         ("ClearcoatGloss", Range(0, 1)) = 0.0

        //Normal control
        _BumpScale                      ("Normal Scale", Range(0, 1))       = 1.0
        [NoScaleOffset]_BumpMap         ("Normal Map", 2D)                  = "bump"  {}

        //Metalic
        [NoScaleOffset]_Metallic        ("Metallic Map", 2D)                = "white" {}

        //Roughness
        [NoScaleOffset]_Roughness       ("Roughness Map", 2D)               = "bump"  {}
        _RoughnessOffset                ("Roughness Offset", Range(-1,1))   = 0
        _RoughnessScale                 ("Roughness Scale", Range(0, 1))    = 0

        //GI control
        [NoScaleOffset]_IrradianceMap   ("Irradiance Map", CUBE)            = "white" {}
        [NoScaleOffset]_LUT             ("LUT", 2D)                         = "white" {}
        [NoScaleOffset]_PrefilterMap    ("Prefilter Map", CUBE)             = "white" {}
        [NoScaleOffset]_AO              ("AO", 2D)                          = "white" {}
        _PrefilterScale                 ("Prefilter Scale", Range(0, 1))    = 1.0
        _IrradianceScale                ("Irradiance Scale", Range(0, 3))   = 1.0
        
        //Overall brightness
        _BrightnessScale                ("Brightness Scale", Range(1, 3))   = 1
    }

        SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True" }

        Pass
        {
            Name "DisneyForward one"
            Tags {"LightMode" = "UniversalForward"}

            CULL Off
            Blend One Zero
            ZTest LEqual
            ZWrite On


            HLSLPROGRAM
            #pragma prefer_hlslcc gles          //TODO
            #pragma exclude_renderers d3d11_9x  //TODO
            #pragma target 2.0                  //TODO

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma shader_feature _ALPHATEST_ON

            #pragma shader_feature _NORMALMAP

        /*#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
        #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
        #pragma multi_compile _ _SHADOWS_SOFT
        #pragma multi_compile _ Anti_Aliasing_ON*/

        #define _NORMALMAP
        #define _MAIN_LIGHT_SHADOWS
        #define _MAIN_LIGHT_SHADOWS_CASCADE
        #define _SHADOWS_SOFT
        #define _ALPHATEST_ON
        #define _ADDITIONAL_LIGHTS

        #define _ENV_BRDF_UNITY

        #pragma multi_compile _ LIGHTMAP_ON
        #pragma multi_compile _ DIRLIGHTMAP_COMBINED
        #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE

        #define BRDF_TEX 1

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
        #include "brdf_comm.cginc"

        //TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
        //TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);

            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
                float2 lightmapUV : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float2 uv1 : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float3 normalWS : TEXCOORD3;
                float3 tangentWS : TEXCOORD4;
                float3 bitangentWS : TEXCOORD5;
                float4 viewDirWS : TEXCOORD6;
                float  fogCoord : TEXCOORD7;    //TODO: combined to other texcoord 

                UNITY_VERTEX_INPUT_INSTANCE_ID
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

                OUT.uv1 = IN.lightmapUV;

                OUT.fogCoord = ComputeFogFactor(OUT.positionCS.z);
                return OUT;
            }

            half3 EnvironmentBRDFSpecular(half3 F0, half grazingTerm, half fresnelTerm, half roughness2)
            {
                float surfaceReduction = 1.0 / (roughness2 + 1.0);
                return half3(surfaceReduction * lerp(F0, grazingTerm, fresnelTerm));
            }
            half3 EnvironmentBRDF(half3 diffuse, half3 indirectDiffuse, half3 indirectSpecular,
                half3 F0, half grazingTerm, half fresnelTerm, half roughness2)
            {
                half3 c = indirectDiffuse * diffuse;
                c += indirectSpecular * EnvironmentBRDFSpecular(F0, grazingTerm, fresnelTerm, roughness2);
                return c;
            }
            half3 HDREnvironmentReflection(half3 reflectVector, float3 positionWS, half perceptualRoughness)
            {
                half3 irradiance;
#ifdef _REFLECTION_PROBE_BOX_PROJECTION
                reflectVector = BoxProjectedCubemapDirection(reflectVector, positionWS, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
#endif
                half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
                half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip));
                irradiance = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
                return irradiance;
            }

            half3 UnityGIColor(Varyings IN, half3 Albedo, half3 reflectVector, half NdotV, half perceptualRoughness, half3 F0)
            {
                half3 brdfDiffuse = Albedo * (half3(1.0, 1.0, 1.0) - Albedo);
                half3 bakedGI = SampleSH(IN.normalWS);
                half fresnelTerm = Pow4(1.0 - NdotV);
                half3 indirectDiffuse = bakedGI;
                half3 indirectSpecular = HDREnvironmentReflection(reflectVector, IN.positionWS, perceptualRoughness);
                half grazingTerm = saturate(1 - perceptualRoughness);
                half roughness2 = saturate(perceptualRoughness * perceptualRoughness);

                half3 color = EnvironmentBRDF(brdfDiffuse, indirectDiffuse, indirectSpecular, F0, grazingTerm, fresnelTerm, roughness2);
                return color;
            }

            FragLightOutput FragmentBRDFPerLight(Varyings IN, Light light, half3 viewDirWS, float atten,
                float3 Albedo, float roughness, float squareRoughness, 
                float metalic, float3 Ctint, float3 Csheen)
            {
                //light dir
                half3 lightDirWS = normalize(TransformObjectToWorldDir(light.direction));

                //ligth col
                float3 lightColor = light.color;

                //H
                float3 halfVector = normalize(lightDirWS + viewDirWS);

                //helper values...
                float nl = max(saturate(dot(IN.normalWS, lightDirWS)), 0.000001);
                float nv = max(saturate(dot(IN.normalWS, viewDirWS)), 0.000001);
                float vh = max(saturate(dot(viewDirWS, halfVector)), 0.000001);
                float nh = max(saturate(dot(IN.normalWS, halfVector)), 0.000001);
                float lh = max(saturate(dot(lightDirWS, halfVector)), 0.000001);

                float aspect = sqrt(1.0 - _Anisotropic * 0.9);
                float ax = max(0.001, squareRoughness / aspect);
                float ay = max(0.001, squareRoughness * aspect);
                float hx = max(saturate(dot(halfVector, IN.tangentWS)), 0.000001);
                float hy = max(saturate(dot(halfVector, IN.bitangentWS)), 0.000001);

                //Fresnel values
                float Fnl = SchlickFresnel(nl);
                float Fnv = SchlickFresnel(nv);
                float Flh = SchlickFresnel(lh);

                //directLight Specular
                //D term
                float Ds = Disney_Specular_GTR2_iso(nh, roughness);

                //G term
                float Gnv = SmithsG_GGX_aniso(nv, dot(viewDirWS, hx), dot(viewDirWS, hy), ax, ay);
                float Gnl = SmithsG_GGX_aniso(nl, dot(lightDirWS, hx), dot(lightDirWS, hy), ax, ay);
                float Gs = saturate(Gnv) * saturate(Gnl);

                //F term
                float3 Fs = Specular_Fresnel(Ctint, Albedo, Flh, metalic);

                //directLight clearcoat D F G
                float Dr = Disney_Clear_GTR1(nh, lerp(0.1, 0.001, _ClearcoatGloss));
                float3 F0 = float3(0.04, 0.04, 0.04);
                float3 Fr = lerp(F0, float3(1, 1, 1), Flh);
                float Gr = Disney_Clear_GGX(nv, nl, 0.25);

                //conbine specular part 
                float3 specular = Gs * Fs * Ds + Dr * Gr * Fr * 0.25 * _Clearcoat;

                //directLight Diffuse
                float Fd = Disney_Diffuse_Kfd(roughness, lh, Fnl, Fnv);
                float ss = Disney_Subsurface_ss(roughness, lh, Fnl, Fnv, nl, nv);
                float3 Fsheen = Flh * _Sheen * Csheen;
                float3 diffuse = (Albedo * lerp(Fd, ss, _Subsurface) / UNITY_PI + Fsheen) * (1.0 - metalic);

                float3 directLight = (diffuse + specular) * lightColor * nl;
                directLight *= atten;

                FragLightOutput output = (FragLightOutput)0;
                output.directLight = directLight;

                return output;
            }

            float4 frag(Varyings IN) : SV_Target
            {

                //normal
#ifdef _NORMALMAP 
                half3 normalTS = SampleNormal(IN.uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);
                half3 modelNormalWS = IN.normalWS.xyz;
                IN.normalWS = TransformTangentToWorld(normalTS, half3x3(IN.tangentWS.xyz, IN.bitangentWS.xyz, IN.normalWS.xyz));
#endif

                //albedo 
                half4 albedoAlpha = SampleAlbedoAlpha(IN.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
                half3 Albedo = albedoAlpha.rgb;

                //view dir
                half3 viewDirWS = normalize(_WorldSpaceCameraPos.xyz - IN.positionWS);

                //roughness
                float roughness = SAMPLE_TEXTURE2D(_Roughness, sampler_Roughness, IN.uv).r;
                roughness = saturate((roughness + _RoughnessOffset) * _RoughnessScale);
                float squareRoughness = roughness * roughness;

                //metalic
                float metalic = SAMPLE_TEXTURE2D(_Metallic, sampler_Metallic, IN.uv).r;
                metalic = saturate(metalic);

                //rip off the energy from albedo 
                float Cdlum = 0.3 * Albedo.r + 0.6 * Albedo.g + 0.1 * Albedo.b;
                float3 Ctint = Cdlum > 0 ? (Albedo / Cdlum) : float3(1, 1, 1);
                float3 Csheen = lerp(float3(1, 1, 1), Ctint, _SheenTint);

                //mainlight && main atten
                float4 SHADOW_COORDS = TransformWorldToShadowCoord(IN.positionWS);
                Light mainlight = GetMainLight(SHADOW_COORDS);
                float atten = mainlight.shadowAttenuation;

                //mainlight contribution
                FragLightOutput directLightOutput = FragmentBRDFPerLight(IN, mainlight, viewDirWS, 
                    atten, Albedo, roughness, squareRoughness, metalic, Ctint, Csheen);
                float3 directLight = directLightOutput.directLight;

#ifdef _ADDITIONAL_LIGHTS
                uint pixelLightCount = GetAdditionalLightsCount();
                for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
                {
                    Light light = GetAdditionalLight(lightIndex, IN.positionWS);
                    FragLightOutput tmp = FragmentBRDFPerLight(IN, light, viewDirWS, light.shadowAttenuation, 
                        Albedo, roughness, squareRoughness, metalic, Ctint, Csheen);
                    directLight += tmp.directLight;
                }
#endif
                float nv = max(saturate(dot(IN.normalWS, viewDirWS)), 0.000001);
                float3 reflectVector = reflect(-viewDirWS, IN.normalWS);
                float3 F0 = lerp(kDieletricSpec.rgb, Albedo, metalic);

                float3 indirectLight = 0;
#ifdef _ENV_BRDF_UNITY
                //half mip = PerceptualRoughnessToMipmapLevel(roughness) + 3;
                //half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip);
                //half3 skyboxLight = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
                //directLight += (skyboxLight * nv * nv * (Albedo + float3(0.05, 0.05, 0.05)) * 0.2);
                indirectLight = UnityGIColor(IN, Albedo, reflectVector, nv, roughness, F0);
                indirectLight *= _IrradianceScale;
#else
                //Use Irradiance map + Pre-filter map
                //GI Diffuse              
                float3 F_ibl = fresnelSchlickRoughness(nv, F0, roughness);   //perceptualRoughness
                float kd_ibl = (1 - F_ibl.r) * (1 - metalic);
                float3 irradiance = SAMPLE_TEXTURECUBE_LOD(_IrradianceMap, sampler_IrradianceMap, IN.normalWS, 0).rgb;
                float3 indiffuse = kd_ibl * Albedo * irradiance * _IrradianceScale;

                //GI Specular
                float3 prefilter_Specular = SAMPLE_TEXTURECUBE_LOD(_PrefilterMap, sampler_PrefilterMap, reflectVector, 0).rgb;
                float2 envBRDF = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, float2(lerp(0, 0.99, nv), lerp(0, 0.99, roughness))).rg;  //envBRDF IBL
                //combine GI Specular 
                float3 inspecular = prefilter_Specular * (envBRDF.r * F_ibl + envBRDF.g) * _PrefilterScale;
                indirectLight = indiffuse + inspecular;
#endif

                //AO 
                half AO = SAMPLE_TEXTURE2D(_AO, sampler_AO, IN.uv).r;
                indirectLight *= AO;

                //ALL IN ONE
                float4 col = float4(directLight + indirectLight, 1);

                // apply fog
                col.xyz = MixFog(col.xyz, IN.fogCoord);

                //overall brightness control 
                col.xyz *= _BrightnessScale; 
                //col.xyz = float3(.04,.04,.04);

                return col;
            }
            ENDHLSL
        }

        /*
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            Cull Off
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM

            // 设置关键字
            #pragma shader_feature _ALPHATEST_ON

            #pragma vertex vert
            #pragma fragment frag

           #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;

            struct Attributes
            {
                float4 positionOS: POSITION;
                float3 normalOS: NORMAL;
            };

            struct Varyings
            {
                float4 positionCS: SV_POSITION;
            };

            // 获取裁剪空间下的阴影坐标
            float4 GetShadowPositionHClips(Attributes input)
            {
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                // 获取阴影专用裁剪空间下的坐标
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));

                // 判断是否是在DirectX平台翻转过坐标
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif

                return positionCS;
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = GetShadowPositionHClips(input);
                return output;
            }


            half4 frag(Varyings input) : SV_TARGET
            {
                return 0;
            }

            ENDHLSL

        }
        */
        
        Pass
        {
            Name "ShadowCaster"
            Tags {"LightMode" = "ShadowCaster"}

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature _ALPHATEST_ON

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
