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
            static float3 V_CB1_48 = float3(0.67306363582611, -0.465476632118225, -0.00000010974);
            static float3 V_CB1_49 = float3(0.116760797798633, 0.168832123279571, 0.411912322044372);
            static float3 V_CB1_50 = float3(-0.509014785289764, -0.736369132995605, 0.445718020200729);

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
                //UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
                OUT.vertex = TransformObjectToHClip(IN.vertex); 
                OUT.uv = IN.uv;

                return OUT;
            }

            half4 frag (v2f IN) : SV_Target
            {
                half4 test = half4(0, 0, 0, 0);  //JUST FOR SHOW CASE 

                //UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                //最终输出值
                half4 output = half4(0, 0, 0, 0);

                //辅助临时变量(存放计算中间量) 
                half tmp1 = 0; 
                half2 tmp2 = half2(0, 0);
                half3 tmp3 = half3(0, 0, 0);
                half3 tmp_col = half3(0, 0, 0);

                //Start here 
                half2 suv = IN.vertex.xy * screen_param.zw;     //screen uv 
                half2 coord = (IN.vertex.xy * screen_param.zw - 0.5) * IN.vertex.w * 2.0;  //[-1, +1] 
                //test = IN.vertex.wwww / 2; //使用Renderdoc截帧抓取输出颜色知 -> IN.vertex.w == 1.0 -> 符合正交投影中HClip.w的定义 

                //Sample Depth
                half d = SAMPLE_TEXTURE2D(_Depth, sampler_Depth, suv); 
                d = 1 / (d * 0.1);  // 这是之前透视摄像机记录的 HClip.z -> 数值上等于视空间z轴 
                
                //get h-clip space 
                half2 hclipXY = coord * d;  //这一步用于将DNC空间的平面，展开到齐次裁剪前的透视投影空间里 
                float4 hclip = float4(hclipXY.xy, d, 1);  //严格说这不是hclip的表述 -> 最后一维应当是d而不是1 
                                                          //使用1作为最后一维的量 -> 将float4(coord.xy, d, 1)视为在hclip中的一个点，参与矩阵变换 

                //use matrix_Inv_VP to rebuild posWS 
                float4 posWS = mul(M_Inv_VP, hclip);  //注意UE4下，posWS的单位是 "厘米" 

                //cameraToPixelDir (取反得viewDir: 从视点触发指向摄像机) 
                half3 cameraToPixelDir = normalize(posWS.xyz - camPosWS); 
                half3 viewDir = -cameraToPixelDir;
                /*
                //开启这段代码用于交叉验证 posWS的准确性 -> 如果posWS不是像素点的世界坐标
                //那么摄像机世界坐标到posWS所描述的点的距离不会出现由进到远的分层效果 
                test.xyz = posWS.xyz - camPosWS;
                test.x = sqrt(dot(test.xyz, test.xyz)) / 1000;
                test.yz = 0;
                */

                //Sample Normal 
                half3 n = SAMPLE_TEXTURE2D(_Norm, sampler_Norm, suv); 
                n = n * 2 - 1; 
                half3 norm = normalize(n); 
                
                //get chessboard mask 
                uint2 jointPixelIdx = (uint2)(IN.vertex.xy); 
                uint chessboard = (jointPixelIdx.x + jointPixelIdx.y + 1) & 0x00000001; 
                half2 chessMask = chessboard ? half2(1, 0) : half2(0, 1); 

                //Sample _R_I_F_R 
                half4 rifr = SAMPLE_TEXTURE2D(_R_I_F_R, sampler_R_I_F_R, suv);     
                uint flag = (uint)round(rifr.z * 255.0);
                uint2 condi = flag & uint2(15, 16);//condi.x控制像素渲染逻辑(颜色表现丰富则噪点密集，表现单一则成块同色), y控制颜色混合;  
                /* 对condi的计算等效如下代码: 
                uint2 condi = uint2(flag & 0x0000000F, flag & 0x00000010); */ 

                //Sample _F_R_X_X
                float4 frxx = SAMPLE_TEXTURE2D(_F_R_X_X, sampler_F_R_X_X, suv);
                //下面frxx_condi的数据覆盖:衣服布料色(除缝线和划痕),树叶(绿色不连续，有随机间断),头部轮廓(彩) 
                float4 frxx_condi = condi.y ? float4(0, 0, 0, 0) : frxx.xyzw; //其x通道负责后续Fresnel项功能 

                //计算渲染通道mask, matCondi.xyz 分别对应 9, 5 和 4号渲染通道 -> 提供了随机的微小噪点 
                uint3 matCondi = condi.xxx == uint3(9, 5, 4).xyz; 

                //Sample Diffuse 
                half4 df = SAMPLE_TEXTURE2D(_Diffuse, sampler_Diffuse, suv); 
                //test = df;   

                //spec_power_mask 
                half spec_base_intensity = rifr.y * 0.08; 
                half factor_RoughOrZero = matCondi.x ? 0 : rifr.x;  //#9号通道时粗糙度为0， 其余情况使用贴图输出的rifr.x值(粗糙度:rough1) 
                //从‘spec_base_intensity’到 diffuse纹理所记载的漫反射颜色进行插值 
                //另一方面roughness越大，spec_power_mask越大，反之spec_power_mask接近于0 
                half4 spec_power_mask = half4( lerp(spec_base_intensity.xxx, df.xyz, factor_RoughOrZero).xyz, 0 ); //可以看出 spec_power_mask 似乎是不同材质Spec强度基础值
                //test.xyz = spec_power_mask; 
                
                //计算R10颜色 -> diffuse_base_col 
                uint is9or5 = matCondi.x | matCondi.y; 
                uint flag_r7z = 0;  // 0 < cb1[155].x ?  -> 注: 修改如下几个控制flag，会极大影响diffuse表现 
                uint flag_r7w = 1;  // 0 < cb1[200].z ? 
                uint and_r7z_w = flag_r7z & flag_r7w; 
                uint flag_ne_r7w = 0; // 0 != cb1[155].x ? 
                half3 R8 = flag_ne_r7w ? half3(1, 1, 1) : df.xyz; 
                //R11 -> 经过 或 没有经过 棋盘处理的 spec_power_mask 
                half4 R11 = and_r7z_w ? half4(spec_power_mask.xyz, rifr.y) * chessMask.y : half4(spec_power_mask.xyz, rifr.y);
                half4 R10 = half4(0, 0, 0, 0); 
                R10.xyz = and_r7z_w ? chessMask.xxx : R8.xyz; 
                R10.w = R11.w; 
                R10 = is9or5 ? R10 : half4(df.xyz, rifr.y);  //目前通过调整参数，让R10==df 

                //计算优化后的 NoV 输出到 spec_power_mask.w 中 -> 不是Lambert(NoL)，也不是Phong(NoH)，应该和Fresnel或漫反射强度相关 
                half NoV = dot(norm, viewDir);
                half NoV_sat = saturate(NoV);
                half a = (NoV_sat * 0.5 + 0.5) * NoV_sat - 1.0; //大体上在[-1, 0]区间上成二次曲线分布，N和V垂直得-1 
                half b = saturate(1.25 - 1.25 * rifr.w); //与纹理.rough2成反比，且调整了偏移和缩放 
                spec_power_mask.w = a * b; //这张输出图对比 NoV 来说，区间在[-1, 0]，且物体边缘数值绝对值大，中间值接近0 
                //上面的数值转换到 [0, 1] 区间，经过粗糙度处理，整体类似提亮后的NoV 
                half NoV_nearOne = spec_power_mask.w + 1.0;  //该值具有边缘暗中间亮的效果
                //NoV_nearOne 相比于 NoV_sat 色调差异小，明暗过渡柔和 
                
                //计算R12颜色 -> 按照视角的大小，表现出由暗到明的过渡(边缘暗中间亮) 
                //另外，col - (col^2 - col)*t -> 这种模式的颜色操作等效于对原始颜色进行 "非线性提亮" 
                half3 R12 = R10.xyz * 1.111111; 
                half3 NoV_soft = 0.85 * (NoV_sat - 1) * (1 - (R12 - 0.78 * (R12 * R12 - R12))) + 1; 
                R12 = R12 * NoV_soft;    //将基于NoV的环境光强度 -> 作用到 R10 颜色上(边缘压暗，中间相对提亮) 

                //NoV_nearOne算子与下面的(1 - frxx_condi.x * fresnel)功能相似 -> 边缘压暗(中间相对提亮)
                //R12颜色可以认为是基于R10(环境光基础色)将边缘压暗后的结果，与上式tmp_col比更加暗沉,具体可参考下面的test输出 
                //注意R12 = R10 * (一次NoV压暗:NoV_nearOne) * (第二次NoV压暗:NoV_soft) 
                R12 = 0.9 * NoV_nearOne * R12;

                //借用Fresnel返回值与1的互补数，构造tmp_col，使之具有类似R12的修正效果，但相比略亮一些 
                float p5 = pow5(1 - NoV_sat); 
                float fresnel = lerp(p5, 1, 0.04);                    //略微修正(增大)fresnel 
                //Fresnel项的特色众所周知(边缘亮中间暗)；frxx_condi.x则是来自纹理的遮罩，只在人物+草叶等物件上有数值 
                //frxx_condi.x * fresnel -> 对菲涅尔项添加遮罩，现在只有人物+草叶有Fresnel效果(数值大于0) 
                //(1 - frxx_condi.x * fresnel) -> 取反后被遮罩屏蔽的区域数值为 1；人物和草叶等变为反色(边缘暗中间亮) -> 作用类似NoV 
                //R10颜色推测为GI_Diffuse_Col -> 乘以上述缩放因子 -> 降低人物和草叶的边缘的亮度 
                tmp_col = R10.xyz * (1 - frxx_condi.x * fresnel);     //这里是将 Fresnel 项 -> 作用到 R10 颜色上 
                //test.xyz = tmp_col - R12; 
                
                //factor_RoughOrZero主要来自贴图rifr.x通道，只有人物和茅草屋顶有值 
                //frxx_condi.x * factor_RoughOrZero叠加后获得人物有值的遮罩 
                //通过lerp，在人物区域用上式中计算出的R12颜色(相对更加暗沉一些)，其他区域用tmp_col颜色(相对亮一些) 
                R12 = lerp(tmp_col, R12, frxx_condi.x * factor_RoughOrZero); 
                
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
                half4 g_norm_ld = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.zy); //左下 
                half4 g_norm_rd = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.xy); //右下 
                half4 g_norm_lu = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.zw); //左上 
                half4 g_norm_ru = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.xw); //右上 

                //利用(全局法线 & 深度)的差异做扰动，求颜色 R13 
                //首先下面基于屏幕像素索引的“奇偶”性，组合出网格状屏幕空间纹理 
                //从功能上看，scr_pat.xyzw 分别对应田字中左下，右，上和右上4个方位上像素(深度)的衰减值(或者叫权重)  
                tmp2 = (half2(1, 1) - delta_half_pixels).yx; 
                half4 scr_pat = half4(tmp2.x * tmp2.y, 
                    (delta_half_pixels * tmp2).xy, 
                    delta_half_pixels.x * delta_half_pixels.y); 
                //组合4次采样的深度 
                half4 depth4 = half4(g_norm_ld.w, g_norm_rd.w, g_norm_lu.w, g_norm_ru.w); //注,这里的w通道存放单位为里面的距离 
                depth4 = 1.0 / (abs(depth4 - d) + 0.0001) * scr_pat;   //[田的4个方位与中心点距离差的倒数 (差异越大数值越小)] * [4个方位的不同衰减幅度] 
                half g_depth_factor = 1.0 / dot(depth4, half4(1.0, 1.0, 1.0, 1.0));  //求和depth4的4个通道后取倒数 -> 作为求平均的乘子 
                //以下类似矩阵运算的过程，本质是求取屏幕空间法线的一种计算方式 
                //可以这样理解: depth4.xyzw代表了以当前像素点为中心周围4个方向的一种"梯度"，通过连续与对应方向的采样法线相乘和累加，相当于是将梯度值大小视作权，对4周法线加权求和  
                //最终结果 d_norm 应当兼具了法线走势，又具有较好连续性，且能够体现边缘处的变化 
                //d_norm -> depth-based normal:基于深度和4领域插值的世界空间法向量 
                //d_norm -> 还没归一化，其模长正比于物体表面的平坦程度: 既越平坦，模长越大 -> 主要归因于上式中 1/abs(depth4 - d) 部分 -> 越平坦数值越大 
                half3 d_norm = g_norm_ld.xyz * depth4.xxx + g_norm_rd.xyz * depth4.yyy + g_norm_lu.xyz * depth4.zzz + g_norm_ru.xyz * depth4.www; 

                //1/0.0001667 = 6000 -> 推测是编码距离时使用的极大值，20000推测是缩放系数 
                //整体来说:当d>20000时scale恒为0; 当14000<d<20000时scale在[0,1]区间上线性分布; 当d<14000时scale横为1 
                half scale = saturate((20000 - d) * 0.00016666666);      //Scale, 靠近摄像机->1，远离->0 
                d_norm = lerp(norm, d_norm * g_depth_factor, scale);     //这张基于4邻域深度差扰动后的d_norm看起来与_GNorm很像(可能略微模糊了一点?) 
                //test.xyz = d_norm;
                //if (condi.x)  //对于 #1 ~ #15 号渲染通道来说都能进入 
                if (true)       //这里修改原始定义，先让所有像素进入当前分支 -> 计算GI_Diffuse_Col 
                {
                    //依据是否是 #4号通道 -> 采样不同 diffuse (R12相对于R10在人物区域相对更加暗沉一些) 
                    //GI_Diffuse - GI_Diffuse * factor_RoughOrZero -> 调低了人物和茅屋顶的亮度 
                    half3 R15 = matCondi.z ? (R12.xyz - R12.xyz * factor_RoughOrZero) : (R10.xyz - R10.xyz * factor_RoughOrZero);

                    //RN 是归一化后的 d_norm -> RebuiltedNorm (或RN) 
                    half RN_Len = sqrt(dot(d_norm, d_norm));  //前面以及提及，RN_Len正比于物体表面的平坦程度 
                    half3 RN = d_norm / max(RN_Len, 0.00001); 
                    
                    //后续会使用的表面法线向量(对于 #7号渲染通道，会改写这个值)
                    half3 bias_N = lerp(RN, norm, RN_Len);  //对于平坦表面使用norm，边缘以及陡峭表面使用RN 

                    //计算AO_from_RN 
                    half RNoN = dot(RN, norm); //基于深度的法线 RN 与纹理法线 norm 之间的相似度 
                    half AO_from_RN = lerp(RNoN, 1, RN_Len);  //推测为AO -> 完全平坦时总是1，崎岖陡峭处返回RNoN -> 此时这个值也会很小  

                    //计算 computed_ao 
                    //备注1:log2_n = 1.442695 * ln_n 
                    //备注2:推测是经验公式(待考) -> 但是输出 computed_ao 可见对锐利边缘和暗部的检测效果很好 
                    half computed_ao = saturate(40.008 /(exp(-0.01*(RN_Len * 10.0 - 5))+1) - 19.504); 
                    computed_ao = pow(computed_ao, 0.7);    //0.7 -> cb0[8].w 
                    computed_ao = lerp(computed_ao, 1, 0);  //  0 -> cb0[1].w 

                    //以下计算AO_final -> 使用了 纹理采样的ao(df.w)，屏幕空间ao(ao)，以及上面计算的computed_ao进行多重混淆 
                    uint AO_blend_Type = (0 == 1);                  //其中 1 来自 cb0[9].x 
                    half min_of_texao_and_ssao = min(df.w, ao);     //min(Tex_AO, SSAO) 
                    half min_of_3_ao = min(computed_ao, min_of_texao_and_ssao); 
                    half mul_of_compuao_and_min_tx_ss_ao = computed_ao * min_of_texao_and_ssao; 
                    half AO_final = AO_blend_Type ? min_of_3_ao : mul_of_compuao_and_min_tx_ss_ao; 

                    uint4 matCondi2 = condi.xxxx == uint4(6, 2, 3, 7).xyzw; 
                    half3 frxxPow2 = frxx_condi.xyz * frxx_condi.xyz;  //该变量作用推测是作为颜色遮罩 -> 只对人物+草叶生效(尤其是人物) 
                    half3 ao_scale_from_6 = half3(0, 0, 0);
                    half3 ao_scale = half3(0, 0, 0);  //非 #6 号渲染通路也会在后面用类似如下的方法计算 common 变量 
                    //if (matCondi2.x)  // #6 号渲染通路 使用如下公式计算 virtual_light_from_6 
                    if(false) //TODO DELETE 
                    {
                        half4 neg_norm = half4(-norm.xyz, 1); 
                        half3 bias_neg_norm1 = mul(M_CB1_181, neg_norm);  //结果类似灰度图，主要区分了朝上和朝下方向的法线 
                        half3 rd_norm = norm.yzzx * norm.xyzz; 
                        half3 bias_neg_norm2 = mul(M_CB1_184, rd_norm);   //只对某个特定方向有响应，其余地方数值趋向于0 
                        //base_disturb * scale + bias 
                        half3 virtual_light_from_6 = V_CB1_187 * (norm.x*norm.x-norm.y*norm.y) + (bias_neg_norm1+bias_neg_norm2);
                        virtual_light_from_6 = V_CB1_180 * max(virtual_light_from_6, half3(0, 0, 0));

                        //#6号渲染通路对应的 AO -> 使用了 frxxPow2 作为遮罩，只对人物(还有草叶等)生效 
                        ao_scale_from_6 = AO_final * virtual_light_from_6 * frxxPow2;
                    }

                    uint is2or3 = matCondi2.y | matCondi2.z;  //#2 或 #3 号渲染通道
                    is2or3 = 0;         //TODO: 这里手动清除噪点  
                    R15 = is2or3 ? (frxxPow2 + R15) : R15;    //TODO: frxxPow2 + R15 -> T11.xyz 的具体含义 
                    //test.xyz = R15;

                    //if (matCondi2.w) // #7 号渲染通路 求其特有的基础 Diffuse -> 覆盖到 R15.xyz 
                    if ( false ) //TODO DELETE 
                    {
                        //使用 M_Inv_VP 的前3x3矩阵(去除仿射变换部分) 对处于NDC空间中的坐标(其中z轴固定为1)做变换
                        //所的结果可以认为是: 将摄像机到屏幕像素点的朝向(Direction)通过矩阵逆变换，转换到世界空间中
                        //TODO -> 优化时可精简 
                        half3 camToPixelDirRaw2 = V_CB1_48.xyz * coord.xxx;
                        camToPixelDirRaw2       = V_CB1_49.xyz * coord.yyy      + camToPixelDirRaw2;
                        camToPixelDirRaw2       = V_CB1_50.xyz * half3(1, 1, 1) + camToPixelDirRaw2;
                        half3 camToPxlDir2 = normalize(camToPixelDirRaw2); 
                        half3 viewDir2 = -camToPxlDir2;
                        //test.xyz = abs(viewDir - viewDir2);  //验证上述代码求解出的 viewDir 与 之前通过像素点世界坐标与摄像机坐标求解出的 viewDir 是一致的 

                        //待考证: 下面公式的最后加法部分如果使用 camToPxlDir2 替代 viewDir2 -> 所得向量接近光线折射方向 
                        //这样后续的许多计算将会看起来更加有"意义" 
                        half3 viewTangentRaw = dot(viewDir2, norm) * (-norm) + camToPxlDir2;  //viewTangentRaw(vt) 
                        half3 viewTangent = normalize(viewTangentRaw); 
                        bias_N = viewTangent;    //注: 该分支需要改写了bias_N的取值，bias_N后续会继续参与运算 

                        half rough_7 = min(1.0, max(rifr.w, 0.003922)); 

                        half ToV = dot(viewTangent, viewDir);   //ToV -> 掠视时得到最大值1;俯视时得最小值0; 45度斜视时得0.5
                        half ToN = dot(viewTangent, norm);      //ToN -> 横为0，因为Tangent和Nornmal互相垂直 
                        //test = ToN.xxxx * 1000; //作为验证，可以开启这段代码(需确保总是进入当前分支) 
                        half ang_NoV = acos(NoV); //我们知道NoV=1代表V和N同向(俯视) -> ang_NoV = acos(1) = 0，既俯视时偏暗；反之掠视时偏亮(最大得pi/2) 
                        //test = ang_NoV.xxxx / (_pi); //验证用 
                        half ang_ToN = acos(ToN); //应该恒为 pi/2  -> TODO: 优化时可精简 
                        //test = ang_ToN.xxxx / (_pi/2) * 0.5; //作为验证，使用renderdoc截取此输出，经过像素检测可知各处等于 0.5 -> 符合acos(0) = pi/2 的结果 

                        half cos_half_angle_TtoV = cos(abs(ang_NoV - ang_ToN) * 0.5); //俯视时为cos(π/4)=sqrt(2)/2，掠视时为cos(0)=1 
                        //test = cos_half_angle_TtoV.xxxx; //使用renderoc截帧查看俯视角度像素 -> 最小值在0.75附近 -> 符合预估的sqrt(2)/2 

                        half3 dir_A = norm * (-ToN) + viewTangent; //鉴于ToN恒为0，返回值恒为 viewTangent，这里用dir_A表示以示区别 
                        //test.xyz = abs(dir_A - viewTangent); 

                        half AoTraw = dot(dir_A, viewTangentRaw);
                        tmp1 = sqrt(dot(dir_A, dir_A) * dot(viewTangentRaw, viewTangentRaw) + 0.0001); //相当于求 |dir_A| * |viewTangentRaw|
                        half cos_AtoT = AoTraw * (1.0 / tmp1); //相当于求 dir_A 和 viewTangentRaw夹角的余弦值 -> cos(AtoT) = cos(0) = 1  

                        //以下可以看做是对cos值的 Scale 和 Transform 
                        half2 cos_AtoT_ST = half2(0.5, 17.0) * cos_AtoT + half2(0.5, -16.780001); 
                        cos_AtoT_ST.x = saturate(cos_AtoT_ST.x); 
                        half sqrt_cosAtoTst = sqrt(cos_AtoT_ST.x); //该值目前看恒为 1  

                        rough_7 = rough_7 * rough_7; 
                        half rough_factor_1 = rough_7 + 0.2; 
                        half rough_factor_2 = rough_7 * 2 + 0.2; 

                        half sin_NaV = sqrt(1 - NoV * NoV); 
                        half sin_NaV_ST = (0.997551 * sqrt_cosAtoTst) * sin_NaV + (-0.069943 * NoV);  //和cos_half_angle_TtoV表现的趋势一致，俯视时数值偏小，掠视时数值偏大 

                        tmp2 = (sqrt_cosAtoTst * rough_factor_1) * half2(1.414214, 3.544908);     //常数对照 -> (sqrt(2), 2*sqrt(π)) 
                        tmp1 = sqrt_cosAtoTst * exp(-0.5 * pow2((NoV + ToN) + 0.139886 * sin_NaV_ST) / pow2(tmp2.x)) / tmp2.y; //sqrt_cosAtoTst似乎可以和tmp2.y的构成元素互相约去 
                        //下式pow5会导致返回值非常接近0，如果使用pow2则能保留俯视角度的高亮感 
                        //dark_fresnel_intensity 输出的是一张数值整体接近0，但是在掠视方向被柔和提亮的强度图 
                        half dark_fresnel_intensity = tmp1 * (0.953479 * pow5(1 - sqrt(saturate(ToV * 0.5 + 0.5))) + 0.046521);
                        
                        //R10.w主要来自纹理rifr.y通道，代表整体的GI_Intensity遮罩
                        half gi_fresnel_dark_intensity = R10.w * dark_fresnel_intensity;

                        half ToV_sat = saturate(-ToV);   //迷思: 如果是T和V点乘，返回值总是正，后续计算将会变得无意义；如果是折射角点乘V，则当前行的处理合理 
                        half factor_ToV = 1 - ToV_sat;   //一般而言这个值都是 1

                        half bright_fresnel_intensity = exp((-0.5 * pow2((NoV + ToN) - 0.14)) / pow2(rough_factor_2)) / (rough_factor_2 * 2.506628); //2.506=sqrt(2π) 
                        
                        tmp1 = 0.953479 * pow5(1 - 0.5 * cos_half_angle_TtoV) + 0.046521; 
                        half lambert_intensity = pow2(1 - tmp1) * tmp1; //注意这个强度遮罩与前面菲涅尔遮罩不同，属于俯视时强度值大的类型 

                        half3 df_chan7 = pow(R10.xyz, 0.8/cos_half_angle_TtoV); //对R10漫反射颜色修正，俯视角下不变，掠视情况下提亮  
                        df_chan7 = df_chan7 * bright_fresnel_intensity * exp(cos_AtoT_ST.y) * lambert_intensity + factor_ToV * 0.5 * gi_fresnel_dark_intensity; 
                        //test.xyz = df_chan7; //检视节点结果 -> 较暗的场景 + 较亮的人物 + 相对突出的皮肤和窗户颜色 

                        //以下遮罩主要来自纹理 rifr.x -> 人物 + 茅草屋顶 
                        half mask_RoughOrZero = lerp(min(0.25*(1 + dot(viewTangent, viewTangent)), 1.0), (1 - abs(ToN)), 0.33) * factor_RoughOrZero * 0.318310;

                        //sqrt(R10.xyz) -> 提亮diffuse -> 之后再应用遮罩提取人物和屋顶(顺便压暗纹理) -> 最后追加df_chan7 
                        R10.xyz = sqrt(R10.xyz) * mask_RoughOrZero + df_chan7; 
                        R10.xyz = min(-R10.xyz, half3(0, 0, 0)); //结合下面乘 -π -> 这一步作用是抹去负数 
                        tmp3 = R10.xyz * half3(-_pi, -_pi, -_pi); //π * 基础环境光 -> 这里的π一般认为是着色点附近半球域光强度积分后的强度值  
                        R15.xyz = tmp3;
                        //test.xyz = R15;
                    }
                    
                    uint is8 = condi.x == uint(8); 
                    is8 = 0; //TODO: 手动清除噪点 
                    R10.xyz = frxxPow2.xyz * frxx_condi.w + R15.xyz; 
                    R10.xyz = is8 ? R10.xyz : R15.xyz; 
                    
                    //以下逻辑与之前处理 #6 渲染通道时雷同 
                    //推测是计算 GI_Virtual_Directional_Light 的照射强度，因为计算结合依赖于表面法线的某几个维度 
                    half4 biasN = half4(bias_N.xyz, 1.0);   //测试调整为bias_N.xzy 与 bias_N.xyz对比 
                    half3 bias_biasN = mul(M_CB1_181, biasN); 
                    half4 mixN = biasN.yzzx * biasN.xyzz; 
                    half3 bias_mixN = mul(M_CB1_184, mixN);  //值域小于0，查看时使用 -bias_mixN  
                    //base_disturb * scale + bias 
                    half3 virtual_light = V_CB1_187 * (biasN.x * biasN.x - biasN.y * biasN.y) + (bias_biasN + bias_mixN);
                    virtual_light = V_CB1_180 * max(virtual_light, half3(0, 0, 0));   //经过V_CB1_180缩放后，返回值可能会大于1.0 
                    //test.xyz = virtual_light * 0.5;
                    //#6号渲染通路的disturb返回值最终是基于"法线扰动" & "AO" & "材质参数"的混合 
                    ao_scale = AO_from_RN * AO_final * virtual_light + V_CB0_1 * (1 - AO_final); 
                    
                    R10.xyz = R10.xyz * ao_scale + ao_scale_from_6;  //这是个颜色, 推测为完整的 Diffuse 
                    //test.xyz = R10.xyz;

                    half intense = dot(half3(0.3, 0.59, 0.11), R10.xyz); 
                    half check = 1.0 == 0;      //返回false -> 相当于关闭了alpha通道 -> cb1[200].z == 0 ? 
                    //output.alpha 主要来自于从R10(gi_diffuse)颜色提取的光强度值 -> intense 
                    //除此之外还需要手动开启 check符号位 以及符合 #9或#5号渲染通道，不然alpha输出值为0 
                    output.w = half((uint(check) & uint(intense)) & is9or5);    //此处返回恒为 0 
                }
                else //对于 #0 号 渲染通道  
                {
                    R10 = half4(0, 0, 0, 0); 
                    output.w = 0; 
                }

                //到此为止完成了 GI_Diffuse 
                //test.xyz = R10; 

                uint2 is0or7 = condi.xxx != uint2(0, 7).xy; 
                //if ((is0or7.x & is0or7.y) != 0)  //既不是 #0号 也不是 #7 号渲染通道 
                if (true)  //TODO DELETE 
                {
                    //GI_Spec 计算部分在此 
                    half3 Specular_Final = half3(0, 0, 0);
                    half3 gi_spec_base = half3(0, 0, 0);

                    //首先依据是否是9or5号渲染通道，选择R11=spec_power_mask(?*方块Mask.y) 或 spec_power_mask 
                    spec_power_mask.xyz = is9or5 ? R11.xyz : spec_power_mask.xyz;
                    
                    //如下tmp1数值普遍在0.5左右，人物的边缘轮廓附近数值更低0.4左右 
                    tmp1 = (frxx_condi.x * spec_power_mask.w + 1) * 0.08; //spec_power_mask.w是与rough和NoV有关的值，处于[-1,0]区间；frxx_condi.x作为遮罩用于屏蔽指定像素 
                    R11.xyz = lerp(tmp1, R12, factor_RoughOrZero); //R11颜色是基于 R12(除人物略暗外其他接近df) 做的lerp  
                    spec_power_mask.xyz = matCondi.z ? R11.xyz : spec_power_mask.xyz;  //如果是 #4 渲染通道 设置 spec_power_mask 为 上面计算出来的R11颜色 
                    
                    half3 VR = (NoV + NoV) * norm + cameraToPixelDir;  //View_Reflection -> VR:视线反射方向 
                    
                    half roughSquare = rifr.w* rifr.w;
                    //下式对应函数图像 -> 可近似为开口朝向的二次曲线，过y轴正1，同时与x轴正负1相交 
                    half rate = (roughSquare + sqrt(1 - roughSquare)) * (1 - roughSquare);  //约 0.63 -> 某种rate系数 
                    half3 VR_lift = lerp(norm, VR, rate);  //暂且定义为‘上抬视反’(注:没有归一化) ，具体反射向量上抬角度受rough控制 -> 简言之越粗糙，反射视线越接近法线朝向 
                    
                    //使用屏幕UV采样 T12 -> 这张纹理看起来对水晶,金属扣环等物体做了处理 -> 疑似关联 spec 
                    //T12.xyz分量推测是对高光项的线性的附加补充量
                    //T12.w分量是高光项的强度 
                    half4 spec_add_raw = SAMPLE_TEXTURE2D(_Spec, sampler_Spec, suv);
                    half spec_mask = 1 - spec_add_raw.w;  //后续会作用到环境光第二高光波瓣强度的重建过程中 -> 强度遮罩 -> 此处恒为0 
                    //如下可知 frxx_condi.x 非0既1 -> 当0时使用采样T12纹理的采样返回值(w分量取1的互补数)；当1时xyz高光附加颜色分量置为0(而w通道被置为1) 
                    half4 spec_add = matCondi.z ? (frxx_condi.x * half4(-spec_add_raw.xyz, spec_add_raw.w) + half4(spec_add_raw.xyz, spec_mask)) : half4(spec_add_raw.xyz, spec_mask);

                    //如下输出的是被T12.w通道修正过的'AO噪声'高频部分系数 
                    half mixed_ao = df.w * ao + NoV_sat; //TexAO * Computered_AO(SSAO.r) + saturate(NdotV) -> mixed_AO 
                    half AOwthRoughNoise = df.w * ao + pow(mixed_ao, roughSquare); 
                    AOwthRoughNoise = saturate(AOwthRoughNoise - 1);  //-> r0.y -> 只截取超过1的部分，这部分可以看做是AO叠加上Rough后的高频噪声 
                    //half spec_scaler = spec_add.w;    //spec_add.w是高光强度控制阀 
                    half spec_scaler = 0.5;             //TODO: 避免噪点，使用0.5替代spec_add.w 
                    half spec_first_intensity = spec_scaler * AOwthRoughNoise; 

                    //以下逻辑用于计算索引 -> 最终用于获取IBL贴图 
                    uint2 screenPixelXY = uint2(IN.vertex.xy); 
                    uint logOfDepth = uint(max(log(d * 1 + 1) * 1, 0));  //剔除深度对数小于0的部分 -> 排除太过接近的距离 
                    //test.xyz = logOfDepth/3;  //对于人物来说，其logOfDepth返回值等于2 
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
                    half smoothness = 0;            //该参数和gi_spec_base是下面逻辑分支的主要计算目标 
                    if (true)  //这条分支又cb[0].x 控制，总是可以进入 
                    {
                        half RN_raw_Len = sqrt(dot(d_norm, d_norm));
                        smoothness = RN_raw_Len;  //重建的norm是多个norm合成值，如果参与合成的norms方差较大，会分散合力，造成RN向量的模长较小 
                        //test = smoothness;
                        //计算过程中使用到了: |Rn_raw|, roughness, asin(dot(Rn,'上抬视反')/|Rn|) -> 推测为经验公式 
                        if (true) //cb1[189].x 用十六进制解码后得 0x00000001 -> true 
                        {
                            //if (is6) //处理 #6 渲染通道 
                            if(false)  //TODO DELETE 
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

                                smoothness = saturate((_pi* RN_raw_Len - 0.1) * 5.0)* tmp1; //更新 smoothness 
                            }
                        }
                        half cb0_1_w_rate = 0;
                        smoothness = lerp(smoothness, 1.0, cb0_1_w_rate);
                        gi_spec_base = (1.0 - smoothness) * V_CB0_1.xyz;
                        //test.xyz = gi_spec_base;
                    }
                    else
                    {
                        gi_spec_base = half3(0, 0, 0);  
                        smoothness = 1;
                    }
                    //<---------- 
                    half lod_lv = 6 - (1.0 - 1.2 * log(rifr.w));  //与粗糙度有关的采样LOD等级，魔法数字6来自cb0 
                    half threshold = spec_first_intensity;
                    half3 ibl_spec_output = half3(0, 0, 0);  //这是如下for循环的主要输出 
                    //注意: ret_from_t3_buffer_1是使用‘屏幕像素’与‘距离对数’组合出索引 -> 再从 T3 buffer 中取得的映射值 
                    //该映射返回值的取值范围要么是 0, 要么 1 
                    //推测是依据距离远景和是否处于屏幕中心，判断是否要开启当前像素的环境光贴图采样逻辑 
                    //此外 spec_first_intensity 本身是多重AO以及Rough计算得出  
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
                        //half probe_range = cb4_12.w;
                        half probe_range = 10000;
                        if (d_PixelToProbe < probe_range)  //测试当前像素所在世界坐标是否在目标Probe的作用范围内 
                        //if (true)  //测试当前像素所在世界坐标是否在目标Probe的作用范围内 
                        {
                            half d_rate = saturate(d_PixelToProbe / probe_range); //距离占比 
                            half VRLoP2P = dot(VR_lift, v_PixelToProbe); 
                            //下式形式为: Scale * VR_lift + v_PixelToProbe - [200,0,0] 
                            half3 shifted_p2p_dir = (sqrt(pow2(VRLoP2P) - (d_PixelToProbe_square - pow2(probe_range))) - VRLoP2P) * VR_lift + v_PixelToProbe - half3(200, 0, 0);
                            tmp1 = max(2.5 * d_rate - 1.5, 0);  //如果 (像素到探针的距离 / 探针影响半径R) < 0.6 -> 上式一律返回 0 
                            half rate_factor = 1.0 - (3.0 - 2.0 * tmp1) * pow2(tmp1); //距离缩放因子 
                            //shifted_p2p_dir 是采样cubemap的方向指针 
                            //IBL_cubemap_array的index由 cb4[12 + 341].y 获得，当前值为 "13"  
                            //注意，由于没有以Cubemap_array形式导入原始资源，故如下采样的uv参数中没有第四维(array索引) 
                            half4 ibl_raw = SAMPLE_TEXTURECUBE_LOD(_IBL, sampler_IBL, shifted_p2p_dir, lod_lv).rgba;
                            //更新 ibl_spec_output 
                            ibl_spec_output = (cb4_353.x * ibl_raw.rgb) * rate_factor * threshold * smoothness + ibl_spec_output;
                            //更新 threshold -> spec_first_intensity 
                            threshold = threshold * (1.0 - rate_factor * ibl_raw.a); 
                            //test.xyz = ibl_spec_output;  
                        }
                        
                    }

                    //以下分支用于采样天空盒颜色 
                    if (true) 
                    {
                        half sky_lod = 1.8154297 - (1.0 - 1.2 * log(rifr.w)) - 1;
                        half3 sky_raw = SAMPLE_TEXTURECUBE_LOD(_Sky, sampler_Sky, VR_lift, sky_lod).rgb;
                        gi_spec_base = sky_raw * V_CB1_180 * smoothness + gi_spec_base;
                        //test.xyz = gi_spec_base;
                    }

                    spec_first_intensity = threshold;  //这里我给threshold重新命名，以免疑惑 
                    //下式用来构建 Lc -> 既 GI_Spec_Light_IN -> 或者按学界叫法: prefilter specular -> 原始数据采自预积分的环境光贴图IBL 
                    half3 prefilter_Specular = (ibl_spec_output + gi_spec_base * spec_first_intensity) * 1.0 + spec_add;
                    
                    //if (matCondi.z) //对 #4 号渲染通道来说，spec需要很多额外处理 
                    if(true)  //TODO DELETE 
                    {
                        //完成第一组环境光高光 
                        half2 lut_uv_1 = half2(NoV_sat, rifr.w);//这是第一组lut_uv，rifr.w->对应粗糙度rough2 
                        half2 lut_raw_1 = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, lut_uv_1); 
                        half shifted_lut_bias = saturate(spec_power_mask.y * 50.0) * lut_raw_1.y * (1.0 - frxx_condi.x);
                        half3 gi_spec_brdf_1 = spec_power_mask.xyz * lut_raw_1.x + shifted_lut_bias; //第一组 GI_Spec 中的预积分 brdf输出值 
                        half3 gi_spec_1 = prefilter_Specular * gi_spec_brdf_1; //这是利用预积分技术重构出的 GI_Spec 
                        //test.xyz = gi_spec_1 * 1;
                        
                        //完成第二组环境光高光(波瓣) 
                        half2 lut_uv_2 = half2(NoV_sat, frxx_condi.y); //这是第二组lut_uv，frxx_condi.y->对应粗糙度rough3 
                        half2 lut_raw_2 = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, lut_uv_2);
                        //第二个 GI_Spec 中的光照方程输出值，前面的frxx_condi.x可以理解为对某些像素的遮罩，不是预积分的Lc 
                        half gi_spec_brdf_2 = frxx_condi.x * (0.04 * lut_raw_2.x + lut_raw_2.y); 
                        //gi_spec_2 推测是对部分存在第二高光波瓣的材质进行二次环境光高光渲染的结果 (期间需要扣除一次'曝光'过程中的额外部分) 
                        half3 gi_spec_2 = gi_spec_1 * (1 - gi_spec_brdf_2) + spec_add_raw.xyz * gi_spec_brdf_2; 
                        
                        //spec_mask -> 来自高光贴图alpha通道被1减的结果 (代表了强度) 
                        //gi_spec_brdf_2 -> 本身是基于视角和法线计算出的光照强度分布(也是强度) 
                        //AOwthRoughNoise -> 则是光照强度遮罩 
                        half spec_second_intensity = spec_mask * gi_spec_brdf_2 * AOwthRoughNoise;  //该参数后面会影响第二高光的强度 
                        half smoothness_2 = 0;                //带求的扰动强度 
                        half3 gi_spec_second_base = half3(0, 0, 0);    //带求的第二波瓣颜色 
                        //下面的分支用于输出属于 #4 号通道专有的 gi_spec_second_base(既第二波瓣颜色) 
                        //以及 smoothness_2 (基于RN扰动的强度) 
                        if (true)  //这条分支又cb[0].x 控制，总是可以进入 
                        {
                            half RN_raw_Len = sqrt(dot(d_norm, d_norm));
                            smoothness_2 = RN_raw_Len;
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

                                smoothness_2 = saturate((_pi * RN_raw_Len - 0.1) * 5.0) * tmp1; //更新 smoothness_2
                            }
                            
                            half rn_shift_rate = 0; //定义在 cb0_1_w 的调节比率，恒为0
                            smoothness_2 = lerp(smoothness_2, 1.0, rn_shift_rate);
                            gi_spec_second_base = V_CB0_1.xyz * (1.0 - smoothness_2); //第二高光波瓣的三通道颜色强度 
                        }
                        else
                        {
                            gi_spec_second_base = half3(0, 0, 0);
                            smoothness_2 = 1.0;
                        }

                        //以下通过使用view_reflection第二次采样IBL -> 计算 第二高光波瓣的强度 以及 第二高光颜色 
                        half lod_lv_spc2 = 6 - (1.0 - 1.2 * log(frxx_condi.y));  //与第二波瓣粗糙度(frxx.y)有关的采样LOD等级，魔法数字6来自cb0 
                        half threshold_2 = spec_second_intensity; //第二高光波瓣的强度 -> 受spec_mask影响，此只恒为0 
                        half3 ibl_spec2_output = half3(0, 0, 0);  //第二高光颜色 

                        [unroll] for (uint i = 0; i < ret_from_t3_buffer_1 && threshold_2 >= 0.001; i++) //因为threshold_2的缘故，这里进不去 
                        {
                            //判断当前场景‘激活’的IBL探针，如果当前像素点能被某张IBL影响，则进入内部 if 分支执行逻辑 
                            uint tb4_idx = i + ret_from_t3_buffer_2;
                            //下面跳过了使用 tb4_idx 来获取索引的步骤 -> t4和t3一样，也是张映射表 
                            //ld_indexable(buffer)(short,short,short,short) out, tb4_idx, t4.x  -> 使用tb4_idx=[0-8]采样返回都是"6" 
                            //这里使用视检过的"正确值" -> out = 12 来替代 
                            half3 v_PixelToProbe = posWS - cb4_12.xyz;  //r7.xyz
                            half d_PixelToProbe_square = dot(v_PixelToProbe, v_PixelToProbe); //像素到探针距离的平方 
                            half d_PixelToProbe = sqrt(d_PixelToProbe_square);      //像素到探针的距离 
                            //half probe_range_2 = cb4_12.w;
                            half probe_range_2 = 10000;
                            if (d_PixelToProbe < probe_range_2)  //测试当前像素所在世界坐标是否在目标Probe的作用范围内 
                            {
                                half d_rate = saturate(d_PixelToProbe / probe_range_2); //距离占比  
                                half VRoP2P = dot(VR, v_PixelToProbe);  //注:第一次求spec时使用的是 VR_Lift 
                                //下式形式为: Scale * VR + v_PixelToProbe - [200,0,0] 
                                half3 shifted_p2p_dir_2 = (sqrt(pow2(VRoP2P) - (d_PixelToProbe_square - pow2(probe_range_2))) - VRoP2P) * VR + v_PixelToProbe - half3(200, 0, 0);
                                
                                tmp1 = max(2.5 * d_rate - 1.5, 0);  //如果 (像素到探针的距离 / 探针影响半径R) < 0.6 -> 上式一律返回 0 
                                half rate_factor = 1.0 - (3.0 - 2.0 * tmp1) * pow2(tmp1); //距离缩放因子 
                                //shifted_p2p_dir_2 是采样cubemap的方向指针 
                                //IBL_cubemap_array的index由 cb4[12 + 341].y 获得，当前值为 "13" 
                                //注意，由于没有以Cubemap_array形式导入原始资源，故如下采样的uv参数中没有第四维(array索引) 
                                half4 ibl_raw_2 = SAMPLE_TEXTURECUBE_LOD(_IBL, sampler_IBL, shifted_p2p_dir_2, lod_lv_spc2).rgba; 
                                //更新 ibl_spec2_output -> cb4_353.x=1 
                                ibl_spec2_output = (cb4_353.x * ibl_raw_2.rgb) * rate_factor * threshold_2 * smoothness_2 + ibl_spec2_output;
                                //更新 threshold_2 -> spec_second_intensity 
                                threshold_2 = threshold_2 * (1.0 - rate_factor * ibl_raw_2.a); 
                            }
                        }

                        //第二次采样天空盒  
                        if (true)  //总是进入 
                        {
                            half sky_lod_2 = 1.8154297 - (1.0 - 1.2 * log(frxx_condi.y)) - 1;
                            half3 sky_raw_2 = SAMPLE_TEXTURECUBE_LOD(_Sky, sampler_Sky, VR, sky_lod_2).rgb;
                            gi_spec_second_base = sky_raw_2 * V_CB1_180 * smoothness_2 + gi_spec_second_base; //为gi_spec追加天空盒的贡献 
                        }
                        
                        half spec_second_intensity_final = threshold_2; //重新命名下，以免糊涂 
                        half3 ibl_scale_3chan = half3(1, 1, 1);         //用于替代 cb1_156_xyz 中的数据 -> 缩放 ibl_spec2 
                        half3 scale_second_spec = half3(1, 1, 1);       //用于替代 cb1_134_yyy 中的数据 -> 缩放 第二高光的总和 
                        
                        //ibl_spec2_output * ibl_scale_3chan -> 主要来自‘IBL贴图颜色’与‘第二高光强度’的混合 -> 代表了 GI_Spec_second_Mirror 
                        //gi_spec_second_base * spec_second_intensity_final -> 主要来自‘阳光颜色’与‘第二高光强度’的混合 -> 代表了 GI_Spec_second_Diffuse 
                        //gi_spec_2 -> 是经过调整的第一高光颜色 
                        Specular_Final = (ibl_spec2_output * ibl_scale_3chan + gi_spec_second_base * spec_second_intensity_final)* scale_second_spec + gi_spec_2; 

                        //test.xyz = Specular_Final;
                    }
                    else  //不是 #4，也不是 #0 和 #7 的所有其他渲染通道 
                    {
                        half2 lut_uv_1 = half2(NoV_sat, rifr.w);  //这是第一组lut_uv，rifr.w->对应粗糙度rough2 
                        half2 lut_raw_1 = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, lut_uv_1); 
                        half shifted_lut_bias = saturate(spec_power_mask.y * 50.0) * lut_raw_1.y;
                        half3 gi_spec_brdf_1 = spec_power_mask.xyz * lut_raw_1.x + shifted_lut_bias;  //第一组 GI_Spec 中的预积分 brdf输出值  
                        half3 gi_spec_1 = prefilter_Specular * gi_spec_brdf_1; 
                        Specular_Final = gi_spec_1;
                    }

                    Specular_Final = min(-Specular_Final, half3(0, 0, 0)); 
                    output.xyz = -Specular_Final + R10.xyz; 
                    //test.xyz = output.xyz; 
                }
                else
                {
                    //o0.xyz = R10颜色 
                    //对于没有高光的部分 -> 直接返回R10颜色 -> R10颜色可以认为是 GI_Diffuse_Final 
                    output.xyz = R10.xyz; 
                }
                
                test = output;
                return half4((test).xyz, output.w); //for test only 
                //return half4((output).xyz, output.w); 
            }
            ENDHLSL
        }
    }
}
