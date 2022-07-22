Shader "Test/testGAMMA"
{
    Properties{
    }

    SubShader{
        Tags {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Geometry"
            "ForceNoShadowCasting" = "True" 
            "IgnoreProjector" = "True"
            "Queue" = "Geometry"
        }

        Pass {
            Name "Test GAMMA"

            Blend One OneMinusSrcAlpha //预乘Alpha

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

            CBUFFER_START(UnityPerMaterial)
                
            CBUFFER_END

            struct VertexInput {
                float4 posOS : POSITION;   //顶点输入
                float2 uv :TEXCOORD0;      //纹理uv
            };

            struct VertexOutput {
                float4 posCS : SV_POSITION;  //顶点输出
                float2 uv : TEXCOORD0;
            };

            VertexOutput vert(VertexInput IN) {
                VertexOutput OUT = (VertexOutput)0;
                OUT.posCS = TransformObjectToHClip(IN.posOS);
                OUT.uv = IN.uv;
                return OUT;
            }

            half4 frag(VertexOutput IN) : SV_Target{

                int base = IN.uv.x * 255;
                half mid = base == 128 ? 0 : 1;
                half col = half(base) / 255.0;
                col = col * mid;

                return half4(col.xxx, 1);
            }

            ENDHLSL
        }
    }
}
