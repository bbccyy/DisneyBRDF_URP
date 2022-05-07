Shader "Test/testOpaqueTexture"
{
    Properties
    {
        //_MainTex ("Texture", 2D) = "white" {}
        _Intensity("Intensity", Range(0, 1)) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" 
               "RenderPipeline"="UniversalPipeline"
               "Queue"="Transparent"}
        LOD 100

        Cull Off
        Blend SrcAlpha OneMinusSrcAlpha, One OneMinusSrcAlpha
        ZTest LEqual
        ZWrite Off

        Pass
        {
            Name "Forward Test Opaque"

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #define REQUIRE_OPAQUE_TEXTURE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            float _Intensity;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varying
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            sampler2D _CameraOpaqueTexture;

            Varying vert (Attributes IN)
            {
                Varying o = (Varying)0;
                o.positionCS = TransformObjectToHClip(IN.positionOS);
                o.uv = IN.uv;

                return o;
            }

            half4 frag(Varying IN) : SV_Target
            {
                float2 uv = IN.positionCS.xy / _ScreenParams.xy;

                half4 col = tex2D(_CameraOpaqueTexture, uv + 0.1);

                return col * float4(0, _Intensity, 0, 1);
            }

            ENDHLSL
        }
    }
}
