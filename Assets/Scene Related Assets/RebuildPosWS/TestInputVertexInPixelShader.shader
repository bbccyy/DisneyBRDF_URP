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

                //col.rgb = i.posWS;  //����ֱ���������ռ����� 
                
                //������� i.vertex �鿴���� 
                //997���س���539���ؿ����ǿ��ǵ�xy�Դ�0.5����ƫ�ƣ���Ҫ�����ظ�������1��
                //float2(997 +1, 539 + 1)
                col.rg = (i.vertex.xy * (_ScreenParams.zw - 1)).xy;
                col.b = i.vertex.z;       //z�����������Ҫд��SV_Depth��ֵ = ndc.z 
                col.a = i.vertex.w / 10;  //w��Clip.w -> �ȼ��� ViewSpace �µĸ����ص��Ӧ��������λ�õ����(��λ����) 
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
