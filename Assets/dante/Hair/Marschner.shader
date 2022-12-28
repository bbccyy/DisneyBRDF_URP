Shader "Hair/Marschner"
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
        Tags { "RenderType"="TransparentCutout" "Queue" = "AlphaTest" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True"}

        Pass
        {
            Name "Hair Forward"
            Tags {"LightMode" = "UniversalForward"}

            CULL Off
            //Blend One Zero
            Blend SrcAlpha OneMinusSrcAlpha
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

            #include "hair_func.cginc"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"

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

            // BRDFSingleLightOutput CalculateBRDFForSingleLight(
            //     Light light, float3 viewDirS, float3 NormalWS, 
            //     float3 Ns, float3 outColor){
            //     BRDFSingleLightOutput output = (BRDFSingleLightOutput)0;

            //     float3 lightColor = light.color;
            //     half3 lightDir = normalize(TransformObjectToWorldDir(light.direction));

            //     float Shift = 0.035;
            //     float alpha[] =
            //     {
            //     	-Shift * 2,
            //     	Shift,
            //     	Shift * 3.5,
            //     };

            //     float roughness = clamp(_Roughness, 0.01, 1);
            //     float lambda[] =
	        //     {
	        //     	pow2(roughness),
	        //     	pow2(roughness) / 2,
	        //     	pow2(roughness) * 2,
	        //     };

            //     float LdotV = dot(lightDir, viewDirS);
            //     float sinThetaL = clamp(dot(Ns, lightDir), -1.0f, 1.0f);
            //     float sinThetaV = clamp(dot(Ns, lightDir), -1.0f, 1.0f);
            //     float cosThetaD = cos(0.5 * abs(asin(sinThetaV) - asin(sinThetaL)));
            //     float3 thetaD = acos(cosThetaD);

            //     //light and view dir on normal plane
            //     float3 LOnNp = lightDir - sinThetaL * Ns;
            //     float3 VOnNp = viewDirS - sinThetaV * Ns;
            //     float cosPhi = dot(LOnNp, VOnNp) * rsqrt(dot(LOnNp, LOnNp) * dot(VOnNp, VOnNp) + 1e-4);
            //     float cosHalfPhi = sqrt(saturate(0.5 + 0.5 * cosPhi));

            //     //diffuse
            //     float NdotL = dot(NormalWS, lightDir);
            //     float3 diffuse = KajiyaDiffuse(outColor, _Metallic, lightDir, -viewDirS, NormalWS, -NdotL);

            //     //Specular
            //     //s=mp*np*fp*tp
            //     float3 S = 0;
            //     float3 SR = SRvalue(alpha[0], lambda[0], cosHalfPhi, sinThetaV, sinThetaL, LdotV, NdotL);
            //     float3 STT = STTvalue(alpha[1], lambda[1], cosPhi, cosHalfPhi, sinThetaV, sinThetaL, cosThetaD, thetaD, outColor);
            //     float3 STRT = STRTvalue(alpha[2], lambda[2], cosPhi, sinThetaV, sinThetaL, cosThetaD, thetaD, outColor);

            //     S = saturate(SR + STT + STRT);

            //     output.SingleLightBRDF = (diffuse + S * _SpecularScale) * lightColor;

            //     return output;
            // }

            float4 frag (v2f i) : SV_Target
            {
                //Hair basics
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
	            	pow2(roughness) / 2,
	            	pow2(roughness) * 2,
	            };

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
                // ModifiedNormalTS.x = normalTS.x;
                // ModifiedNormalTS.y = normalTS.z;
                // ModifiedNormalTS.z = -normalTS.y;
                ModifiedNormalTS.x = UnpackNormalScale(normalTXS, _BumpScale / 10).x;
                ModifiedNormalTS.y = UnpackNormalScale(normalTXS, _BumpScale / 10).z;
                ModifiedNormalTS.z = -UnpackNormalScale(normalTXS, _BumpScale / 10).y;

                //Light
                float4 SHADOW_COORDS = TransformWorldToShadowCoord(i.positionWS);
                Light mainlight = GetMainLight(SHADOW_COORDS);
                float3 lightColor = mainlight.color;
                half3 MainLightDir = normalize(TransformObjectToWorldDir(mainlight.direction));

                half3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.positionWS);

                //Sample the strand texture.
                //Make alpha clip.
                float Mask = SAMPLE_TEXTURE2D(_StrandMap, sampler_StrandMap, i.uv).a;
                clip(SAMPLE_TEXTURE2D(_StrandMap, sampler_StrandMap, i.uv).a - _AlphaThreshold);
                
                //Three vector to calculate specular
                float3 Ns = TransformTangentToWorld(ModifiedNormalTS, half3x3(i.tangentWS.xyz, i.bitangentWS.xyz, i.normalWS.xyz));
                
                float3 lightDirS = 0;
                lightDirS.x = MainLightDir.x;
                lightDirS.y = MainLightDir.y;
                lightDirS.z = MainLightDir.z;

                float3 viewDirS = normalize(_WorldSpaceCameraPos.xyz - i.positionWS);

                //*********************************
                //Specular start
                float LdotV = dot(lightDirS, viewDirS);
                float sinThetaL = clamp(dot(Ns, lightDirS), -1.0f, 1.0f);
                float sinThetaV = clamp(dot(Ns, viewDirS), -1.0f, 1.0f);
                float cosThetaD = cos(0.5 * abs(asin(sinThetaV) - asin(sinThetaL)));
                float3 thetaD = acos(cosThetaD);

                //light and view dir on normal plane
                float3 LOnNp = lightDirS - sinThetaL * Ns;
                float3 VOnNp = viewDirS - sinThetaV * Ns;
                float cosPhi = dot(LOnNp, VOnNp) * rsqrt(dot(LOnNp, LOnNp) * dot(VOnNp, VOnNp) + 1e-4);
                float cosHalfPhi = sqrt(saturate(0.5 + 0.5 * cosPhi));

                float4 col = (0, 0, 0, 0);

                //diffuse
                float NdotL = dot(i.normalWS, MainLightDir);
                float3 diffuse = KajiyaDiffuse(outColor, _Metallic, MainLightDir, viewDir, Ns, -NdotL);

                //Specular
                //s=mp*np*fp*tp
                float3 S = 0;
                float3 SR = SRvalue(alpha[0], lambda[0], cosHalfPhi, sinThetaV, sinThetaL, LdotV, NdotL);
                float3 STT = STTvalue(alpha[1], lambda[1], cosPhi, cosHalfPhi, sinThetaV, sinThetaL, cosThetaD, thetaD, outColor);
                float3 STRT = STRTvalue(alpha[2], lambda[2], cosPhi, sinThetaV, sinThetaL, cosThetaD, thetaD, outColor);

                S = saturate(SR + STT + STRT);
                //Specular end
                //*********************************

                col.xyz = (diffuse + S * _SpecularScale) * lightColor;
                col.w = 1;
                //col.xyz = diffuse;

                return col;
            }
            ENDHLSL
        }
    }
}
