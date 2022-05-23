Shader "Test/Fire"
{
    Properties{
        _Mask           ("R:Outer Flame G:Inner Flame B:Alpha", 2D) = "blue" {}
        _Noise          ("Noise R:chann1 G:chann2", 2D) = "gray" {}
        _Noise1Params   ("Noise 1 Param, X:Scale Y:FlowSpeed Z:Intensity", vector) = (1.0, 0.2, 0.2, 1.0)
        _Noise2Params   ("Noise 2 Param, X:Scale Y:FlowSpeed Z:Intensity", vector) = (1.0, 0.2, 0.2, 1.0)
        [HDR]_Color1    ("Outer Flame Color", color) = (1,1,1,1)
        [HDR]_Color2    ("Inner Flame Color", color) = (1,1,1,1)
    }

    SubShader{
        Tags {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "ForceNoShadowCasting" = "True"
            "IgnoreProjector" = "True"
            "Queue" = "Transparent"
        }

        Pass {
            Name "Test Fire Flame"

            Blend One OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0 

            #define _MAIN_LIGHT_SHADOWS
            #define _MAIN_LIGHT_SHADOWS_CASCADE
            #define _SHADOWS_SOFT
            #define _ALPHATEST_ON
            #define _ADDITIONAL_LIGHTS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_Mask); SAMPLER(sampler_Mask);
            TEXTURE2D(_Noise); SAMPLER(sampler_Noise);

            CBUFFER_START(UnityPerMaterial)
                float4 _Mask_ST;
                half3 _Noise1Params;
                half3 _Noise2Params;
                half3 _Color1;
                half3 _Color2;
            CBUFFER_END

            struct VertexInput {
                float4 posOS : POSITION;   //顶点输入
                float2 uv :TEXCOORD0;      //纹理uv
            };

            struct VertexOutput {
                float4 posCS : SV_POSITION;  //顶点输出
                float2 uv0 : TEXCOORD0;      //采样Mask
                float2 uv1 : TEXCOORD1;      //采样Noise1
                float2 uv2 : TEXCOORD2;      //采样Noise2
            };

            VertexOutput vert(VertexInput IN) {
                VertexOutput OUT = (VertexOutput)0;
                OUT.posCS = TransformObjectToHClip(IN.posOS);
                OUT.uv0 = TRANSFORM_TEX(IN.uv, _Mask);  //支持Mask纹理的TilingOffset
                OUT.uv1 = OUT.uv0 * _Noise1Params.x + float2(0, frac(_Time.x * _Noise1Params.y));
                OUT.uv2 = OUT.uv0 * _Noise2Params.x + float2(0, frac(_Time.x * _Noise2Params.y));
                return OUT;
            }

            half4 frag(VertexOutput IN) : COLOR{
                //warp mask 负责扰动 
                half4 warpMask = SAMPLE_TEXTURE2D(_Mask, sampler_Mask, IN.uv0).b;

                //noise chann #1
                half var_Noise1 = SAMPLE_TEXTURE2D(_Noise, sampler_Noise, IN.uv1).r;

                //noise chann #2
                half var_Noise2 = SAMPLE_TEXTURE2D(_Noise, sampler_Noise, IN.uv2).g;

                //mix both chann
                half noise = var_Noise1 * _Noise1Params.z + var_Noise2 * _Noise2Params.z;

                //warp uv0
                float2 warpUV = frac(IN.uv0 - float2(0, noise) * warpMask);

                //sample Mask to get outer and inner flame tex
                half3 var_Mask = SAMPLE_TEXTURE2D(_Mask, sampler_Mask, warpUV);

                //final RGB
                half3 finalRGB = _Color1 * var_Mask.r + _Color2 * var_Mask.g;

                //opacity
                half opacity = var_Mask.r + var_Mask.g;

                return half4(finalRGB, opacity);
            }

            ENDHLSL
        }
        
    }
}
