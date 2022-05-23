Shader "Test/L15_GhostWarp"
{
    Properties{
        _MainTex("RGBA", 2D) = "gray" {}
        _Opacity("Opacity", range(0, 1)) = 0.5
        _WarpTex("Warp Texture", 2D) = "gray" {}
        _WarpInt("Warp Intensity", range(0, 1)) = 0.1
        _NoiseInt("Noise Intensity", range(0, 5)) = 1
        _FlowSpeed("Flow Speed", range(-10, 10)) = 5
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
                Name "Test Ghost flow"

                Blend SrcAlpha OneMinusSrcAlpha

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
                //uniform sampler2D _NoiseTex;
                //uniform sampler2D _MainTex;

                CBUFFER_START(UnityPerMaterial)
                    float4 _WarpTex_ST;
                    half _Opacity;
                    half _WarpInt;
                    half _NoiseInt;
                    half _FlowSpeed;
                CBUFFER_END

                struct VertexInput {
                    float4 posOS : POSITION;   //顶点输入
                    float2 uv :TEXCOORD0;      //纹理uv
                };

                struct VertexOutput {
                    float4 posCS : SV_POSITION;  //顶点输出
                    float2 uv0 : TEXCOORD0;      //采样Main
                    float2 uv1 : TEXCOORD1;      //采样Noise
                };

                VertexOutput vert(VertexInput IN) {
                    VertexOutput OUT = (VertexOutput)0;
                    OUT.posCS = TransformObjectToHClip(IN.posOS);
                    OUT.uv0 = IN.uv;
                    OUT.uv1 = TRANSFORM_TEX(IN.uv, _WarpTex);              //支持TilingOffset
                    OUT.uv1.y = OUT.uv1.y + frac(_Time.x * _FlowSpeed);    //轴向流动(V轴)
                    return OUT;
                }

                half4 frag(VertexOutput IN) : SV_Target{

                    half3 var_WarpTex = SAMPLE_TEXTURE2D(_WarpTex, sampler_WarpTex, IN.uv1);        //采样Warp
                    half2 uvBias = (var_WarpTex.rg - 0.5) * _WarpInt;
                    half2 uv0 = IN.uv0 + uvBias;

                    half4 var_MainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv0);           //采样Main

                    half3 finalRGB = var_MainTex.rgb;
                    half noise = lerp(1.0, var_WarpTex.b * 2.0, _NoiseInt);  //Remap Noise
                    noise = max(0.0, noise);
                    half opacity = var_MainTex.a * _Opacity * noise;

                    return half4(finalRGB, opacity);
                }

                ENDHLSL
            }


        }
}
