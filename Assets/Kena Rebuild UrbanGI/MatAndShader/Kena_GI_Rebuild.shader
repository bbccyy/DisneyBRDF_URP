Shader "Unlit/Kena_GI_Rebuild"
{
    Properties
    {
        [NoScaleOffset] _Diffuse("Diffuse", 2D) = "white" {}
        [NoScaleOffset] _Depth("Depth", 2D) = "white" {}
        [NoScaleOffset] _AO("AO", 2D) = "white" {}
        [NoScaleOffset] _F_R_X_X("F_R_X_X", 2D) = "white" {}
        [NoScaleOffset] _GNorm("GNorm", 2D) = "white" {}
        [NoScaleOffset] _IBL("IBL", CUBE) = "white" {}
        [NoScaleOffset] _Sky("Sky", CUBE) = "white" {}
        [NoScaleOffset] _LUT("LUT", 2D) = "white" {}
        [NoScaleOffset] _Norm("Norm", 2D) = "white" {}
        [NoScaleOffset] _R_I_F_R("R_I_F_R", 2D) = "white" {}
        [NoScaleOffset] _Spec("Spec", 2D) = "white" {}

    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Blend One One

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
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };


            TEXTURE2D(_Diffuse); SAMPLER(sampler_Diffuse);
            TEXTURE2D(_Depth); SAMPLER(sampler_Depth);
            TEXTURE2D(_AO); SAMPLER(sampler_AO);
            TEXTURE2D(_F_R_X_X); SAMPLER(sampler_F_R_X_X);
            TEXTURE2D(_GNorm); SAMPLER(sampler_GNorm);
            TEXTURE2D(_LUT); SAMPLER(sampler_LUT);
            TEXTURE2D(_Norm); SAMPLER(sampler_Norm);
            TEXTURE2D(_R_I_F_R); SAMPLER(sampler_R_I_F_R);
            TEXTURE2D(_Spec); SAMPLER(sampler_Spec);
            TEXTURECUBE(_IBL); SAMPLER(sampler_IBL);
            TEXTURECUBE(_Sky); SAMPLER(sampler_Sky);

            static float4 View_BufferSizeAndInvSize = float4(1708.00, 960.00, 0.00059, 0.00104);
            static float4 View_ViewSizeAndInvSize = float4(1708.00, 960.00, 0.00059, 0.00104);
            static float4 View_ViewRectMin = float4(0, 0, 0, 0);



            float2 SvPositionToBufferUV(float4 SvPosition)
            {
                return SvPosition.xy * View_BufferSizeAndInvSize.zw;
            }

            float4 SvPositionToScreenPosition(float4 SvPosition)
            {
                float2 PixelPos = SvPosition.xy - View_ViewRectMin.xy;
                // NDC (NormalizedDeviceCoordinates, after the perspective divide)
                float3 NDCPos = float3((PixelPos * View_ViewSizeAndInvSize.zw - 0.5f) * float2(2, -2), SvPosition.z);
                // SvPosition.w: so .w has the SceneDepth, some mobile code and the DepthFade material expression wants that
                return float4(NDCPos.xyz, 1) * SvPosition.w;
            }



            v2f vert (appdata IN)
            {
                v2f OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                //UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
                OUT.vertex = TransformObjectToHClip(IN.vertex);
                OUT.uv = IN.uv;

                return OUT;
            }

            half4 frag (v2f IN) : SV_Target
            {
                half4 test = half4(0, 0, 0, 0);  //JUST FOR SHOW CASE 

                float2 BufferUV = SvPositionToBufferUV(IN.vertex);


                test.xy = BufferUV;

                return test;
            }
            ENDHLSL 
        }
    }
}
