Shader "Test/TestInputVertexInPixelShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
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
                float3 posWS : TEXCOORD1;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS = TransformObjectToWorld(v.vertex);
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                // sample the texture
                half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);

                //col.rgb = i.posWS;  //这里直接输出世界空间坐标 
                
                //以下输出 i.vertex 查看究竟 
                //997像素长，539像素宽，但是考虑到xy自带0.5像素偏移，需要对像素个数增加1个
                //float2(997 +1, 539 + 1)
                col.rg = (i.vertex.xy * (_ScreenParams.zw - 1)).xy;
                col.b = i.vertex.z;       //z是正常情况下要写入SV_Depth的值 = ndc.z 
                col.a = i.vertex.w / 10;  //w是Clip.w -> 等价于 ViewSpace 下的该像素点对应几何物体位置的深度(单位是米) 
                return col;
            }
            ENDHLSL
        }
    }
}

// x = width
// y = height
// z = 1 + 1.0/width
// w = 1 + 1.0/height
// -> _ScreenParams

//col.rgb = mul(UNITY_MATRIX_I_VP, float4(i.vertex.xyz/ i.vertex.w, 1)).xyz;
