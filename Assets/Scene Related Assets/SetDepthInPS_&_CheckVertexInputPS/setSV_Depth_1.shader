Shader "Unlit/setSV_Depth_1"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Depth("Depth", Range(0,0.3)) = 0.01
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
            float _Depth;
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag (v2f i, out float depth : SV_DEPTH) : SV_Target
            {
                // sample the texture
                half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);

                /*
                �ӱ����Ͽ����� С -> �� ����_Depthֵ��������ᵼ�¹��ش�fragment shader�������� �ڱ�-> ��¶��
                ����Ⱦ��ǰ����a��fragmentʱ����Ӧpixel����Ȼ����л���һ���Ѿ����ڵ�ֵ Db�����Db����һ��DrawCall��ĳ����b��Ⱦʱͨ��"Z-Write"д����Ȼ����ֵ��
                ������ǲ��ڵ�ǰshader��ִ�ж�SV_DEPTH���������ô�ᰴ��Ԥ���"Z-Test"��ʶ��ִ�бȽϲ�ѡ��ͨ��������ĳЩ���أ�����tag���£�
                ZTest Less | Greater | LEqual | GEqual | Equal | NotEqual | Always
                Ĭ����LEqual���ȵ�ǰframent shader���������ʵ�����ֵDa���ɵײ�����ͨ����ֵ��ӦPRIMITIVE�����ã���С��Depth Buffer�е�ֵDbʱ��ͨ�����Բ�ִ�к�����Ⱦ��
                ���������ֶ��޸� SV_DEPTH ��ֵ�����൱��ֱ���޸���Depth buffer�е�Dbֵ�����ǵ���С SV_DEPTH ʱ���൱�ڰ�ԭ�ȵ�"�ڵ���"b������������������λ��0�㣩���ᵼ�µ�ǰ����a�޷�ͨ��Z-Test���γ��ڱΡ�
                �����ǵ��� SV_DEPTH ʱ���൱����Զ������b��ʹ�õ�ǰ����a��������b�ڱΣ��ܹ�������ʾ��
                ֱ���޸�SV_DEPTH��Ȼ�����һЩ�㷨�ϵı�������ȻҲ���д��۵ģ�
                
                ��Ⱦ���߻�Ҫ�������޸��� SV_DEPTH ��DC��Ҫλ�ڸ���û���޸ĵ�����֮����Ⱦ�������ڲ�����Ⱦ˳������ջ(��Ⱦջ)˳��ִ��(����?)�������Ƿ����������Ӱ�������      
                ʵ������ -> ����shader�ƺ�����Ⱦ����������ܹ���֤������Ⱦʱ������ǰ��һ����Χ�ڵ�����shader��һ����Ⱦ��ϣ�
                �Ӷ��ž��������Լ���Ⱦ�������Depth������������shader����������Լ����ӿ����������λ��ִ����Ⱦ��
                
                ������Ϊ��ǰshader�����������Ȼ����ֵȡ�����Ƿ�ͨ����Z-Test���������������������̣����Լ����ص�ʵ�����(������K��Depth)�ٴθ�����Ȼ��棬
                ���ûͨ��Z-Test����ô���൱������K��Depth��������Ȼ��棬���Ǳ���PSû���κ���ɫ�����SV_Target��
                */
                depth = _Depth;

                return col;
            }
            ENDHLSL
        }
    }
}
