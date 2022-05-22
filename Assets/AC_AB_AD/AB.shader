Shader "Test/AB"
{
    Properties{
       _MainTex("RGBA", 2D) = "gray" {}
       _Opacity("Opacity", range(0, 1)) = 0.5
    }

    SubShader{
        Tags {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "TransparentCutout"
            "ForceNoShadowCasting" = "True"
            "IgnoreProjector" = "True"
            "Queue" = "Transparent"
        }

        Pass {
            Name "Test Alpha Cutout"

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

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half _Opacity;
            CBUFFER_END

            struct VertexInput {
                float4 posOS : POSITION;   //顶点输入
                float2 uv :TEXCOORD0;      //纹理uv
            };

            struct VertexOutput {
                float4 posCS : SV_POSITION;  //顶点输出
                float2 uv0 : TEXCOORD0;      //采样Main
            };

            VertexOutput vert(VertexInput IN) {
                VertexOutput OUT = (VertexOutput)0;
                OUT.posCS = TransformObjectToHClip(IN.posOS);
                OUT.uv0 = TRANSFORM_TEX(IN.uv, _MainTex);     //支持TilingOffset
                return OUT;
            }

            half4 frag(VertexOutput IN) : SV_Target{

                half4 var_MainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv0);        //采样Main

                half3 finalRGB = var_MainTex.rgb;
                half opacity = var_MainTex.a * _Opacity;

                return half4(finalRGB * opacity, opacity);   //由于Blend方式的缘故，返回去要预乘alpha 
            }

            ENDHLSL
        }
    }
}
