Shader "Unlit/testColorOp"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Scale ("Scale", Range(-1, 1)) = 0
        _NdotV ("NoV", Range(0,1)) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            float4 _MainTex_ST;
            float _Scale;
            float _NdotV;
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                // sample the texture
                half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                half4 col2 = col;
                //0.85*(NdotV-1)*{1+0.78*[(R12)^2 - R12]-R12} + 1
                col = lerp(col, col* col, _Scale);

                //垂直时(_NdotV==1) 结果为1 
                col = 0.85 * (_NdotV - 1) * (1 - col) + 1;

                col = col2 * col;

                return col;
            }
            ENDHLSL
        }
    }
}
