Shader "Hidden/ShowDepth"
{
    Properties
    {
        _MainTex ("Texture", any) = "" {}
        _Color("Multiplicative color", Color) = (1,1,1,1)
    }
    SubShader
    {
        ZTest Always
        Cull Off
        ZWrite Off

        Pass
        {
            Name "Depth Texture"

            HLSLPROGRAM
            #pragma vertex Vert         //PostProcessing/Common.hlsl中定义了全屏Mesh对应的Vert方法 
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"

            half4 Frag(Varyings IN) : SV_Target
            {
                // sample the texture
                half4 col = SampleSceneDepth(IN.uv);  //该方法在DeclareDepthTexture.hlsl内 
                //col.rgb 位于 [0,1]区间，属于ndc坐标下的深度z 
                return col;
            }
            ENDHLSL
        }

        Pass    
        {
            Name "World Position"

            HLSLPROGRAM
            #pragma vertex VertWS
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"

            struct VaryingsWS
            {
                float4 positionCS : SV_POSITION;
                float4 uv   : TEXCOORD0;
            };

            VaryingsWS VertWS(Attributes IN)
            {
                VaryingsWS output;
                UNITY_SETUP_INSTANCE_ID(IN);

                output.positionCS = TransformObjectToHClip(IN.positionOS.xyz);

                float4 projPos = output.positionCS * 0.5;
                projPos.xy = projPos.xy + projPos.w;  //这到底在干啥？？ 

                output.uv.xy = IN.uv;
                output.uv.zw = projPos.xy;

                return output;
            }

            half4 Frag(VaryingsWS IN) : SV_Target
            {
                half4 col;

#if UNITY_REVERSED_Z
                float depth = SampleSceneDepth(IN.uv.xy);
#else
                // Adjust z to match NDC for OpenGL
                float depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(IN.uv.xy));
#endif
                //inputs: positionSS, depthNDC, InverseVP
                float3 worldPos = ComputeWorldSpacePosition(IN.uv.xy, depth, unity_MatrixInvVP);

                col.rgb = worldPos.rgb;
                col.a = 1.0;

                return col;
            }

            ENDHLSL
        }

        Pass
        {
            Name "Slice"  //http://www.aortiz.me/2018/12/21/CG.html 用于聚类渲染 

            HLSLPROGRAM
            #pragma vertex Vert  
            #pragma fragment Frag 

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"

            half4 Frag(Varyings IN) : SV_Target
            {
                //TODO: meaning? 
                half4 col;
                float depth = LinearEyeDepth(SampleSceneDepth(IN.uv), _ZBufferParams);

                float _NumSlices = 31;
                int slice = floor(log(depth) * _NumSlices / log(_ProjectionParams.z / _ProjectionParams.y)
                    - _NumSlices * log(_ProjectionParams.y) / log(_ProjectionParams.z / _ProjectionParams.y));

                col.r = 1 - step(3, fmod(slice + 2, 6));
                col.g = 1 - step(3, fmod(slice, 6));
                col.b = 1 - step(3, fmod(slice + 4, 6));
                col.a = 1;

                return col;
            }
            ENDHLSL
        }
    }
}
