Shader "Kena/KenaGI"
{
    Properties
    {
        [NoScaleOffset] _Diffuse("Diffuse", 2D)     = "white" {}
        [NoScaleOffset] _Depth("Depth", 2D)         = "white" {}
        [NoScaleOffset] _AO("AO", 2D)               = "white" {}
        [NoScaleOffset] _F_R_X_X("F_R_X_X", 2D)     = "white" {}
        [NoScaleOffset] _GNorm("GNorm", 2D)         = "white" {}
        [NoScaleOffset] _IBL("IBL", CUBE)           = "white" {}
        [NoScaleOffset] _Sky("Sky", CUBE)           = "white" {}
        [NoScaleOffset] _LUT("LUT", 2D)             = "white" {}
        [NoScaleOffset] _Norm("Norm", 2D)           = "white" {}
        [NoScaleOffset] _R_I_F_R("R_I_F_R", 2D)     = "white" {}
        [NoScaleOffset] _Spec("Spec", 2D)           = "white" {}

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

            static float4 screen_param = float4(1708, 960, 1.0/1708, 1.0/960);  //这是截帧时的屏幕像素信息 

            static float4x4 M_Inv_VP = float4x4(
                float4(0.67306363582611, 0.116760797798633, -0.509014785289764, -58890.16015625),
                float4(-0.465476632118225, 0.168832123279571, -0.736369132995605, 27509.392578125),
                float4(-0.00000010974, 0.411912322044372, 0.445718020200729, -6150.4560546875),
                float4(0, 0, 0, 1)
                );

            static float3 camPosWS = float3(-58890.16015625, 27509.392578125, -6150.4560546875);

            v2f vert (appdata IN)
            {
                v2f OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
                OUT.vertex = TransformObjectToHClip(IN.vertex);
                OUT.uv = IN.uv;

                return OUT;
            }

            half4 frag (v2f IN) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                half2 suv = IN.vertex.xy * screen_param.zw;     //screen uv 
                half2 coord = (IN.vertex.xy * screen_param.zw - 0.5) * IN.vertex.w * 2.0;  //[-1, +1] 

                //Sample Depth
                half d = SAMPLE_TEXTURE2D(_Depth, sampler_Depth, suv); 
                d = 1 / (d * 0.1);  // Clip.z 
                
                //get h-clip space 
                coord = coord * d; 
                half4 hclip = half4(coord.xy, d, 1);

                //use matrix_Inv_VP to rebuild posWS 
                half4 posWS = mul(M_Inv_VP, hclip);

                //ViewDir
                half3 viewDir = normalize(posWS.xyz - camPosWS);

                //Sample Normal
                half3 n = SAMPLE_TEXTURE2D(_Norm, sampler_Norm, suv);
                n = n * 2 - 1; 
                half3 norm = normalize(n);

                //get chessboard mask 
                uint2 jointPixelIdx = (uint2)(IN.vertex.xy);
                uint chessboard = (jointPixelIdx.x + jointPixelIdx.y + 1) & 0x00000001;
                half2 mask = chessboard ? half2(1, 0) : half2(0, 1);

                //Sample _R_I_F_R 
                float4 rifr = SAMPLE_TEXTURE2D(_R_I_F_R, sampler_R_I_F_R, suv); 
                uint flag = (uint)round(rifr.z * 255);
                uint2 condi = flag & uint2(15, 16);//condi.x控制像素渲染逻辑(颜色表现丰富则噪点密集，表现单一则成块同色), y控制颜色混合;  

                //Sample _F_R_X_X
                float4 frxx = SAMPLE_TEXTURE2D(_F_R_X_X, sampler_F_R_X_X, suv);
                //frxx 的数据覆盖:衣服布料(除缝线和划痕),树叶(颜色不连续，有随机间断),头部轮廓(彩色的?) 
                frxx = condi.y == 16 ? float4(0, 0, 0, 0) : frxx.xyzw; 

                //计算渲染通道mask, matCondi.xyz 分别对应 9, 5 和 4号渲染通道 -> 提供了随机的微小噪点 
                uint3 matCondi = condi.xxx == uint3(9, 5, 4).xyz; 

                //Sample Diffuse 
                half4 df = SAMPLE_TEXTURE2D(_Diffuse, sampler_Diffuse, suv); 

                //Diffuse_GI_base 
                half base_intensity = rifr.y * 0.08;
                half4 df_delta = df.xyzw - base_intensity; //从漫反射图中减去部分光强度 -> 余下部分高亮度材质(皮肤+窗户等) 
                half factor_RoughOrZero = matCondi.x ? 0 : rifr.x; //rifr.x=rough,只有屋顶+人物有值 
                
                //对扣除强度的dif_delta部分做缩放(主要基于材质自身的rough)，最后再加回扣除的光强 
                half4 df_base = df_delta * factor_RoughOrZero + base_intensity;
                
                return half4((half4)(condi).xxxx / 16 );
            }
            ENDHLSL
        }
    }
}
