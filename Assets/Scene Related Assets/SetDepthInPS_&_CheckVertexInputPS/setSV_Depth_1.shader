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
                从表现上看，由 小 -> 大 调整_Depth值的输出，会导致挂载此fragment shader的物体由 遮蔽-> 显露。
                在渲染当前物体a的fragment时，对应pixel的深度缓存中会有一个已经存在的值 Db，这个Db是上一次DrawCall对某物体b渲染时通过"Z-Write"写入深度缓存的值。
                如果我们不在当前shader里执行对SV_DEPTH的输出，那么会按照预设的"Z-Test"标识符执行比较并选择通过或舍弃某些像素，具体tag如下：
                ZTest Less | Greater | LEqual | GEqual | Equal | NotEqual | Always
                默认是LEqual，既当前frament shader所渲物体的实际深度值Da（由底层驱动通过插值对应PRIMITIVE顶点获得）若小于Depth Buffer中的值Db时，通过测试并执行后续渲染。
                现在我们手动修改 SV_DEPTH 的值，这相当于直接修改了Depth buffer中的Db值，于是当调小 SV_DEPTH 时，相当于把原先的"遮挡物"b向摄像机调近（摄像机位于0点），会导致当前物体a无法通过Z-Test，形成遮蔽。
                当我们调大 SV_DEPTH 时，相当于拉远了物体b，使得当前物体a不被物体b遮蔽，能够正常显示。
                直接修改SV_DEPTH虽然会带来一些算法上的遍历，当然也是有代价的：
                
                渲染管线会要求所有修改了 SV_DEPTH 的DC需要位于附近没有修改的物体之后渲染。它们内部的渲染顺序按照入栈(渲染栈)顺序执行(待考?)。此外是否会对性能造成影响待考。      
                实践表面 -> 此类shader似乎在渲染队列里，总是能够保证自身渲染时，附近前后一定范围内的正常shader先一步渲染完毕，
                从而杜绝类似于自己渲染并输出了Depth后，有其他正常shader物体在相对自己更加靠近摄像机的位置执行渲染。
                
                可以认为当前shader最终输出到深度缓存的值取决于是否通过了Z-Test，如果是则后续走正常流程，用自己像素的实际深度(不是手K的Depth)再次覆盖深度缓存，
                如果没通过Z-Test，那么就相当于用手K的Depth覆盖了深度缓存，但是本身PS没有任何颜色输出到SV_Target。
                */
                depth = _Depth;

                return col;
            }
            ENDHLSL
        }
    }
}
