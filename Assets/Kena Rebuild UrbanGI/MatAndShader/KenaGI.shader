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
            #define _pi 3.141593f

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

            static float pow5(float a)
            {
                float t = a * a;
                return t * t * a;
            }

            static float pow2(float a)
            {
                return a * a;
            }

            static float acos(float a) {
                float a2 = a * a;   // a squared
                float a3 = a * a2;  // a cubed
                if (a >= 0) {
                    return (float)sqrt(1.0 - a) * (1.5707288 - 0.2121144 * a + 0.0742610 * a2 - 0.0187293 * a3);
                }
                return 3.14159265358979323846
                    - (float)sqrt(1.0 + a) * (1.5707288 + 0.2121144 * a + 0.0742610 * a2 + 0.0187293 * a3);
            }

            static float asin(float a) {
                float a2 = a * a;   // a squared
                float a3 = a * a2;  // a cubed
                if (a >= 0) {
                    return 1.5707963267948966
                        - (float)sqrt(1.0 - a) * (1.5707288 - 0.2121144 * a + 0.0742610 * a2 - 0.0187293 * a3);
                }
                return -1.5707963267948966 + (float)sqrt(1.0 + a) * (1.5707288 + 0.2121144 * a + 0.0742610 * a2 + 0.0187293 * a3);
            }

            static float4 screen_param = float4(1708, 960, 1.0/1708, 1.0/960);  //这是截帧时的屏幕像素信息 
            //37 15 13&12 + 341 = 353/4:13 356:9 378:17 -> 选12/13,353/354,13
            static float4x4 M_Inv_VP = float4x4(
                float4(0.67306363582611, 0.116760797798633, -0.509014785289764, -58890.16015625),
                float4(-0.465476632118225, 0.168832123279571, -0.736369132995605, 27509.392578125),
                float4(-0.00000010974, 0.411912322044372, 0.445718020200729, -6150.4560546875),
                float4(0, 0, 0, 1)
                );

            static float4x4 M_CB1_181 = float4x4(
                float4(0.002263982, -0.06811329, 0.245573655, 0.342455983),
                float4(0.001246308, -0.056144755, 0.291698247, 0.420799345),
                float4(0.000283619, -0.032326974, 0.36867857, 0.53766793),
                float4(0, 0, 0, 1)
                );

            static float4x4 M_CB1_184 = float4x4(
                float4(-0.014053623, -0.017187765, -0.070339404, 0.004438644),
                float4(-0.010436025, -0.013045031, -0.07726939, 0.003332109),
                float4(-0.005038799, -0.002133884, -0.076634146, 0.001644174),
                float4(0, 0, 0, 1)
                );

            static float3 V_CB1_180 = float3(4.949999809, 4.192022324, 3.122247696);
            static float3 V_CB1_187 = float3(-0.016062476, -0.010786114, -0.003302935);

            static float3 V_CB0_1 = float3(0.045186203, 0.051269457, 0.029556833);


            static float3 camPosWS = float3(-58890.16015625, 27509.392578125, -6150.4560546875);

            static float2 cb0_6 = float2(0.998231828212738, 0.998937487602233);

            static float4 cb4_12 = float4(-55666.63672, 27997.91406, -6577.694336, 1296.551636);
            static float4 cb4_353 = float4(1, 13, 0, 0);



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
                
                half4 output = half4(0, 0, 0, 0);
                half tmp1 = 0; 
                half2 tmp2 = half2(0, 0);

                half2 suv = IN.vertex.xy * screen_param.zw;     //screen uv 
                half2 coord = (IN.vertex.xy * screen_param.zw - 0.5) * IN.vertex.w * 2.0;  //[-1, +1] 

                //Sample Depth
                half d = SAMPLE_TEXTURE2D(_Depth, sampler_Depth, suv); 
                d = 1 / (d * 0.1);  // Clip.z, 对原始d*0.1推测是将长度单位从 cm -> m 
                
                //get h-clip space 
                coord = coord * d; 
                half4 hclip = half4(coord.xy, d, 1);

                //use matrix_Inv_VP to rebuild posWS 
                half4 posWS = mul(M_Inv_VP, hclip);  //注意此时单位还是 "厘米" 

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

                //利用(全局法线 & 深度)的差异做扰动，求颜色 R13 
                //首先下面基于屏幕像素索引的“奇偶”性，组合出一定随机特性的屏幕空间纹理 
                tmp2 = 1 - delta_half_pixels; 
                half4 scr_pat = half4(tmp2.x * tmp2.y, 
                    delta_half_pixels * tmp2, 
                    delta_half_pixels.x * delta_half_pixels.y); 
                //组合4次采样的深度 
                half4 depth4 = half4(g_norm_ld.w, g_norm_rd.w, g_norm_lu.w, g_norm_ru.w); //注,这里的w通道存放单位为里面的距离 
                depth4 = 1.0 / (abs(depth4 - d) + 0.0001) * scr_pat;   //r13.xyzw 
                half g_depth = 1.0 / dot(depth4, half4(1.0, 1.0, 1.0, 1.0)); 
                //如下本质是矩阵变换，矩阵每一列是采样_GNorm获得的附近4邻域的法线，而变化对象的每一个通道是深度差的倒数(这是屏幕空间法线的一种计算方式) 
                half3 d_norm = g_norm_ld.xyz * depth4.xxx + g_norm_rd.xyz * depth4.yyy + g_norm_lu.xyz * depth4.zzz + g_norm_ru.xyz * depth4.www; 
                //1/0.0001667 = 6000 -> 推测是编码距离时使用的极大值，20000推测是缩放系数 
                //整体来说:当d>20000时scale横为0; 当14000<d<20000时scale在[0,1]区间上线性分布; 当d<14000时scale横为1 
                half scale = saturate((20000 - d) * 0.00016666666);      //Scale, 靠近摄像机->1，远离->0 
                d_norm = scale * (d_norm * g_depth - norm) + norm;       //这张基于4邻域深度差扰动后的d_norm看起来与_GNorm很像(可能略微模糊了一点?) 

                half4 test = half4(0, 0, 0, 0);  //JUST FOR SHOW-RESULTS 
                if (condi.x)  //对于 #1 ~ #15 号渲染通道来说都能进入 
                {
                    //R12和R10颜色都是黑白噪点下显示人物本体Diffuse的贴图，区别在于R12对D图施加了NoV和Fresnel，而R10是直白的D图 
                    half3 R15 = matCondi.z ? (R12 - R12 * factor_RoughOrZero) : (R10 - R10 * factor_RoughOrZero); 
                    //RN 来自 _GNorm 贴图，经多次采样和叠加而得，推测是某种小范围随机和模糊后的N -> RandomNorm(或RN) 
                    half RN_Len = sqrt(dot(d_norm, d_norm));
                    half3 RN = d_norm / max(RN_Len, 0.00001);
                    
                    //计算AO_from_RN 
                    half3 bias_N = (norm - RN) * RN_Len + RN; //让RN朝着Norm的方向偏折一定距离 -> r17.xyz (第一类r17)
                    half RNoN = dot(RN, norm); 
                    //TODO:这个AO项计算方式可摘录 
                    half AO_from_RN = lerp(RNoN, 1, RN_Len);  //通过全局法线纹理获得的AO -> r11.w 

                    //计算AO_final, 备注:log2_n = 1.442695 * ln_n 
                    half computed_ao = saturate(40.008 /(exp(-0.01*(RN_Len * 10.0 - 5))+1) - 19.504); 
                    computed_ao = pow(computed_ao, 0.7); 
                    computed_ao = lerp(computed_ao, 1, 0);  //rate = 0 -> 来自cb0[1].w 

                    uint AO_blend_Type = (0 == 1); //其中 1 来自 cb0[9].x 
                    half min_of_texao_and_ssao = min(df.w, ao); //min(Tex_AO, SSAO) 
                    half min_of_3_ao = min(computed_ao, min_of_texao_and_ssao); 
                    half mul_of_compao_and_minao = computed_ao * min_of_texao_and_ssao; 
                    half AO_final = AO_blend_Type ? min_of_3_ao : mul_of_compao_and_minao; 

                    uint4 matCondi2 = condi.xxxx == uint4(6, 2, 3, 7).xyzw; 
                    half3 frxxPow2 = frxx_condi.xyz * frxx_condi.xyz;  //不明白这样处理纹理的原因,该数值与材质本身关联 
                    half3 ao_diffuse_from_6 = half3(0, 0, 0); 
                    half3 ao_diffuse_common = half3(0, 0, 0); //非 #6 号渲染通路也会在后面用类似如下的方法计算 common 变量 
                    if (matCondi2.x)  // #6 号渲染通路 使用如下公式计算 ao_diffuse_from_6 
                    {
                        half4 neg_norm = half4(-norm.xyz, 1); 
                        half3 bias_neg_norm1 = mul(M_CB1_181, neg_norm); 
                        neg_norm = norm.yzzx * norm.xyzz; 
                        half3 bias_neg_norm2 = mul(M_CB1_184, neg_norm); 
                        //base_disturb * scale + bias 
                        ao_diffuse_from_6 = V_CB1_187 * (norm.x*norm.x-norm.y*norm.y) + (bias_neg_norm1+bias_neg_norm2);
                        ao_diffuse_from_6 = V_CB1_180 * max(ao_diffuse_from_6, half3(0, 0, 0));
                        //#6号渲染通路的disturb返回值最终是基于"法线扰动" & "AO" & "材质参数"的混合 
                        ao_diffuse_from_6 = AO_final * ao_diffuse_from_6 * frxxPow2;
                    }

                    tmp1 = matCondi2.y | matCondi2.z; //#2 或 #3 号渲染通道 
                    R15 = tmp1 ? (frxxPow2 + R15) : R15;   //base_diffuse 

                    if (matCondi2.w) // #7 号渲染通路 求其特有的基础 Diffuse -> 覆盖到 R15.xyz  
                    {
                        half3 refractDirRaw = NoV * (-norm) + viewDir; 
                        half3 refractDir = normalize(refractDirRaw);  // ->r17.xyz (第二类r17) 
                        half rough_7 = min(1.0, max(rifr.w, 0.003922)); 
                        half3 RoV = dot(refractDir, -viewDir); 
                        half3 RoN = dot(refractDir, norm); 
                        half ang_NoV = acos(NoV); 
                        half ang_RoN = acos(RoN); 

                        half cos_half_angle_VtoRneg = cos(abs(ang_NoV - ang_RoN) * 0.5); 

                        half3 V_hori = norm * (-RoN) + refractDir; //获得朝向折射方向的 "水平向量" -> Vector_Horizontal 
                        half RefrawDotHori = dot(V_hori, refractDirRaw);
                        tmp1 = dot(V_hori, V_hori) * dot(refractDirRaw, refractDirRaw) + 0.0001;
                        tmp1 = RefrawDotHori* (1.0 / sqrt(tmp1)); //相当于求 |V_hori| * |RefracRaw|的倒数  
                        tmp1 = RefrawDotHori* tmp1; // AdotB/(|A|*|B|) -> cos<AB> -> cos(V_hori和Refract的夹角) 
                        //以下可以看做是对cosθ的两种不同range调整  
                        half2 cos_VhroiToRefract_adjust2 = half2(0.5, 17.0) * tmp1 + half2(0.5, -16.780001); 
                        cos_VhroiToRefract_adjust2.x = saturate(cos_VhroiToRefract_adjust2.x); 
                        tmp1 = sqrt(cos_VhroiToRefract_adjust2.x);

                        half rough_factor_1 = rough_7 * rough_7; 
                        half rough_factor_2 = rough_factor_1 * 2 + 0.2;
                        rough_factor_1 = rough_factor_1 + 0.2;

                        half sin_NV = sqrt(1 - NoV * NoV); 
                        half factor_HroiToRefract = 0.997551 * tmp1;
                        half factor_NoV = -0.069943 * NoV;
                        half twist = factor_HroiToRefract* sin_NV + factor_NoV;  //似乎是对朝向的旋转 

                        rough_factor_1 = tmp1* rough_factor_1; 
                        tmp2 = half2(1.414214, 3.544908)* rough_factor_1; //数值->(sqrt(2), 2*sqrt(π)) 

                        half R5Z = (NoV + RoN) - (-0.139886) * twist; //记为 R5Z 
                        R5Z = -0.5 * R5Z * R5Z; 
                        R5Z = R5Z / (tmp2.x* tmp2.x); 
                        // exp(-0.5 * R5Z^2 / (2*cos_VhoR*(roughness^2+0.2)^2)) / (2sqrt(π)*sqrt(cos_VhoR)*(roughness^2 + 0.2)) 
                        // 其中 R5Z = (NdotV + RoN)-(-0.139886)*(0.997*sqrt(cos_VhroiToRefract)*sinθ-0.069943*cosθ) 
                        R5Z = exp(R5Z) / tmp2.y; 
                        tmp1 = tmp1 * R5Z; // sqrt(cos_VhoR*0.5+0.5) * (上式) -> 记为 R5Z' 

                        tmp1 = tmp1 * (0.953479 * pow5(1 - sqrt(saturate(RoV * 0.5 + 0.5))) + 0.046521); 
                        half R1Y = 0.5 * R10.w * tmp1;   //记为R1Y TODO: 给个名字? 

                        half RoV_po = saturate(-RoV); 
                        half factor_RoV = 1 - RoV_po;   //当掠射或垂直时得0，当视线成45度角时得最大值0.3左右 

                        tmp1 = exp((-0.5 * pow2(NoV - 0.14)) / pow2(rough_factor_2)) / (rough_factor_2 * 2.506628); //2.506=sqrt(2π) 

                        half R10W = 0.953479 * pow5(1 - 0.5 * cos_half_angle_VtoRneg) + 0.046521;  //颜色强度 or AO 关联值 
                        R10W = pow2(1 - R10W) * R10W; 
                        //TODO: 确认如下使用exp还是exp2  bh 
                        half3 df_chan7 = exp(log(R10.xyz) * (0.8 / cos_half_angle_VtoRneg));  // #7 渲染通道使用的 df，经过了调整 
                        df_chan7 = df_chan7* tmp1* exp(cos_VhroiToRefract_adjust2.y)* R10W + factor_RoV * R1Y; 

                        tmp1 = lerp(min(0.25 * (1 + dot(refractDir, refractDir)), 1.0), (1 - abs(RoN)), 0.33) * factor_RoughOrZero * 0.318310;
                        
                        R10.xyz = sqrt(R10.xyz) * tmp1 + df_chan7; 
                        R10.xyz = min(-R10.xyz, half3(0, 0, 0)); //结合下面乘 -π -> 这一步作用是抹去负数 
                        R15.xyz = R10.xyz * half3(-_pi, -_pi, -_pi); //π * (由折射夹角和粗糙度系数等换算出来的新df) -> 一种基础漫反射 
                    }

                    uint is8 = condi.x == uint(8);
                    R10.xyz = frxxPow2.xyz * frxx_condi.w + R15.xyz; 
                    R10.xyz = is8 ? R10.xyz : R15.xyz; 

                    //以下逻辑与之前处理 #6 渲染通道时雷同 
                    half4 biasN = half4(bias_N.xyz, 1.0); 
                    half3 bias_biasN = mul(M_CB1_181, biasN); 
                    half4 mixN = biasN.yzzx * biasN.xyzz; 
                    half3 bias_mixN = mul(M_CB1_184, mixN);
                    //base_disturb * scale + bias 
                    ao_diffuse_common = V_CB1_187 * (biasN.x * biasN.x - biasN.y * biasN.y) + (bias_biasN + bias_mixN);
                    ao_diffuse_common = V_CB1_180 * max(ao_diffuse_common, half3(0, 0, 0));

                    //#6号渲染通路的disturb返回值最终是基于"法线扰动" & "AO" & "材质参数"的混合 
                    ao_diffuse_common = AO_from_RN * AO_final * ao_diffuse_common + V_CB0_1 * (1 - AO_final);

                    R10.xyz = R10.xyz * ao_diffuse_common + ao_diffuse_from_6;  //这是个颜色, 推测为完整的 Diffuse 

                    half intense = dot(half3(0.3, 0.59, 0.11), R10.xyz);
                    half check = 1.0 == 0;      //返回false -> 相当于关闭了alpha通道 -> cb1[200].z == 0 ?
                    //光强度与flag求and -> 要求强度大于0且开启了flag 
                    //在前面的基础上还要求是 #9或#5号渲染通道 -> check 才为 true(1) 
                    output.w = half((uint(check) & uint(intense)) & is9or5);    //此处返回恒为 0 

                    test.x = AO_final;
                }
                else //对于 #0 号 渲染通道  
                {
                    R10 = half4(0, 0, 0, 0);
                    output.w = 0;
                }

                uint2 is0or7 = condi.xxx != uint2(0, 7).xy;
                if ((is0or7.x & is0or7.y) != 0)  //既不是 #0号 也不是 #7 号渲染通道 
                {
                    //GI_Spec 计算部分在此 
                    half3 Specular_Final = half3(0, 0, 0);
                    half3 gi_spec_base = half3(0, 0, 0);

                    //首先依据是否是9or5号渲染通道，选择R11(环境光底色*方块Mask.y) 或 环境光底色作为新的 df_base(基础环境光底色) 
                    df_base.xyz = is9or5 ? R11.xyz : df_base.xyz;  
                    tmp1 = (frxx_condi.x * df_base.w + 1) * 0.08; //df_base.w是与rough和NoV有关的值，处于[-1,0]区间；frxx_condi.x作为遮罩用于屏蔽指定像素 
                    R11.xyz = factor_RoughOrZero * (R12.xyz - tmp1.xxx) + tmp1.xxx; //R11颜色是基于R12颜色做的微调 
                    df_base.xyz = matCondi.z ? R11.xyz : df_base.xyz;  //如果是 #4 渲染通道 设置 df_base 为 上面计算出来的R11颜色 
                    half3 VR = (NoV + NoV) * norm + viewDir;  //View_Reflection -> VR:视线反射方向 
                    half roughSquare = rifr.w* rifr.w;
                    //下式对应函数图像 -> 可近似为开口朝向的二次曲线，过y轴正1，同时与x轴正负1相交 
                    half rate = (roughSquare + sqrt(1 - roughSquare)) * (1 - roughSquare);  //约 0.63 -> 某种rate系数 
                    half3 VR_lift = lerp(norm, VR, rate);  //暂且定义为‘上抬视反’(注:没有归一化) ，具体反射向量上抬角度受rough控制 -> 简言之越粗糙，反射视线越接近法线朝向 

                    //使用屏幕UV采样 T12 -> 这张纹理看起来对水晶,金属扣环等物体做了处理 -> 疑似关联 spec -> 从后续逻辑看(xyz分量)推测是对高光项的线性的附加补充量 
                    half4 spec_add_raw = SAMPLE_TEXTURE2D(_Spec, sampler_Spec, suv);
                    half spec_mask = 1 - spec_add_raw.w;  //后续会作用到基于环境光贴图的高光重建过程中，作为强度遮罩 
                    //如下可知 frxx_condi.x 非0既1 -> 当0时使用采样T12纹理的采样返回值(w分量会取反)；当1时xyz高光附加颜色分量置为0(而w通道被置为1) 
                    half4 spec_add = matCondi.z ? (frxx_condi.x * half4(-spec_add_raw.xyz, spec_add_raw.w) + half4(spec_add_raw.xyz, spec_mask)) : half4(spec_add_raw.xyz, spec_mask);

                    //如下输出的是被T12.w通道修正过的'AO噪声'高频部分系数 
                    half mixed_ao = df.w * ao + NoV_sat; 
                    half AOwthRoughNoise = df.w * ao + exp(log(mixed_ao) * roughSquare);
                    AOwthRoughNoise = saturate(AOwthRoughNoise - 1);  //-> r0.y -> 只截取超过1的部分，这部分可以看做是AO叠加上Rough后的高频噪声 
                    half masked_AOwthRoughNoise = spec_add.w * AOwthRoughNoise; //推测为spec特殊底噪 

                    //以下逻辑用于计算索引 -> 最终用于获取IBL贴图 
                    uint2 screenPixelXY = uint2(IN.vertex.xy);
                    uint logOfDepth = uint(max(log(d * 1 + 1) + 1, 0));  //大体上等于深度的对数 + 1 -> 剔除了太过接近的距离 
                    uint curbed_logOfDepth = min(logOfDepth, uint(0));   //似乎只能返回 0? -> 注:上下行涉及常数部分均来自cb3 
                    screenPixelXY = screenPixelXY >> 1;                  //相当于半屏幕像素索引 
                    //((距离对数因子 * 1 + 半屏幕像素索引.v) * 1 + 半屏幕像素索引.u + 1) * 2 
                    uint map_Idx_1 = ((curbed_logOfDepth * 1 + screenPixelXY.y) * 1 + screenPixelXY.x + 1) << 1; 
                    uint map_Idx_2 = map_Idx_1 + 1; 
                    //下面跳过了使用map_Idx来获取索引的步骤 -> 这不重要 
                    //ld_indexable(buffer)(uint,uint,uint,uint) ret_from_t3_buffer_1, map_Idx_1, t3.x 
                    //ld_indexable(buffer)(uint,uint,uint,uint) ret_from_t3_buffer_2, map_Idx_2, t3.x 
                    uint ret_from_t3_buffer_1 = 1;  //r0.w -> 用于控制循环计算不同IBL环境光贴图的次数 -> 可为[0,1,..7] 
                    uint ret_from_t3_buffer_2 = 1;  //r0.z -> 用于辅助定位IBL贴图在贴图队列中的位置 -> 可为[0,1,..7] 

                    uint is6 = condi.x == uint(6);  //是否是 #6 渲染通道 
                    half norm_shift_intensity = 0;  //该参数和gi_spec_base是下面逻辑分支的主要计算目标 
                    if (true)  //这条分支又cb[0].x 控制，总是可以进入 
                    {
                        half RN_raw_Len = sqrt(dot(d_norm, d_norm));
                        norm_shift_intensity = RN_raw_Len;
                        //以下分支用于计算某种扰动强度 -> norm_shift_intensity? -> TODO 确定学界定义范畴 
                        //计算过程中使用到了: |Rn_raw|, roughness, asin(dot(Rn,'上抬视反')/|Rn|) -> 推测为经验公式 
                        if (true) //cb1[189].x 用十六进制解码后得 0x00000001 -> true 
                        {
                            if (is6) //处理 #6 渲染通道 
                            {
                                //以下准备中间计算量 
                                half rough_chan6 = max(rifr.w, 0.1);
                                //half pi_RN_raw_Len = _pi * (RN_raw_Len * 1);
                                half RNoVRLift = dot(d_norm, VR_lift);
                                RN_raw_Len = max(RN_raw_Len, 0.001);

                                half asin_input = RNoVRLift / RN_raw_Len;
                                tmp2.x = asin(asin_input) - abs(_pi * rough_chan6 - _pi * RN_raw_Len);
                                tmp2.y = (_pi * rough_chan6 + _pi * RN_raw_Len) - abs(_pi * rough_chan6 - _pi * RN_raw_Len);
                                tmp1 = saturate(tmp2.x / tmp2.y);
                                tmp1 = ((1.0 - tmp1) * (-2.0) + 3.0) * pow2(1.0 - tmp1);

                                norm_shift_intensity = saturate((_pi* RN_raw_Len - 0.1) * 5.0)* tmp1; //更新 norm_shift_intensity 
                            }
                        }
                        half cb0_1_w_rate = 0;
                        norm_shift_intensity = lerp(norm_shift_intensity, 1.0, cb0_1_w_rate);
                        gi_spec_base = (1.0 - norm_shift_intensity) * V_CB0_1.xyz;
                    }
                    else
                    {
                        gi_spec_base = half3(0, 0, 0); 
                        norm_shift_intensity = 1; 
                    }

                    half lod_lv = 6 - (1.0 - 1.2 * log(rifr.w));  //与粗糙度有关的采样LOD等级，魔法数字6来自cb0 
                    half threshold = masked_AOwthRoughNoise;
                    half3 ibl_spec_output = half3(0, 0, 0);  //这是如下for循环的主要输出 
                    //注意: ret_from_t3_buffer_1是使用‘屏幕像素’与‘距离对数’组合出索引 -> 再从 T3 buffer 中取得的映射值 
                    //该映射返回值的取值范围要么是 0, 要么 1 
                    //推测是依据距离远景和是否处于屏幕中心，判断是否要开启当前像素的环境光贴图采样逻辑 
                    //此外 masked_AOwthRoughNoise 本身是后棋盘装mask和多重AO以及Rough计算出的"高频细节" 
                    //其作为循环判断之一也能阻止一部分像素进入IBL采样循环 
                    [unroll] for (uint i = 0; i < ret_from_t3_buffer_1 && threshold >= 0.001; i++)
                    {
                        //判断当前场景‘激活’的IBL探针，如果当前像素点能被某张IBL影响，则进入内部 if 分支执行逻辑 
                        uint tb4_idx = i + ret_from_t3_buffer_2;
                        //下面跳过了使用 tb4_idx 来获取索引的步骤 -> t4和t3一样，也是张映射表 
                        //ld_indexable(buffer)(short,short,short,short) out, tb4_idx, t4.x  -> 使用tb4_idx=[0-8]采样返回都是"6" 
                        //这里使用视检过的"正确值" -> out = 12 来替代 
                        half3 v_PixelToProbe = posWS - cb4_12.xyz; 
                        half d_PixelToProbe_square = dot(v_PixelToProbe, v_PixelToProbe); 
                        half d_PixelToProbe = sqrt(d_PixelToProbe_square); 
                        if (d_PixelToProbe < cb4_12.w)  //测试当前像素所在世界坐标是否在目标Probe的作用范围内 
                        {
                            half d_rate = saturate(d_PixelToProbe / cb4_12.w); //距离占比  
                            half VRLoP2P = dot(VR_lift, v_PixelToProbe); 
                            //下式形式为: Scale * VR_lift + v_PixelToProbe - [200,0,0] 
                            half3 shifted_p2p_dir = (sqrt(pow2(VRLoP2P) - (d_PixelToProbe_square - pow2(cb4_12.w))) - VRLoP2P) * VR_lift + v_PixelToProbe - half3(200, 0, 0);
                            tmp1 = max(2.5 * d_rate - 1.5, 0);  //如果 (像素到探针的距离 / 探针影响半径R) < 0.6 -> 上式一律返回 0 
                            half rate_factor = 1.0 - (3.0 - 2.0 * tmp1) * pow2(tmp1); //距离缩放因子 
                            //shifted_p2p_dir 是采样cubemap的方向指针 
                            //IBL_cubemap_array的index由 cb4[12 + 341].y 获得，当前值为 "13"  
                            //注意，由于没有以Cubemap_array形式导入原始资源，故如下采样的uv参数中没有第四维(array索引) 
                            half4 ibl_raw = SAMPLE_TEXTURECUBE_LOD(_IBL, sampler_IBL, shifted_p2p_dir, lod_lv).rgba;
                            //更新 ibl_spec_output 
                            ibl_spec_output = (cb4_353.x * ibl_raw.rgb) * rate_factor * threshold * norm_shift_intensity + ibl_spec_output; 
                            //更新 threshold -> masked_AOwthRoughNoise 
                            threshold = threshold * (1.0 - rate_factor * ibl_raw.a); 
                        }
                    }

                    //以下分支用于采样天空盒颜色 
                    if (true) 
                    {
                        half sky_lod = 1.8154297 - (1.0 - 1.2 * log(rifr.w)) - 1;
                        half3 sky_raw = SAMPLE_TEXTURECUBE_LOD(_Sky, sampler_Sky, VR_lift, sky_lod).rgb;
                        gi_spec_base = sky_raw * V_CB1_180 * norm_shift_intensity + gi_spec_base;
                    }

                    half spec_AOwthRoughNoise = threshold;  //这里我给threshold重新命名，以免疑惑 
                    //下式用来构建 Lc -> 既 GI_Spec_Light_IN -> 或者按学界叫法: prefilter specular -> 原始数据采自预积分的环境光贴图IBL 
                    half3 prefilter_Specular = (ibl_spec_output + gi_spec_base * spec_AOwthRoughNoise) * 1.0 + spec_add;

                    if (matCondi.z) //对 #4 号渲染通道来说，spec需要很多额外处理 
                    {
                        //完成第一组环境光高光 
                        half2 lut_uv_1 = half2(NoV_sat, rifr.w);//这是第一组lut_uv，rifr.w->对应粗糙度rough2 
                        half2 lut_raw_1 = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, lut_uv_1);
                        half shifted_lut_bias = saturate(df_base.y * 50.0) * lut_raw_1.y * (1.0 - frxx_condi.x);
                        half gi_spec_brdf_1 = df_base.xyz * lut_raw_1.x + shifted_lut_bias; //第一组 GI_Spec 中的预积分 brdf输出值  
                        half3 gi_spec_1 = prefilter_Specular * gi_spec_brdf_1; //这是利用预积分技术重构出的 GI_Spec 

                        //完成第二组环境光高光(波瓣) 
                        half2 lut_uv_2 = half2(NoV_sat, frxx_condi.y); //这是第二组lut_uv，frxx_condi.y->对应粗糙度rough3 
                        half2 lut_raw_2 = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, lut_uv_2);
                        //第二个 GI_Spec 中的光照方程输出值，前面的frxx_condi.x可以理解为对某些像素的遮罩，不是预积分的Lc 
                        half gi_spec_brdf_2 = frxx_condi.x * (0.4 * lut_raw_2.x + lut_raw_2.y); 
                        //gi_spec_2 推测是对部分存在第二高光波瓣的材质进行二次环境光高光渲染的结果 (期间需要扣除一次'曝光'过程中的额外部分) 
                        half3 gi_spec_2 = gi_spec_1 * (1 - gi_spec_brdf_2) + spec_add_raw.xyz * gi_spec_brdf_2; 

                        //spec_mask -> 来自高光贴图alpha通道被1减的结果 (代表了强度) 
                        //gi_spec_brdf_2 -> 本身是基于视角和法线计算出的光照强度分布(也是强度) 
                        //AOwthRoughNoise -> 则是光照强度遮罩 
                        half spec_second_intensity = spec_mask * gi_spec_brdf_2 * AOwthRoughNoise;  //该参数后面会影响第二高光的强度 
                        half RN_shift_intensity = 0;                //带求的扰动强度 
                        half3 gi_spec_second_base = half3(0, 0, 0);    //带求的第二波瓣颜色 
                        //下面的分支用于输出属于 #4 号通道专有的 gi_spec_second_base(既第二波瓣颜色) 
                        //以及 RN_shift_intensity(基于RN的扰动强度) 
                        if (true)  //这条分支又cb[0].x 控制，总是可以进入 
                        {
                            half RN_raw_Len = sqrt(dot(d_norm, d_norm));
                            RN_shift_intensity = RN_raw_Len;
                            if (true) //cb1[189].x 用十六进制解码后得 0x00000001 -> true 
                            {
                                //从frxx(T11)纹理中y通道提取rough数值,对没有数值的部分(木制件,茅草屋顶等部分)确保数值不低于0.1 
                                half rough_chan4 = max(frxx_condi.y, 0.1); //从上下文环境看，这条rough为 #4号渲染通道专用 
                                RN_raw_Len = max(RN_raw_Len, 0.001);  

                                half asin_input = dot(d_norm, VR) / RN_raw_Len; 

                                tmp2.x = asin(asin_input) - abs(_pi * rough_chan4 - _pi * RN_raw_Len);
                                tmp2.y = (_pi * rough_chan4 + _pi * RN_raw_Len) - abs(_pi * rough_chan4 - _pi * RN_raw_Len);
                                tmp1 = saturate(tmp2.x / tmp2.y);
                                tmp1 = ((1.0 - tmp1) * (-2.0) + 3.0) * pow2(1.0 - tmp1);

                                RN_shift_intensity = saturate((_pi * RN_raw_Len - 0.1) * 5.0) * tmp1; //更新 RN_shift_intensity
                            }
                            
                            half rn_shift_rate = 0; //定义在 cb0_1_w 的调节比率，恒为0
                            RN_shift_intensity = lerp(RN_shift_intensity, 1.0, rn_shift_rate); 
                            gi_spec_second_base = V_CB0_1.xyz * (1.0 - RN_shift_intensity); //第二高光波瓣的三通道颜色强度 
                        }
                        else
                        {
                            gi_spec_second_base = half3(0, 0, 0);
                            RN_shift_intensity = 1.0; 
                        }

                        //以下通过使用view_reflection第二次采样IBL -> 计算 第二高光波瓣的强度 以及 第二高光颜色 
                        half lod_lv_spc2 = 6 - (1.0 - 1.2 * log(frxx_condi.y));  //与第二波瓣粗糙度(frxx.y)有关的采样LOD等级，魔法数字6来自cb0 
                        half threshold_2 = spec_second_intensity; //第二高光波瓣的强度 
                        half3 ibl_spec2_output = half3(0, 0, 0);  //第二高光颜色 

                        [unroll] for (uint i = 0; i < ret_from_t3_buffer_1 && threshold_2 >= 0.001; i++)
                        {
                            //判断当前场景‘激活’的IBL探针，如果当前像素点能被某张IBL影响，则进入内部 if 分支执行逻辑 
                            uint tb4_idx = i + ret_from_t3_buffer_2;
                            //下面跳过了使用 tb4_idx 来获取索引的步骤 -> t4和t3一样，也是张映射表 
                            //ld_indexable(buffer)(short,short,short,short) out, tb4_idx, t4.x  -> 使用tb4_idx=[0-8]采样返回都是"6" 
                            //这里使用视检过的"正确值" -> out = 12 来替代 
                            half3 v_PixelToProbe = posWS - cb4_12.xyz;  //r7.xyz
                            half d_PixelToProbe_square = dot(v_PixelToProbe, v_PixelToProbe); //像素到探针距离的平方 
                            half d_PixelToProbe = sqrt(d_PixelToProbe_square);      //像素到探针的距离 
                            if (d_PixelToProbe < cb4_12.w)  //测试当前像素所在世界坐标是否在目标Probe的作用范围内 
                            {
                                half d_rate = saturate(d_PixelToProbe / cb4_12.w); //距离占比  
                                half VRoP2P = dot(VR, v_PixelToProbe);  //注:第一次求spec时使用的是 VR_Lift 
                                //下式形式为: Scale * VR + v_PixelToProbe - [200,0,0] 
                                half3 shifted_p2p_dir_2 = (sqrt(pow2(VRoP2P) - (d_PixelToProbe_square - pow2(cb4_12.w))) - VRoP2P) * VR + v_PixelToProbe - half3(200, 0, 0);
                                
                                tmp1 = max(2.5 * d_rate - 1.5, 0);  //如果 (像素到探针的距离 / 探针影响半径R) < 0.6 -> 上式一律返回 0 
                                half rate_factor = 1.0 - (3.0 - 2.0 * tmp1) * pow2(tmp1); //距离缩放因子 
                                //shifted_p2p_dir_2 是采样cubemap的方向指针 
                                //IBL_cubemap_array的index由 cb4[12 + 341].y 获得，当前值为 "13" 
                                //注意，由于没有以Cubemap_array形式导入原始资源，故如下采样的uv参数中没有第四维(array索引) 
                                half4 ibl_raw_2 = SAMPLE_TEXTURECUBE_LOD(_IBL, sampler_IBL, shifted_p2p_dir_2, lod_lv_spc2).rgba; 
                                //更新 ibl_spec2_output -> cb4_353.x=1 
                                ibl_spec2_output = (cb4_353.x * ibl_raw_2.rgb) * rate_factor * threshold_2 * RN_shift_intensity + ibl_spec2_output; 
                                //更新 threshold_2 -> spec_second_intensity 
                                threshold_2 = threshold_2 * (1.0 - rate_factor * ibl_raw_2.a); 
                            }
                        }

                        //第二次采样天空盒  
                        if (true)  //总是进入 
                        {
                            half sky_lod_2 = 1.8154297 - (1.0 - 1.2 * log(frxx_condi.y)) - 1;
                            half3 sky_raw_2 = SAMPLE_TEXTURECUBE_LOD(_Sky, sampler_Sky, VR, sky_lod_2).rgb;
                            gi_spec_second_base = sky_raw_2 * V_CB1_180 * RN_shift_intensity + gi_spec_second_base; //为gi_spec追加天空盒的贡献 
                        }
                        
                        half spec_second_intensity_final = threshold_2; //重新命名下，以免糊涂 
                        half3 ibl_scale_3chan = half3(1, 1, 1);  //用于替代 cb1_156_xyz 中的数据 -> 缩放 ibl_spec2 
                        half3 scale_second_spec = half3(1, 1, 1);          //用于替代 cb1_134_yyy 中的数据 -> 缩放 第二高光的总和 
                        
                        //ibl_spec2_output * ibl_scale_3chan -> 主要来自‘IBL贴图颜色’与‘第二高光强度’的混合 -> 代表了 GI_Spec_second_Mirror 
                        //gi_spec_second_base * spec_second_intensity_final -> 主要来自‘阳光颜色’与‘第二高光强度’的混合 -> 代表了 GI_Spec_second_Diffuse 
                        //gi_spec_2 -> 是经过调整的第一高光颜色 
                        Specular_Final = (ibl_spec2_output * ibl_scale_3chan + gi_spec_second_base * spec_second_intensity_final)* scale_second_spec + gi_spec_2; 
                    }
                    else  //不是 #4，也不是 #0 和 #7 的所有其他渲染通道 
                    {
                        half2 lut_uv_1 = half2(NoV_sat, rifr.w);  //这是第一组lut_uv，rifr.w->对应粗糙度rough2 
                        half2 lut_raw_1 = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, lut_uv_1); 
                        half shifted_lut_bias = saturate(df_base.y * 50.0) * lut_raw_1.y; 
                        half gi_spec_brdf_1 = df_base.xyz * lut_raw_1.x + shifted_lut_bias;  //第一组 GI_Spec 中的预积分 brdf输出值  
                        half3 gi_spec_1 = prefilter_Specular * gi_spec_brdf_1; 
                        Specular_Final = gi_spec_1;
                    }

                    Specular_Final = min(Specular_Final, half3(0, 0, 0));
                    output.xyz = Specular_Final;
                }
                else
                {
                    //o0.xyz = R10颜色 
                    //对于没有高光的部分 -> 直接返回R10颜色 -> R10颜色可以认为是 GI_Diffuse_Final 
                    output.xyz = R10.xyz; 
                }
                //TODO test
                return half4((output).xyz * 1, 1);
            }
            ENDHLSL
        }
    }
}
