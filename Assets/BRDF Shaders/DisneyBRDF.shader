Shader "Example/DisneyBRDF"
{
    Properties
    {
        //Disney coefficients
        [MainTexture] _BaseMap   ("Base Color", 2D)                  = "white" {}
        _Metallic                ("Metallic", Range(0, 1))           = 0.0
        _Smoothness              ("Smoothness", Range(0, 1))         = 0.5
        _Subsurface              ("Subsurface", Range(0, 1))         = 0.0
        _Specular                ("Specular", Range(0, 1))           = 0.5
        _SpecularTint            ("SpecularTint", Range(0, 1))       = 0.0
        _Anisotropic             ("Anisotropic", Range(0, 1))        = 0.0
        _Sheen                   ("Sheen", Range(0, 1))              = 0.0
        _SheenTint               ("SheenTint", Range(0, 1))          = 0.5
        _Clearcoat               ("Clearcoat", Range(0, 1))          = 0.0
        _ClearcoatGloss          ("ClearcoatGloss", Range(0, 1))     = 0.0

        //Normal control
        _BumpScale               ("Normal Scale", Range(0, 1))       = 1.0
        _BumpMap                 ("Normal Map", 2D)                  = "bump"  {}

        //GI control
        _IrradianceMap           ("Irradiance Map", CUBE)            = "white" {}
        _LUT                     ("LUT", 2D)                         = "white" {}
        _PrefilterMap            ("Prefilter Map", CUBE)             = "white" {}
        _AO                      ("AO", 2D)                          = "white" {}
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True" }

        Pass
        {
            Name "DisneyForward"
            Tags {"LightMode" = "UniversalForward"}

            CULL OFF

            HLSLPROGRAM
            #pragma prefer_hlslcc gles          //TODO
            #pragma exclude_renderers d3d11_9x  //TODO
            #pragma target 2.0                  //TODO

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

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

            Varyings vert (Attributes IN)
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

            float4 frag(Varyings IN) : SV_Target
            {
                //light dir
                float4 SHADOW_COORDS = TransformWorldToShadowCoord(IN.positionWS);
                Light light = GetMainLight(SHADOW_COORDS);
                half3 lightDirWS = normalize(TransformObjectToWorldDir(light.direction));

                //view dir
                half3 viewDirWS = normalize(_WorldSpaceCameraPos.xyz - IN.positionWS);

                //ligth col
                float3 lightColor = _MainLightColor.rgb;

                //H
                float3 halfVector = normalize(lightDirWS + viewDirWS);

                //roughness
                float perceptualRoughness = 1.0 - _Smoothness;
                float roughness = perceptualRoughness * perceptualRoughness;
                float squareRoughness = roughness * roughness;

                //normal
#ifdef _NORMALMAP 
                //half3 normalTS = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv).rgb * _BumpScale;
                half3 normalTS = SampleNormal(IN.uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);
                IN.normalWS = TransformTangentToWorld(normalTS, half3x3(IN.tangentWS.xyz, IN.bitangentWS.xyz, IN.normalWS.xyz));
#endif

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

                //albedo 
                half4 albedoAlpha = SampleAlbedoAlpha(IN.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
                half3 Albedo = albedoAlpha.rgb;

                //rip off the energy from albedo 
                float Cdlum = 0.3 * Albedo.r + 0.6 * Albedo.g + 0.1 * Albedo.b;
                float3 Ctint = Cdlum > 0 ? (Albedo / Cdlum) : float3(1, 1, 1);
                float3 Csheen = lerp(float3(1, 1, 1), Ctint, _SheenTint);

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
                float Gs = Gnv * Gnl;

                //F term
                float3 Fs = Specular_Fresnel(Ctint, Albedo, Flh, _Metallic);

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
                float3 diffuse = (Albedo * lerp(Fd, ss, _Subsurface) / UNITY_PI + Fsheen) * (1.0 - _Metallic); 

                float3 directLight = (diffuse + specular) * lightColor * nl;
                directLight *= light.shadowAttenuation;

                //GI Diffuse
                F0 = lerp(kDieletricSpec.rgb, Albedo, _Metallic);
                float3 F_ibl = fresnelSchlickRoughness(nv, F0, roughness);   //perceptualRoughness
                float kd_ibl = (1 - F_ibl.r) * (1 - _Metallic);  
                float3 irradiance = SAMPLE_TEXTURECUBE_LOD(_IrradianceMap, sampler_IrradianceMap, IN.normalWS, 0).rgb;
                float3 indiffuse = kd_ibl * Albedo * irradiance;

                //GI Specular
                float3 reflectVector = reflect(-viewDirWS, IN.normalWS); 
                float3 prefilter_Specular = SAMPLE_TEXTURECUBE_LOD(_PrefilterMap, sampler_PrefilterMap, reflectVector, 0).rgb;
                float2 envBRDF = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, float2(lerp(0, 0.99, nv), lerp(0, 0.99, roughness))).rg;  //envBRDF IBL
                //combine GI Specular 
                float3 inspecular = prefilter_Specular * (envBRDF.r * F_ibl + envBRDF.g); 

                //AO 
                half AO = SAMPLE_TEXTURE2D(_AO, sampler_AO, IN.uv).r;
                float3 indirectLight = (indiffuse + inspecular) * AO;

                //ALL IN ONE
                float4 col = float4(directLight + indirectLight, 1);  
                //float4 col = float4(directLight, 1); 

                // apply fog
                col.xyz = MixFog(col.xyz, IN.fogCoord);
                
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
