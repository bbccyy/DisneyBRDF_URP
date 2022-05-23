Shader "Test/Water"
{
    Properties{
        _MainTex("MainTex", 2D) = "white" {}
        _WarpTex("WarpTex", 2D) = "gray" {}
        _MainTexSpeed("MainTexSeed X:SpeedX Y:SpeedY", vector) = (1.0, 1.0, 0, 1.0)
        _Warp1Params("Warp 1 Param, X:Scale Y:FlowSpeedX Z:FlowSpeedY W:Intensity", vector) = (1.0, 1.0, 0.5, 1.0)
        _Warp2Params("Warp 2 Param, X:Scale Y:FlowSpeedX Z:FlowSpeedY W:Intensity", vector) = (2.0, 0.5, 0.5, 1.0)
    }

    SubShader{
        Tags {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "ForceNoShadowCasting" = "True"
            "IgnoreProjector" = "True"
            "Queue" = "Opaque"
        }

        Pass {
            Name "Test Water"

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

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_WarpTex); SAMPLER(sampler_WarpTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half2 _MainTexSpeed;
                half4 _Warp1Params;
                half4 _Warp2Params;
            CBUFFER_END

            struct VertexInput {
                float4 posOS : POSITION;   //顶点输入
                float2 uv :TEXCOORD0;      //纹理uv
            };

            struct VertexOutput {
                float4 posCS : SV_POSITION;  //顶点输出
                float2 uv0 : TEXCOORD0;      //采样MainTex
                float2 uv1 : TEXCOORD1;      //采样Warp Noise1
                float2 uv2 : TEXCOORD2;      //采样Warp Noise2
            };

            VertexOutput vert(VertexInput IN) {
                VertexOutput OUT = (VertexOutput)0;
                OUT.posCS = TransformObjectToHClip(IN.posOS);
                OUT.uv0 = TRANSFORM_TEX(IN.uv, _MainTex);           //支持主纹理的TilingOffset
                OUT.uv0 = OUT.uv0 - frac(_Time.x * _MainTexSpeed);  //2个方向上的主纹理偏移速度 
                //一下uv0是否使用原始值？
                OUT.uv1 = OUT.uv0 * _Warp1Params.x - frac(_Time.x * _Warp1Params.yz);
                OUT.uv2 = OUT.uv0 * _Warp2Params.x - frac(_Time.x * _Warp2Params.yz);
                return OUT;
            }

            half4 frag(VertexOutput IN) : COLOR{
                //取样 warp 扰动分量 1 & 2
                half3 var_Warp1 = SAMPLE_TEXTURE2D(_WarpTex, sampler_WarpTex, IN.uv1).rgb;
                half3 var_Warp2 = SAMPLE_TEXTURE2D(_WarpTex, sampler_WarpTex, IN.uv2).rgb;

                //mix warp 1 and 2
                half2 warp = (var_Warp1.rg - 0.5) * _Warp1Params.w +
                             (var_Warp2.rg - 0.5) * _Warp2Params.w;
                
                //warp uv
                float2 warpUV = IN.uv0 + warp;

                //sample MainTex using warpped uv
                half4 var_MainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, warpUV);

                //final RGB
                half3 finalRGB = var_MainTex * var_Warp1.b + var_MainTex * var_Warp2.b;

                //opacity
                half opacity = 1;

                //return half4(finalRGB, opacity);
                return half4(var_MainTex.rgb, opacity);
            }

            ENDHLSL
        }

    }
}
