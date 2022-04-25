Shader "Example/grabpass"
{
    Properties
    {
        _MainTex("RGB：颜色 A：透贴", 2d) = "gray"{}
        _Opacity("Opacity", range(0, 1)) = 0.5
        _WarpMidVal("WarpMidVal", range(0, 1)) = 0.5
        _WarpInt("WarpInt", range(0, 5)) = 1
    }
    SubShader
    {
        Tags { 
            "RenderType" = "Transparent" 
            "RenderPipeline" = "UniversalPipeline"
            "IgnoreProjector" = "True" 
            "ForceNoShadowCasting" = "True"
        }
        LOD 100

        Pass
        {

            Name "GrabPass"
            Tags {"LightMode" = "UseColorTexture"}
            Blend One OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma prefer_hlslcc gles           
            #pragma exclude_renderers d3d11_9x   
            #pragma target 2.0                   

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_ScreenGrabTexture); SAMPLER(sampler_ScreenGrabTexture);

            CBUFFER_START(UnityPerMaterial)
                uniform half _Opacity;
                uniform half _WarpMidVal;
                uniform half _WarpInt;
            CBUFFER_END

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 pos : SV_POSITION;
                float4 grabPos : TEXCOORD1;     //for grabpass tex uv
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float4 ComputeGrabScreenPos(float4 pos) {
#if UNITY_UV_STARTS_AT_TOP
                float scale = -1.0;
#else
                float scale = 1.0;
#endif
                float4 o = pos * 0.5f;
                o.xy = float2(o.x, o.y * scale) + o.w;
#ifdef UNITY_SINGLE_PASS_STEREO
                o.xy = TransformStereoScreenSpaceTex(o.xy, pos.w);
#endif
                o.zw = pos.zw;
                return o;
            }

            v2f vert (appdata v)
            {
                v2f o = (v2f)0;
                o.pos = TransformObjectToHClip(v.vertex);
                //o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.uv = v.uv;
                o.grabPos = ComputeGrabScreenPos(o.pos);
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                // sample the texture
                //half4 var_MainTex = SampleAlbedoAlpha(i.uv, TEXTURE2D_ARGS(_MainTex, sampler_MainTex));
                half4 var_MainTex = tex2D(_MainTex, i.uv);

                // 扰动背景纹理采样UV
                i.grabPos.xy += (var_MainTex.b - _WarpMidVal) * _WarpInt * _Opacity;
                // 采样背景
                half3 var_BGTex = SAMPLE_TEXTURE2D(_ScreenGrabTexture, sampler_ScreenGrabTexture, i.grabPos).rgb;
                // FinalRGB 不透明度
                half3 finalRGB = lerp(1.0, var_MainTex.rgb, _Opacity) * var_BGTex;
                half opacity = var_MainTex.a;
                // 返回值
                return half4(finalRGB * opacity, opacity);
            }
            ENDHLSL
        }
    }
}
