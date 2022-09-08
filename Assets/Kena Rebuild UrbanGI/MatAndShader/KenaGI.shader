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

            static float2 cb0_6 = float2(0.998231828212738, 0.998937487602233);

            float pow5(float a)
            {
                float t = a * a;
                return t * t * a;
            }

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

                //ViewDir (使用时取反: 从视点触发指向摄像机)
                half3 viewDir = normalize(posWS.xyz - camPosWS);

                //Sample Normal
                half3 n = SAMPLE_TEXTURE2D(_Norm, sampler_Norm, suv);
                n = n * 2 - 1; 
                half3 norm = normalize(n);

                //get chessboard mask 
                uint2 jointPixelIdx = (uint2)(IN.vertex.xy);
                uint chessboard = (jointPixelIdx.x + jointPixelIdx.y + 1) & 0x00000001;
                half2 chessMask = chessboard ? half2(1, 0) : half2(0, 1);

                //Sample _R_I_F_R 
                float4 rifr = SAMPLE_TEXTURE2D(_R_I_F_R, sampler_R_I_F_R, suv); 
                uint flag = (uint)round(rifr.z * 255);
                uint2 condi = flag & uint2(15, 16);//condi.x控制像素渲染逻辑(颜色表现丰富则噪点密集，表现单一则成块同色), y控制颜色混合;  

                //Sample _F_R_X_X
                float4 frxx = SAMPLE_TEXTURE2D(_F_R_X_X, sampler_F_R_X_X, suv);
                //下面frxx_condi的数据覆盖:衣服布料色(除缝线和划痕),树叶(绿色不连续，有随机间断),头部轮廓(彩)   
                float4 frxx_condi = condi.y == 16 ? float4(0, 0, 0, 0) : frxx.xyzw; //其x通道负责后续Fresnel项功能 

                //计算渲染通道mask, matCondi.xyz 分别对应 9, 5 和 4号渲染通道 -> 提供了随机的微小噪点 
                uint3 matCondi = condi.xxx == uint3(9, 5, 4).xyz; 

                //Sample Diffuse 
                half4 df = SAMPLE_TEXTURE2D(_Diffuse, sampler_Diffuse, suv); 

                //Diffuse_GI_base 
                half base_intensity = rifr.y * 0.08;
                half4 df_delta = df.xyzw - base_intensity; //从漫反射图中减去部分光强度 -> 余下部分高亮度材质(皮肤+窗户等) 
                half factor_RoughOrZero = matCondi.x ? 0 : rifr.x; //rifr.x=rough,只有屋顶+人物有值 
                
                //从采样df中先扣除强度,获得"dif_delta",再对其缩放(主要基于材质自身的rough)，最后再加回扣除的光强 
                half4 df_base = df_delta * factor_RoughOrZero + base_intensity; 

                //计算集中中间态颜色: R8, R10 和 R11 
                uint is9or5 = matCondi.x | matCondi.y;
                half3 R8 = half3(1, 1, 1);  //TODO 
                half4 R11 = half4(df_base.xyz, rifr.y) * chessMask.y;       //经过棋盘处理的 df_base 
                half4 R10 = is9or5 ? half4(chessMask.xxx, R11.w) : half4(df.xyz, rifr.y);  //部分人物+窗户等物件显示diffse,其他近似黑白噪点 

                //计算优化后的 NoV 输出到 df_base.w 中 -> 不是Lambert(NoL)，也不是Phong(NoH)，应该和Fresnel或漫反射强度相关 
                half NoV = dot(norm, -viewDir);
                half NoV_sat = saturate(NoV);
                half a = (NoV_sat * 0.5 + 0.5) * NoV_sat - 1.0; //大体上在[-1, 0]区间上成二次弧线分布，N和V垂直得-1 
                half b = saturate(1.25 - 1.25 * rifr.w); //与纹理.rough2成反比，且整体调整了偏移和缩放 
                df_base.w = a * b; //这张输出图对比 NoV 来说，区间在[-1, 0]，且物体边缘数值绝对值大，中间值接近0 
                half NoV_nearOne = df_base.w + 1.0; //上面的数值转换到 [0, 1] 区间，整体类似提亮的NoV，垂直得0(边缘暗)，同向得1(中间亮) 
                
                //计算R12颜色 
                half3 R12 = R10.xyz * 1.111111;
                half3 tmp_col = 0.85 * (NoV_sat - 1) * (1 - (R12 - 0.78*(R12 * R12 - R12))) + 1; 
                R12 = R12 * tmp_col;    //将基于NoV的环境光强度 -> 作用到 R10 颜色上 

                //施加Fresnel影响 
                float p5 = pow5(1 - NoV_sat);
                float fresnel = 0.04 * (1 - p5) + p5;                 //TODO:这个F项计算方式可摘录 
                tmp_col = R10.xyz * (1 - frxx_condi.x * fresnel);     //这里是将 Fresnel 项 -> 作用到 R10 颜色上 
                R12 = 0.9 * NoV_nearOne * R12;                        //这是经过环境光强度修正的 R10 
                R12 = lerp(tmp_col, R12, frxx_condi.x * factor_RoughOrZero);  //lerp中的Rate在绝大部分情况下趋于 0 

                //采样AO
                half ao = SAMPLE_TEXTURE2D(_AO, sampler_AO, suv);

                //求半分辨率下的UV 
                half2 _suv = min(suv, cb0_6.xy);                        //正常分辨率下的 UV 
                half2 half_scr_pixels = floor(screen_param.xy * 0.5);   //半分辨率下，屏幕的长宽对应像素个数 
                half2 one_over_half_pixels = 1.0 / half_scr_pixels;     //半分辨率下，一个像素对应 UV 的跨度 
                //下式将全分辨率 UV 转换到了 半分辨率对应的新 UV' -> 新UV'的值朝原点靠拢 
                //特点1: 正常分辨率下的“偶”数像素 UV 值，经变换后减少了 0.5*(1/原始长宽像素个数) 
                //特点2: 正常分辨率下的“奇”数像素 UV 值，经变换后减少了 1.5*(1/原始长宽像素个数) 
                half2 half_cur_uv = floor(_suv * half_scr_pixels - 0.5) / half_scr_pixels + one_over_half_pixels * 0.5; 
                half2 uv_delta = _suv - half_cur_uv;    //UV - UV' -> (0.5或1.5)*(1/原始长宽像素个数) 
                //半分辨率下，(UV - UV')占一个像素多少百分比(注:此时像素面积膨胀为原来4倍，长宽膨胀为原来2倍) 
                half2 delta_half_pixels = uv_delta * half_scr_pixels;  //推算下来，占用了(0.25或0.75)个大像素点长度 

                //多次采样GlobalNormal 
                half4 tmp_uv = half_cur_uv.xyxy + half4(one_over_half_pixels.x, 0, 0, one_over_half_pixels.y); 
                half4 g_norm_ld = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, half_cur_uv.xy); 
                half4 g_norm_rd = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.xy); 
                half4 g_norm_lu = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.zw); 
                half4 g_norm_ru = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.xw); 

                //利用全局法线扰动，求颜色 R13 


                return half4((g_norm_ru).xyzw);
            }
            ENDHLSL
        }
    }
}
