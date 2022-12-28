Shader "Hair/Marschner MultiLight"
{
    Properties
    {
        _StrandMap ("Strand Map", 2D) = "white" {}
        _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Bump Scale", Range(0, 1)) = 1.0
        _Roughness ("Roughness", Range(0, 1)) = 0.1
        _Melanin ("Medulla Absorption", Range(0, 1)) = 1.0
        _Redness ("Redness", Range(0, 1)) = 1.0
        _DyeColor ("Dye Color", Color) = (0, 0, 0, 0)
        _Metallic ("Matellic", Range(0, 1)) = 1.0
        _SpecularScale ("Specular Scale", Range(0, 5)) = 1.0
        _AlphaThreshold ("Alpha Threshold", Range(0, 1)) = 0.5
    }
    SubShader
    {
        Tags { "RenderType" = "TransparentCutout" "Queue" = "AlphaTest" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True"}

        Pass
        {
            Name "Hair Forward"
            Tags {"LightMode" = "UniversalForward"}

            // CULL Back
            // //Blend One Zero
            // Blend SrcAlpha OneMinusSrcAlpha
            // ZTest LEqual
            // ZWrite Off

            CULL Off
            Blend One Zero
            ZTest LEqual
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local _ALPHACLIP_ON
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK

            #include "hair_func.cginc"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"

            #define _ADDITIONAL_LIGHTS

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 tangentWS : TEXCOORD2;
                float3 bitangentWS : TEXCOORD3;
                float4 viewDirWS : TEXCOORD4;
                float3 positionWS : TEXCOORD5;
                float2 normalUV : TEXCOORD6;
            };

            // sampler2D _StrandMap;
            TEXTURE2D(_StrandMap); SAMPLER(sampler_StrandMap);
            //TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);

            CBUFFER_START(UnityPerMaterial)
            float4 _StrandMap_ST;
            float4 _BumpMap_ST;

            float _Metallic;
            float _BumpScale;
            float _Roughness;
            float _Melanin;
            float _Redness;
            float4 _DyeColor;
            float _SpecularScale;
            float _AlphaThreshold;
            CBUFFER_END

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.positionWS = TransformObjectToWorld(v.vertex.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _StrandMap);

                VertexNormalInputs tbn = GetVertexNormalInputs(v.normalOS, v.tangentOS);
                o.normalWS = tbn.normalWS;
                o.tangentWS = tbn.tangentWS;
                o.bitangentWS = tbn.bitangentWS;
                o.normalUV = TRANSFORM_TEX(v.uv, _BumpMap);
                // UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            BRDFSingleLightOutput CalculateBRDFForSingleLight(
                Light light, half3 viewDir, float3 NormalWS, 
                float3 Ns, float3 outColor, float isMainLight){
                BRDFSingleLightOutput output = (BRDFSingleLightOutput)0;

                float3 lightColor = light.color;
                half3 lightDir = normalize(TransformObjectToWorldDir(light.direction));

                half3 lightDirS = 0;
                //This is a trick!!! Not a feature!!!
                //Just to handle wrong nodel normals
                lightDirS.x = normalize(TransformObjectToWorldDir(light.direction)).x;
                lightDirS.y = normalize(TransformObjectToWorldDir(light.direction)).y;
                lightDirS.z = normalize(TransformObjectToWorldDir(light.direction)).z;

                float Shift = 0.035;
                float alpha[] =
                {
                	-Shift * 2,
                	Shift,
                	Shift * 3.5,
                };

                float roughness = clamp(_Roughness, 0.01, 1);
                float lambda[] =
	            {
	            	pow2(roughness),
	            	saturate((pow2(roughness) / 2) * 3.57f),
	            	pow2(roughness) * 2,
	            };

                HairAngles hairAngles = (HairAngles)0;
                //diffuse
                hairAngles.NdotL = dot(NormalWS, lightDir);
                //float3 diffuse = KajiyaDiffuse(outColor, _Metallic, lightDir, -viewDirS, Ns, -NdotL);
                float3 diffuse = KajiyaDiffuse(outColor, _Metallic, lightDir, viewDir, Ns, -hairAngles.NdotL);

                float atten = light.shadowAttenuation;

                //Specular
                //s=mp*np*fp*tp
                hairAngles.LdotV = dot(lightDirS, viewDir);
                hairAngles.sinThetaL = clamp(dot(Ns, lightDirS), -1.0f, 1.0f);
                hairAngles.sinThetaV = clamp(dot(Ns, viewDir), -1.0f, 1.0f);
                hairAngles.cosThetaD = cos(0.5 * abs(asin(hairAngles.sinThetaV) - asin(hairAngles.sinThetaL)));
                hairAngles.thetaD = acos(hairAngles.cosThetaD);

                //light and view dir on normal plane
                hairAngles.LOnNp = lightDirS - hairAngles.sinThetaL * Ns;
                hairAngles.VOnNp = viewDir - hairAngles.sinThetaV * Ns;
                hairAngles.cosPhi = dot(hairAngles.LOnNp, hairAngles.VOnNp) 
                                    * rsqrt(dot(hairAngles.LOnNp, hairAngles.LOnNp) 
                                    * dot(hairAngles.VOnNp, hairAngles.VOnNp) + 1e-4);
                hairAngles.cosHalfPhi = sqrt(saturate(0.5 + 0.5 * hairAngles.cosPhi));

                float3 S = 0;
                float3 SR = SRvalue(alpha[0], lambda[0], hairAngles);
                float3 STT = STTvalue(alpha[1], lambda[1], hairAngles, outColor) * isMainLight;
                float3 STRT = STRTvalue(alpha[2], lambda[2], hairAngles, outColor);

                S = saturate(SR + STT * atten + STRT);
                //Specular end
                //*********************************

                output.SingleLightBRDF = (diffuse + S * _SpecularScale) * lightColor;
                //output.SingleLightBRDF = STT * atten;

                return output;
            }

            float4 frag (v2f i) : SV_Target
            {
                //Hair color
                float3 dyeColor = clamp(_DyeColor, 1e-5, 1);
                float3 Medula = clamp(_Melanin, 0.01, 1);
                float3 absorptionColor = GetHairColorFromMelanin(Medula, _Redness, dyeColor);                
                float3 outColor = lerp(absorptionColor, _DyeColor, 0.1f);

                //Normal from normal map
                float4 normalTXS = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.normalUV);
                float3 normalTS = UnpackNormalScale(normalTXS, _BumpScale).xyz;

                half3 modelNormalWS = i.normalWS.xyz;
                i.normalWS = TransformTangentToWorld(normalTS, half3x3(i.tangentWS.xyz, i.bitangentWS.xyz, i.normalWS.xyz));

                //Modified vector creaeted from normal map.
                //Convert z & y of normal in tangent space.
                //Get a vector like bitangent, parallel to hair pointing toward root, but from normal map.
                float3 ModifiedNormalTS = 0;
                ModifiedNormalTS.x = UnpackNormalScale(normalTXS, _BumpScale / 10).x;
                ModifiedNormalTS.y = UnpackNormalScale(normalTXS, _BumpScale / 10).z;
                ModifiedNormalTS.z = -UnpackNormalScale(normalTXS, _BumpScale / 10).y;
                float3 Ns = TransformTangentToWorld(ModifiedNormalTS, half3x3(i.tangentWS.xyz, i.bitangentWS.xyz, i.normalWS.xyz));

                //Light
                float4 SHADOW_COORDS = TransformWorldToShadowCoord(i.positionWS);
                Light Mainlight = GetMainLight(SHADOW_COORDS);
                // float3 MainLightColor = Mainlight.color;
                // half3 MainLightDir = normalize(TransformObjectToWorldDir(Mainlight.direction));

                half3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.positionWS);

                //Sample the strand texture.
                //Make alpha clip.
                float Mask = SAMPLE_TEXTURE2D(_StrandMap, sampler_StrandMap, i.uv).a;
                clip(SAMPLE_TEXTURE2D(_StrandMap, sampler_StrandMap, i.uv).a - _AlphaThreshold);
                
                float4 col = (0, 0, 0, 0);

                float3 MainBRDF = CalculateBRDFForSingleLight(Mainlight, viewDir, i.normalWS, Ns, outColor, 1.0).SingleLightBRDF;
                //col.xyz = MainBRDF;
            #ifdef _ADDITIONAL_LIGHTS
                uint lightnumbers = GetAdditionalLightsCount();
                for(uint index = 0; index < lightnumbers; index++){
                    float3 brdfTemp = 0;
                    Light light = GetAdditionalLight(index, i.positionWS);
                    half3 lightDir = normalize(TransformObjectToWorldDir(light.direction));
                    float3 lightColor = light.color;

                    brdfTemp = CalculateBRDFForSingleLight(light, viewDir, i.normalWS, Ns, outColor, 0).SingleLightBRDF;
                    //col.xyz = brdfTemp;
                    MainBRDF += brdfTemp;
                }
            #endif
                col.xyz = MainBRDF;
                //col.w = clamp(Mask + 0.5, 0.5, 1.0);
                col.w = Mask;

                return col;
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

    }
}
