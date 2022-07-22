Shader "Test/testTransA"
{
    Properties{
       _BaseCol("BaseCol", color) = (1,1,1,1)
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

            Blend One Zero, One Zero  //ǰһ����Ƭ���Լ��� Alpha ˢ�� targetRT�ϣ�����HDR RT.a��

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
                half _Opacity;
                half4 _BaseCol;
            CBUFFER_END

            struct VertexInput {
                float4 posOS : POSITION;   //��������
                float2 uv :TEXCOORD0;      //����uv
            };

            struct VertexOutput {
                float4 posCS : SV_POSITION;  //�������
            };

            VertexOutput vert(VertexInput IN) {
                VertexOutput OUT = (VertexOutput)0;
                OUT.posCS = TransformObjectToHClip(IN.posOS);
                return OUT;
            }

            half4 frag(VertexOutput IN) : SV_Target{

                half4 var_MainTex = _BaseCol;        //����Main

                half3 finalRGB = var_MainTex.rgb;
                half opacity = var_MainTex.a * _Opacity;

                return half4(finalRGB, opacity);   //����Blend��ʽ��Ե�ʣ�����ȥҪԤ��alpha 
            }

            ENDHLSL
        }
    }
}
