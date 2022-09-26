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

            static float4 screen_param = float4(1708, 960, 1.0/1708, 1.0/960);  //���ǽ�֡ʱ����Ļ������Ϣ 
            //37 15 13&12 + 341 = 353/4:13 356:9 378:17 -> ѡ12/13,353/354,13
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
                d = 1 / (d * 0.1);  // Clip.z, ��ԭʼd*0.1�Ʋ��ǽ����ȵ�λ�� cm -> m 
                
                //get h-clip space 
                coord = coord * d; 
                half4 hclip = half4(coord.xy, d, 1);

                //use matrix_Inv_VP to rebuild posWS 
                half4 posWS = mul(M_Inv_VP, hclip);  //ע���ʱ��λ���� "����" 

                //ViewDir (ʹ��ʱȡ��: ���ӵ㴥��ָ�������) 
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
                uint2 condi = flag & uint2(15, 16);//condi.x����������Ⱦ�߼�(��ɫ���ַḻ������ܼ������ֵ�һ��ɿ�ͬɫ), y������ɫ���;  

                //Sample _F_R_X_X
                float4 frxx = SAMPLE_TEXTURE2D(_F_R_X_X, sampler_F_R_X_X, suv);
                //����frxx_condi�����ݸ���:�·�����ɫ(�����ߺͻ���),��Ҷ(��ɫ����������������),ͷ������(��)   
                float4 frxx_condi = condi.y == 16 ? float4(0, 0, 0, 0) : frxx.xyzw; //��xͨ���������Fresnel��� 

                //������Ⱦͨ��mask, matCondi.xyz �ֱ��Ӧ 9, 5 �� 4����Ⱦͨ�� -> �ṩ�������΢С��� 
                uint3 matCondi = condi.xxx == uint3(9, 5, 4).xyz; 

                //Sample Diffuse 
                half4 df = SAMPLE_TEXTURE2D(_Diffuse, sampler_Diffuse, suv); 

                //Diffuse_GI_base 
                half base_intensity = rifr.y * 0.08;
                half4 df_delta = df.xyzw - base_intensity; //��������ͼ�м�ȥ���ֹ�ǿ�� -> ���²��ָ����Ȳ���(Ƥ��+������) 
                half factor_RoughOrZero = matCondi.x ? 0 : rifr.x; //rifr.x=rough,ֻ���ݶ�+������ֵ 
                
                //�Ӳ���df���ȿ۳�ǿ��,���"dif_delta",�ٶ�������(��Ҫ���ڲ��������rough)������ټӻؿ۳��Ĺ�ǿ 
                half4 df_base = df_delta * factor_RoughOrZero + base_intensity; 

                //���㼯���м�̬��ɫ: R8, R10 �� R11 
                uint is9or5 = matCondi.x | matCondi.y;
                half3 R8 = half3(1, 1, 1);  //TODO 
                half4 R11 = half4(df_base.xyz, rifr.y) * chessMask.y;       //�������̴���� df_base 
                half4 R10 = is9or5 ? half4(chessMask.xxx, R11.w) : half4(df.xyz, rifr.y);  //��������+�����������ʾdiffse,�������ƺڰ���� 

                //�����Ż���� NoV ����� df_base.w �� -> ����Lambert(NoL)��Ҳ����Phong(NoH)��Ӧ�ú�Fresnel��������ǿ����� 
                half NoV = dot(norm, -viewDir);
                half NoV_sat = saturate(NoV);
                half a = (NoV_sat * 0.5 + 0.5) * NoV_sat - 1.0; //��������[-1, 0]�����ϳɶ��λ��߷ֲ���N��V��ֱ��-1 
                half b = saturate(1.25 - 1.25 * rifr.w); //������.rough2�ɷ��ȣ������������ƫ�ƺ����� 
                df_base.w = a * b; //�������ͼ�Ա� NoV ��˵��������[-1, 0]���������Ե��ֵ����ֵ���м�ֵ�ӽ�0 
                half NoV_nearOne = df_base.w + 1.0; //�������ֵת���� [0, 1] ���䣬��������������NoV����ֱ��0(��Ե��)��ͬ���1(�м���) 
                
                //����R12��ɫ 
                half3 R12 = R10.xyz * 1.111111;
                half3 tmp_col = 0.85 * (NoV_sat - 1) * (1 - (R12 - 0.78*(R12 * R12 - R12))) + 1; 
                R12 = R12 * tmp_col;    //������NoV�Ļ�����ǿ�� -> ���õ� R10 ��ɫ�� 

                //ʩ��FresnelӰ�� 
                float p5 = pow5(1 - NoV_sat);
                float fresnel = 0.04 * (1 - p5) + p5;                 //TODO:���F����㷽ʽ��ժ¼ 
                tmp_col = R10.xyz * (1 - frxx_condi.x * fresnel);     //�����ǽ� Fresnel �� -> ���õ� R10 ��ɫ�� 
                R12 = 0.9 * NoV_nearOne * R12;                        //���Ǿ���������ǿ�������� R10 
                R12 = lerp(tmp_col, R12, frxx_condi.x * factor_RoughOrZero);  //lerp�е�Rate�ھ��󲿷���������� 0 

                //����AO
                half ao = SAMPLE_TEXTURE2D(_AO, sampler_AO, suv);

                //���ֱ����µ�UV 
                half2 _suv = min(suv, cb0_6.xy);                        //�����ֱ����µ� UV 
                half2 half_scr_pixels = floor(screen_param.xy * 0.5);   //��ֱ����£���Ļ�ĳ����Ӧ���ظ��� 
                half2 one_over_half_pixels = 1.0 / half_scr_pixels;     //��ֱ����£�һ�����ض�Ӧ UV �Ŀ�� 
                //��ʽ��ȫ�ֱ��� UV ת������ ��ֱ��ʶ�Ӧ���� UV' -> ��UV'��ֵ��ԭ�㿿£ 
                //�ص�1: �����ֱ����µġ�ż�������� UV ֵ�����任������� 0.5*(1/ԭʼ�������ظ���) 
                //�ص�2: �����ֱ����µġ��桱������ UV ֵ�����任������� 1.5*(1/ԭʼ�������ظ���) 
                half2 half_cur_uv = floor(_suv * half_scr_pixels - 0.5) / half_scr_pixels + one_over_half_pixels * 0.5; 
                half2 uv_delta = _suv - half_cur_uv;    //UV - UV' -> (0.5��1.5)*(1/ԭʼ�������ظ���) 
                //��ֱ����£�(UV - UV')ռһ�����ض��ٰٷֱ�(ע:��ʱ�����������Ϊԭ��4������������Ϊԭ��2��) 
                half2 delta_half_pixels = uv_delta * half_scr_pixels;  //����������ռ����(0.25��0.75)�������ص㳤�� 

                //��β���GlobalNormal 
                half4 tmp_uv = half_cur_uv.xyxy + half4(one_over_half_pixels.x, 0, 0, one_over_half_pixels.y); 
                half4 g_norm_ld = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, half_cur_uv.xy); 
                half4 g_norm_rd = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.xy); 
                half4 g_norm_lu = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.zw); 
                half4 g_norm_ru = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.xw); 

                //����(ȫ�ַ��� & ���)�Ĳ������Ŷ�������ɫ R13 
                //�������������Ļ���������ġ���ż���ԣ���ϳ�һ��������Ե���Ļ�ռ����� 
                tmp2 = 1 - delta_half_pixels; 
                half4 scr_pat = half4(tmp2.x * tmp2.y, 
                    delta_half_pixels * tmp2, 
                    delta_half_pixels.x * delta_half_pixels.y); 
                //���4�β�������� 
                half4 depth4 = half4(g_norm_ld.w, g_norm_rd.w, g_norm_lu.w, g_norm_ru.w); //ע,�����wͨ����ŵ�λΪ����ľ��� 
                depth4 = 1.0 / (abs(depth4 - d) + 0.0001) * scr_pat;   //r13.xyzw 
                half g_depth = 1.0 / dot(depth4, half4(1.0, 1.0, 1.0, 1.0)); 
                //���±����Ǿ���任������ÿһ���ǲ���_GNorm��õĸ���4����ķ��ߣ����仯�����ÿһ��ͨ������Ȳ�ĵ���(������Ļ�ռ䷨�ߵ�һ�ּ��㷽ʽ) 
                half3 d_norm = g_norm_ld.xyz * depth4.xxx + g_norm_rd.xyz * depth4.yyy + g_norm_lu.xyz * depth4.zzz + g_norm_ru.xyz * depth4.www; 
                //1/0.0001667 = 6000 -> �Ʋ��Ǳ������ʱʹ�õļ���ֵ��20000�Ʋ�������ϵ�� 
                //������˵:��d>20000ʱscale��Ϊ0; ��14000<d<20000ʱscale��[0,1]���������Էֲ�; ��d<14000ʱscale��Ϊ1 
                half scale = saturate((20000 - d) * 0.00016666666);      //Scale, ���������->1��Զ��->0 
                d_norm = scale * (d_norm * g_depth - norm) + norm;       //���Ż���4������Ȳ��Ŷ����d_norm��������_GNorm����(������΢ģ����һ��?) 

                half4 test = half4(0, 0, 0, 0);  //JUST FOR SHOW-RESULTS 
                if (condi.x)  //���� #1 ~ #15 ����Ⱦͨ����˵���ܽ��� 
                {
                    //R12��R10��ɫ���Ǻڰ��������ʾ���ﱾ��Diffuse����ͼ����������R12��Dͼʩ����NoV��Fresnel����R10��ֱ�׵�Dͼ 
                    half3 R15 = matCondi.z ? (R12 - R12 * factor_RoughOrZero) : (R10 - R10 * factor_RoughOrZero); 
                    //RN ���� _GNorm ��ͼ������β����͵��Ӷ��ã��Ʋ���ĳ��С��Χ�����ģ�����N -> RandomNorm(��RN) 
                    half RN_Len = sqrt(dot(d_norm, d_norm));
                    half3 RN = d_norm / max(RN_Len, 0.00001);
                    
                    //����AO_from_RN 
                    half3 bias_N = (norm - RN) * RN_Len + RN; //��RN����Norm�ķ���ƫ��һ������ -> r17.xyz (��һ��r17)
                    half RNoN = dot(RN, norm); 
                    //TODO:���AO����㷽ʽ��ժ¼ 
                    half AO_from_RN = lerp(RNoN, 1, RN_Len);  //ͨ��ȫ�ַ��������õ�AO -> r11.w 

                    //����AO_final, ��ע:log2_n = 1.442695 * ln_n 
                    half computed_ao = saturate(40.008 /(exp(-0.01*(RN_Len * 10.0 - 5))+1) - 19.504); 
                    computed_ao = pow(computed_ao, 0.7); 
                    computed_ao = lerp(computed_ao, 1, 0);  //rate = 0 -> ����cb0[1].w 

                    uint AO_blend_Type = (0 == 1); //���� 1 ���� cb0[9].x 
                    half min_of_texao_and_ssao = min(df.w, ao); //min(Tex_AO, SSAO) 
                    half min_of_3_ao = min(computed_ao, min_of_texao_and_ssao); 
                    half mul_of_compao_and_minao = computed_ao * min_of_texao_and_ssao; 
                    half AO_final = AO_blend_Type ? min_of_3_ao : mul_of_compao_and_minao; 

                    uint4 matCondi2 = condi.xxxx == uint4(6, 2, 3, 7).xyzw; 
                    half3 frxxPow2 = frxx_condi.xyz * frxx_condi.xyz;  //�������������������ԭ��,����ֵ����ʱ������ 
                    half3 ao_diffuse_from_6 = half3(0, 0, 0); 
                    half3 ao_diffuse_common = half3(0, 0, 0); //�� #6 ����Ⱦͨ·Ҳ���ں������������µķ������� common ���� 
                    if (matCondi2.x)  // #6 ����Ⱦͨ· ʹ�����¹�ʽ���� ao_diffuse_from_6 
                    {
                        half4 neg_norm = half4(-norm.xyz, 1); 
                        half3 bias_neg_norm1 = mul(M_CB1_181, neg_norm); 
                        neg_norm = norm.yzzx * norm.xyzz; 
                        half3 bias_neg_norm2 = mul(M_CB1_184, neg_norm); 
                        //base_disturb * scale + bias 
                        ao_diffuse_from_6 = V_CB1_187 * (norm.x*norm.x-norm.y*norm.y) + (bias_neg_norm1+bias_neg_norm2);
                        ao_diffuse_from_6 = V_CB1_180 * max(ao_diffuse_from_6, half3(0, 0, 0));
                        //#6����Ⱦͨ·��disturb����ֵ�����ǻ���"�����Ŷ�" & "AO" & "���ʲ���"�Ļ�� 
                        ao_diffuse_from_6 = AO_final * ao_diffuse_from_6 * frxxPow2;
                    }

                    tmp1 = matCondi2.y | matCondi2.z; //#2 �� #3 ����Ⱦͨ�� 
                    R15 = tmp1 ? (frxxPow2 + R15) : R15;   //base_diffuse 

                    if (matCondi2.w) // #7 ����Ⱦͨ· �������еĻ��� Diffuse -> ���ǵ� R15.xyz  
                    {
                        half3 refractDirRaw = NoV * (-norm) + viewDir; 
                        half3 refractDir = normalize(refractDirRaw);  // ->r17.xyz (�ڶ���r17) 
                        half rough_7 = min(1.0, max(rifr.w, 0.003922)); 
                        half3 RoV = dot(refractDir, -viewDir); 
                        half3 RoN = dot(refractDir, norm); 
                        half ang_NoV = acos(NoV); 
                        half ang_RoN = acos(RoN); 

                        half cos_half_angle_VtoRneg = cos(abs(ang_NoV - ang_RoN) * 0.5); 

                        half3 V_hori = norm * (-RoN) + refractDir; //��ó������䷽��� "ˮƽ����" -> Vector_Horizontal 
                        half RefrawDotHori = dot(V_hori, refractDirRaw);
                        tmp1 = dot(V_hori, V_hori) * dot(refractDirRaw, refractDirRaw) + 0.0001;
                        tmp1 = RefrawDotHori* (1.0 / sqrt(tmp1)); //�൱���� |V_hori| * |RefracRaw|�ĵ���  
                        tmp1 = RefrawDotHori* tmp1; // AdotB/(|A|*|B|) -> cos<AB> -> cos(V_hori��Refract�ļн�) 
                        //���¿��Կ����Ƕ�cos�ȵ����ֲ�ͬrange����  
                        half2 cos_VhroiToRefract_adjust2 = half2(0.5, 17.0) * tmp1 + half2(0.5, -16.780001); 
                        cos_VhroiToRefract_adjust2.x = saturate(cos_VhroiToRefract_adjust2.x); 
                        tmp1 = sqrt(cos_VhroiToRefract_adjust2.x);

                        half rough_factor_1 = rough_7 * rough_7; 
                        half rough_factor_2 = rough_factor_1 * 2 + 0.2;
                        rough_factor_1 = rough_factor_1 + 0.2;

                        half sin_NV = sqrt(1 - NoV * NoV); 
                        half factor_HroiToRefract = 0.997551 * tmp1;
                        half factor_NoV = -0.069943 * NoV;
                        half twist = factor_HroiToRefract* sin_NV + factor_NoV;  //�ƺ��ǶԳ������ת 

                        rough_factor_1 = tmp1* rough_factor_1; 
                        tmp2 = half2(1.414214, 3.544908)* rough_factor_1; //��ֵ->(sqrt(2), 2*sqrt(��)) 

                        half R5Z = (NoV + RoN) - (-0.139886) * twist; //��Ϊ R5Z 
                        R5Z = -0.5 * R5Z * R5Z; 
                        R5Z = R5Z / (tmp2.x* tmp2.x); 
                        // exp(-0.5 * R5Z^2 / (2*cos_VhoR*(roughness^2+0.2)^2)) / (2sqrt(��)*sqrt(cos_VhoR)*(roughness^2 + 0.2)) 
                        // ���� R5Z = (NdotV + RoN)-(-0.139886)*(0.997*sqrt(cos_VhroiToRefract)*sin��-0.069943*cos��) 
                        R5Z = exp(R5Z) / tmp2.y; 
                        tmp1 = tmp1 * R5Z; // sqrt(cos_VhoR*0.5+0.5) * (��ʽ) -> ��Ϊ R5Z' 

                        tmp1 = tmp1 * (0.953479 * pow5(1 - sqrt(saturate(RoV * 0.5 + 0.5))) + 0.046521); 
                        half R1Y = 0.5 * R10.w * tmp1;   //��ΪR1Y TODO: ��������? 

                        half RoV_po = saturate(-RoV); 
                        half factor_RoV = 1 - RoV_po;   //�������ֱʱ��0�������߳�45�Ƚ�ʱ�����ֵ0.3���� 

                        tmp1 = exp((-0.5 * pow2(NoV - 0.14)) / pow2(rough_factor_2)) / (rough_factor_2 * 2.506628); //2.506=sqrt(2��) 

                        half R10W = 0.953479 * pow5(1 - 0.5 * cos_half_angle_VtoRneg) + 0.046521;  //��ɫǿ�� or AO ����ֵ 
                        R10W = pow2(1 - R10W) * R10W; 
                        //TODO: ȷ������ʹ��exp����exp2  bh 
                        half3 df_chan7 = exp(log(R10.xyz) * (0.8 / cos_half_angle_VtoRneg));  // #7 ��Ⱦͨ��ʹ�õ� df�������˵��� 
                        df_chan7 = df_chan7* tmp1* exp(cos_VhroiToRefract_adjust2.y)* R10W + factor_RoV * R1Y; 

                        tmp1 = lerp(min(0.25 * (1 + dot(refractDir, refractDir)), 1.0), (1 - abs(RoN)), 0.33) * factor_RoughOrZero * 0.318310;
                        
                        R10.xyz = sqrt(R10.xyz) * tmp1 + df_chan7; 
                        R10.xyz = min(-R10.xyz, half3(0, 0, 0)); //�������� -�� -> ��һ��������Ĩȥ���� 
                        R15.xyz = R10.xyz * half3(-_pi, -_pi, -_pi); //�� * (������нǺʹֲڶ�ϵ���Ȼ����������df) -> һ�ֻ��������� 
                    }

                    uint is8 = condi.x == uint(8);
                    R10.xyz = frxxPow2.xyz * frxx_condi.w + R15.xyz; 
                    R10.xyz = is8 ? R10.xyz : R15.xyz; 

                    //�����߼���֮ǰ���� #6 ��Ⱦͨ��ʱ��ͬ 
                    half4 biasN = half4(bias_N.xyz, 1.0); 
                    half3 bias_biasN = mul(M_CB1_181, biasN); 
                    half4 mixN = biasN.yzzx * biasN.xyzz; 
                    half3 bias_mixN = mul(M_CB1_184, mixN);
                    //base_disturb * scale + bias 
                    ao_diffuse_common = V_CB1_187 * (biasN.x * biasN.x - biasN.y * biasN.y) + (bias_biasN + bias_mixN);
                    ao_diffuse_common = V_CB1_180 * max(ao_diffuse_common, half3(0, 0, 0));

                    //#6����Ⱦͨ·��disturb����ֵ�����ǻ���"�����Ŷ�" & "AO" & "���ʲ���"�Ļ�� 
                    ao_diffuse_common = AO_from_RN * AO_final * ao_diffuse_common + V_CB0_1 * (1 - AO_final);

                    R10.xyz = R10.xyz * ao_diffuse_common + ao_diffuse_from_6;  //���Ǹ���ɫ, �Ʋ�Ϊ������ Diffuse 

                    half intense = dot(half3(0.3, 0.59, 0.11), R10.xyz);
                    half check = 1.0 == 0;      //����false -> �൱�ڹر���alphaͨ�� -> cb1[200].z == 0 ?
                    //��ǿ����flag��and -> Ҫ��ǿ�ȴ���0�ҿ�����flag 
                    //��ǰ��Ļ����ϻ�Ҫ���� #9��#5����Ⱦͨ�� -> check ��Ϊ true(1) 
                    output.w = half((uint(check) & uint(intense)) & is9or5);    //�˴����غ�Ϊ 0 

                    test.x = AO_final;
                }
                else //���� #0 �� ��Ⱦͨ��  
                {
                    R10 = half4(0, 0, 0, 0);
                    output.w = 0;
                }

                uint2 is0or7 = condi.xxx != uint2(0, 7).xy;
                if ((is0or7.x & is0or7.y) != 0)  //�Ȳ��� #0�� Ҳ���� #7 ����Ⱦͨ�� 
                {
                    //GI_Spec ���㲿���ڴ� 
                    half3 Specular_Final = half3(0, 0, 0);
                    half3 gi_spec_base = half3(0, 0, 0);

                    //���������Ƿ���9or5����Ⱦͨ����ѡ��R11(�������ɫ*����Mask.y) �� �������ɫ��Ϊ�µ� df_base(�����������ɫ) 
                    df_base.xyz = is9or5 ? R11.xyz : df_base.xyz;  
                    tmp1 = (frxx_condi.x * df_base.w + 1) * 0.08; //df_base.w����rough��NoV�йص�ֵ������[-1,0]���䣻frxx_condi.x��Ϊ������������ָ������ 
                    R11.xyz = factor_RoughOrZero * (R12.xyz - tmp1.xxx) + tmp1.xxx; //R11��ɫ�ǻ���R12��ɫ����΢�� 
                    df_base.xyz = matCondi.z ? R11.xyz : df_base.xyz;  //����� #4 ��Ⱦͨ�� ���� df_base Ϊ ������������R11��ɫ 
                    half3 VR = (NoV + NoV) * norm + viewDir;  //View_Reflection -> VR:���߷��䷽�� 
                    half roughSquare = rifr.w* rifr.w;
                    //��ʽ��Ӧ����ͼ�� -> �ɽ���Ϊ���ڳ���Ķ������ߣ���y����1��ͬʱ��x������1�ཻ 
                    half rate = (roughSquare + sqrt(1 - roughSquare)) * (1 - roughSquare);  //Լ 0.63 -> ĳ��rateϵ�� 
                    half3 VR_lift = lerp(norm, VR, rate);  //���Ҷ���Ϊ����̧�ӷ���(ע:û�й�һ��) �����巴��������̧�Ƕ���rough���� -> ����֮Խ�ֲڣ���������Խ�ӽ����߳��� 

                    //ʹ����ĻUV���� T12 -> ��������������ˮ��,�����ۻ����������˴��� -> ���ƹ��� spec -> �Ӻ����߼���(xyz����)�Ʋ��ǶԸ߹�������Եĸ��Ӳ����� 
                    half4 spec_add_raw = SAMPLE_TEXTURE2D(_Spec, sampler_Spec, suv);
                    half spec_mask = 1 - spec_add_raw.w;  //���������õ����ڻ�������ͼ�ĸ߹��ؽ������У���Ϊǿ������ 
                    //���¿�֪ frxx_condi.x ��0��1 -> ��0ʱʹ�ò���T12����Ĳ�������ֵ(w������ȡ��)����1ʱxyz�߹⸽����ɫ������Ϊ0(��wͨ������Ϊ1) 
                    half4 spec_add = matCondi.z ? (frxx_condi.x * half4(-spec_add_raw.xyz, spec_add_raw.w) + half4(spec_add_raw.xyz, spec_mask)) : half4(spec_add_raw.xyz, spec_mask);

                    //����������Ǳ�T12.wͨ����������'AO����'��Ƶ����ϵ�� 
                    half mixed_ao = df.w * ao + NoV_sat; 
                    half AOwthRoughNoise = df.w * ao + exp(log(mixed_ao) * roughSquare);
                    AOwthRoughNoise = saturate(AOwthRoughNoise - 1);  //-> r0.y -> ֻ��ȡ����1�Ĳ��֣��ⲿ�ֿ��Կ�����AO������Rough��ĸ�Ƶ���� 
                    half masked_AOwthRoughNoise = spec_add.w * AOwthRoughNoise; //�Ʋ�Ϊspec������� 

                    //�����߼����ڼ������� -> �������ڻ�ȡIBL��ͼ 
                    uint2 screenPixelXY = uint2(IN.vertex.xy);
                    uint logOfDepth = uint(max(log(d * 1 + 1) + 1, 0));  //�����ϵ�����ȵĶ��� + 1 -> �޳���̫���ӽ��ľ��� 
                    uint curbed_logOfDepth = min(logOfDepth, uint(0));   //�ƺ�ֻ�ܷ��� 0? -> ע:�������漰�������־�����cb3 
                    screenPixelXY = screenPixelXY >> 1;                  //�൱�ڰ���Ļ�������� 
                    //((����������� * 1 + ����Ļ��������.v) * 1 + ����Ļ��������.u + 1) * 2 
                    uint map_Idx_1 = ((curbed_logOfDepth * 1 + screenPixelXY.y) * 1 + screenPixelXY.x + 1) << 1; 
                    uint map_Idx_2 = map_Idx_1 + 1; 
                    //����������ʹ��map_Idx����ȡ�����Ĳ��� -> �ⲻ��Ҫ 
                    //ld_indexable(buffer)(uint,uint,uint,uint) ret_from_t3_buffer_1, map_Idx_1, t3.x 
                    //ld_indexable(buffer)(uint,uint,uint,uint) ret_from_t3_buffer_2, map_Idx_2, t3.x 
                    uint ret_from_t3_buffer_1 = 1;  //r0.w -> ���ڿ���ѭ�����㲻ͬIBL��������ͼ�Ĵ��� -> ��Ϊ[0,1,..7] 
                    uint ret_from_t3_buffer_2 = 1;  //r0.z -> ���ڸ�����λIBL��ͼ����ͼ�����е�λ�� -> ��Ϊ[0,1,..7] 

                    uint is6 = condi.x == uint(6);  //�Ƿ��� #6 ��Ⱦͨ�� 
                    half norm_shift_intensity = 0;  //�ò�����gi_spec_base�������߼���֧����Ҫ����Ŀ�� 
                    if (true)  //������֧��cb[0].x ���ƣ����ǿ��Խ��� 
                    {
                        half RN_raw_Len = sqrt(dot(d_norm, d_norm));
                        norm_shift_intensity = RN_raw_Len;
                        //���·�֧���ڼ���ĳ���Ŷ�ǿ�� -> norm_shift_intensity? -> TODO ȷ��ѧ�綨�巶�� 
                        //���������ʹ�õ���: |Rn_raw|, roughness, asin(dot(Rn,'��̧�ӷ�')/|Rn|) -> �Ʋ�Ϊ���鹫ʽ 
                        if (true) //cb1[189].x ��ʮ�����ƽ����� 0x00000001 -> true 
                        {
                            if (is6) //���� #6 ��Ⱦͨ�� 
                            {
                                //����׼���м������ 
                                half rough_chan6 = max(rifr.w, 0.1);
                                //half pi_RN_raw_Len = _pi * (RN_raw_Len * 1);
                                half RNoVRLift = dot(d_norm, VR_lift);
                                RN_raw_Len = max(RN_raw_Len, 0.001);

                                half asin_input = RNoVRLift / RN_raw_Len;
                                tmp2.x = asin(asin_input) - abs(_pi * rough_chan6 - _pi * RN_raw_Len);
                                tmp2.y = (_pi * rough_chan6 + _pi * RN_raw_Len) - abs(_pi * rough_chan6 - _pi * RN_raw_Len);
                                tmp1 = saturate(tmp2.x / tmp2.y);
                                tmp1 = ((1.0 - tmp1) * (-2.0) + 3.0) * pow2(1.0 - tmp1);

                                norm_shift_intensity = saturate((_pi* RN_raw_Len - 0.1) * 5.0)* tmp1; //���� norm_shift_intensity 
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

                    half lod_lv = 6 - (1.0 - 1.2 * log(rifr.w));  //��ֲڶ��йصĲ���LOD�ȼ���ħ������6����cb0 
                    half threshold = masked_AOwthRoughNoise;
                    half3 ibl_spec_output = half3(0, 0, 0);  //��������forѭ������Ҫ��� 
                    //ע��: ret_from_t3_buffer_1��ʹ�á���Ļ���ء��롮�����������ϳ����� -> �ٴ� T3 buffer ��ȡ�õ�ӳ��ֵ 
                    //��ӳ�䷵��ֵ��ȡֵ��ΧҪô�� 0, Ҫô 1 
                    //�Ʋ������ݾ���Զ�����Ƿ�����Ļ���ģ��ж��Ƿ�Ҫ������ǰ���صĻ�������ͼ�����߼� 
                    //���� masked_AOwthRoughNoise �����Ǻ�����װmask�Ͷ���AO�Լ�Rough�������"��Ƶϸ��" 
                    //����Ϊѭ���ж�֮һҲ����ֹһ�������ؽ���IBL����ѭ�� 
                    [unroll] for (uint i = 0; i < ret_from_t3_buffer_1 && threshold >= 0.001; i++)
                    {
                        //�жϵ�ǰ�����������IBL̽�룬�����ǰ���ص��ܱ�ĳ��IBLӰ�죬������ڲ� if ��ִ֧���߼� 
                        uint tb4_idx = i + ret_from_t3_buffer_2;
                        //����������ʹ�� tb4_idx ����ȡ�����Ĳ��� -> t4��t3һ����Ҳ����ӳ��� 
                        //ld_indexable(buffer)(short,short,short,short) out, tb4_idx, t4.x  -> ʹ��tb4_idx=[0-8]�������ض���"6" 
                        //����ʹ���Ӽ����"��ȷֵ" -> out = 12 ����� 
                        half3 v_PixelToProbe = posWS - cb4_12.xyz; 
                        half d_PixelToProbe_square = dot(v_PixelToProbe, v_PixelToProbe); 
                        half d_PixelToProbe = sqrt(d_PixelToProbe_square); 
                        if (d_PixelToProbe < cb4_12.w)  //���Ե�ǰ�����������������Ƿ���Ŀ��Probe�����÷�Χ�� 
                        {
                            half d_rate = saturate(d_PixelToProbe / cb4_12.w); //����ռ��  
                            half VRLoP2P = dot(VR_lift, v_PixelToProbe); 
                            //��ʽ��ʽΪ: Scale * VR_lift + v_PixelToProbe - [200,0,0] 
                            half3 shifted_p2p_dir = (sqrt(pow2(VRLoP2P) - (d_PixelToProbe_square - pow2(cb4_12.w))) - VRLoP2P) * VR_lift + v_PixelToProbe - half3(200, 0, 0);
                            tmp1 = max(2.5 * d_rate - 1.5, 0);  //��� (���ص�̽��ľ��� / ̽��Ӱ��뾶R) < 0.6 -> ��ʽһ�ɷ��� 0 
                            half rate_factor = 1.0 - (3.0 - 2.0 * tmp1) * pow2(tmp1); //������������ 
                            //shifted_p2p_dir �ǲ���cubemap�ķ���ָ�� 
                            //IBL_cubemap_array��index�� cb4[12 + 341].y ��ã���ǰֵΪ "13"  
                            //ע�⣬����û����Cubemap_array��ʽ����ԭʼ��Դ�������²�����uv������û�е���ά(array����) 
                            half4 ibl_raw = SAMPLE_TEXTURECUBE_LOD(_IBL, sampler_IBL, shifted_p2p_dir, lod_lv).rgba;
                            //���� ibl_spec_output 
                            ibl_spec_output = (cb4_353.x * ibl_raw.rgb) * rate_factor * threshold * norm_shift_intensity + ibl_spec_output; 
                            //���� threshold -> masked_AOwthRoughNoise 
                            threshold = threshold * (1.0 - rate_factor * ibl_raw.a); 
                        }
                    }

                    //���·�֧���ڲ�����պ���ɫ 
                    if (true) 
                    {
                        half sky_lod = 1.8154297 - (1.0 - 1.2 * log(rifr.w)) - 1;
                        half3 sky_raw = SAMPLE_TEXTURECUBE_LOD(_Sky, sampler_Sky, VR_lift, sky_lod).rgb;
                        gi_spec_base = sky_raw * V_CB1_180 * norm_shift_intensity + gi_spec_base;
                    }

                    half spec_AOwthRoughNoise = threshold;  //�����Ҹ�threshold���������������ɻ� 
                    //��ʽ�������� Lc -> �� GI_Spec_Light_IN -> ���߰�ѧ��з�: prefilter specular -> ԭʼ���ݲ���Ԥ���ֵĻ�������ͼIBL 
                    half3 prefilter_Specular = (ibl_spec_output + gi_spec_base * spec_AOwthRoughNoise) * 1.0 + spec_add;

                    if (matCondi.z) //�� #4 ����Ⱦͨ����˵��spec��Ҫ�ܶ���⴦�� 
                    {
                        //��ɵ�һ�黷����߹� 
                        half2 lut_uv_1 = half2(NoV_sat, rifr.w);//���ǵ�һ��lut_uv��rifr.w->��Ӧ�ֲڶ�rough2 
                        half2 lut_raw_1 = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, lut_uv_1);
                        half shifted_lut_bias = saturate(df_base.y * 50.0) * lut_raw_1.y * (1.0 - frxx_condi.x);
                        half gi_spec_brdf_1 = df_base.xyz * lut_raw_1.x + shifted_lut_bias; //��һ�� GI_Spec �е�Ԥ���� brdf���ֵ  
                        half3 gi_spec_1 = prefilter_Specular * gi_spec_brdf_1; //��������Ԥ���ּ����ع����� GI_Spec 

                        //��ɵڶ��黷����߹�(����) 
                        half2 lut_uv_2 = half2(NoV_sat, frxx_condi.y); //���ǵڶ���lut_uv��frxx_condi.y->��Ӧ�ֲڶ�rough3 
                        half2 lut_raw_2 = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, lut_uv_2);
                        //�ڶ��� GI_Spec �еĹ��շ������ֵ��ǰ���frxx_condi.x�������Ϊ��ĳЩ���ص����֣�����Ԥ���ֵ�Lc 
                        half gi_spec_brdf_2 = frxx_condi.x * (0.4 * lut_raw_2.x + lut_raw_2.y); 
                        //gi_spec_2 �Ʋ��ǶԲ��ִ��ڵڶ��߹Ⲩ��Ĳ��ʽ��ж��λ�����߹���Ⱦ�Ľ�� (�ڼ���Ҫ�۳�һ��'�ع�'�����еĶ��ⲿ��) 
                        half3 gi_spec_2 = gi_spec_1 * (1 - gi_spec_brdf_2) + spec_add_raw.xyz * gi_spec_brdf_2; 

                        //spec_mask -> ���Ը߹���ͼalphaͨ����1���Ľ�� (������ǿ��) 
                        //gi_spec_brdf_2 -> �����ǻ����ӽǺͷ��߼�����Ĺ���ǿ�ȷֲ�(Ҳ��ǿ��) 
                        //AOwthRoughNoise -> ���ǹ���ǿ������ 
                        half spec_second_intensity = spec_mask * gi_spec_brdf_2 * AOwthRoughNoise;  //�ò��������Ӱ��ڶ��߹��ǿ�� 
                        half RN_shift_intensity = 0;                //������Ŷ�ǿ�� 
                        half3 gi_spec_second_base = half3(0, 0, 0);    //����ĵڶ�������ɫ 
                        //����ķ�֧����������� #4 ��ͨ��ר�е� gi_spec_second_base(�ȵڶ�������ɫ) 
                        //�Լ� RN_shift_intensity(����RN���Ŷ�ǿ��) 
                        if (true)  //������֧��cb[0].x ���ƣ����ǿ��Խ��� 
                        {
                            half RN_raw_Len = sqrt(dot(d_norm, d_norm));
                            RN_shift_intensity = RN_raw_Len;
                            if (true) //cb1[189].x ��ʮ�����ƽ����� 0x00000001 -> true 
                            {
                                //��frxx(T11)������yͨ����ȡrough��ֵ,��û����ֵ�Ĳ���(ľ�Ƽ�,é���ݶ��Ȳ���)ȷ����ֵ������0.1 
                                half rough_chan4 = max(frxx_condi.y, 0.1); //�������Ļ�����������roughΪ #4����Ⱦͨ��ר�� 
                                RN_raw_Len = max(RN_raw_Len, 0.001);  

                                half asin_input = dot(d_norm, VR) / RN_raw_Len; 

                                tmp2.x = asin(asin_input) - abs(_pi * rough_chan4 - _pi * RN_raw_Len);
                                tmp2.y = (_pi * rough_chan4 + _pi * RN_raw_Len) - abs(_pi * rough_chan4 - _pi * RN_raw_Len);
                                tmp1 = saturate(tmp2.x / tmp2.y);
                                tmp1 = ((1.0 - tmp1) * (-2.0) + 3.0) * pow2(1.0 - tmp1);

                                RN_shift_intensity = saturate((_pi * RN_raw_Len - 0.1) * 5.0) * tmp1; //���� RN_shift_intensity
                            }
                            
                            half rn_shift_rate = 0; //������ cb0_1_w �ĵ��ڱ��ʣ���Ϊ0
                            RN_shift_intensity = lerp(RN_shift_intensity, 1.0, rn_shift_rate); 
                            gi_spec_second_base = V_CB0_1.xyz * (1.0 - RN_shift_intensity); //�ڶ��߹Ⲩ�����ͨ����ɫǿ�� 
                        }
                        else
                        {
                            gi_spec_second_base = half3(0, 0, 0);
                            RN_shift_intensity = 1.0; 
                        }

                        //����ͨ��ʹ��view_reflection�ڶ��β���IBL -> ���� �ڶ��߹Ⲩ���ǿ�� �Լ� �ڶ��߹���ɫ 
                        half lod_lv_spc2 = 6 - (1.0 - 1.2 * log(frxx_condi.y));  //��ڶ�����ֲڶ�(frxx.y)�йصĲ���LOD�ȼ���ħ������6����cb0 
                        half threshold_2 = spec_second_intensity; //�ڶ��߹Ⲩ���ǿ�� 
                        half3 ibl_spec2_output = half3(0, 0, 0);  //�ڶ��߹���ɫ 

                        [unroll] for (uint i = 0; i < ret_from_t3_buffer_1 && threshold_2 >= 0.001; i++)
                        {
                            //�жϵ�ǰ�����������IBL̽�룬�����ǰ���ص��ܱ�ĳ��IBLӰ�죬������ڲ� if ��ִ֧���߼� 
                            uint tb4_idx = i + ret_from_t3_buffer_2;
                            //����������ʹ�� tb4_idx ����ȡ�����Ĳ��� -> t4��t3һ����Ҳ����ӳ��� 
                            //ld_indexable(buffer)(short,short,short,short) out, tb4_idx, t4.x  -> ʹ��tb4_idx=[0-8]�������ض���"6" 
                            //����ʹ���Ӽ����"��ȷֵ" -> out = 12 ����� 
                            half3 v_PixelToProbe = posWS - cb4_12.xyz;  //r7.xyz
                            half d_PixelToProbe_square = dot(v_PixelToProbe, v_PixelToProbe); //���ص�̽������ƽ�� 
                            half d_PixelToProbe = sqrt(d_PixelToProbe_square);      //���ص�̽��ľ��� 
                            if (d_PixelToProbe < cb4_12.w)  //���Ե�ǰ�����������������Ƿ���Ŀ��Probe�����÷�Χ�� 
                            {
                                half d_rate = saturate(d_PixelToProbe / cb4_12.w); //����ռ��  
                                half VRoP2P = dot(VR, v_PixelToProbe);  //ע:��һ����specʱʹ�õ��� VR_Lift 
                                //��ʽ��ʽΪ: Scale * VR + v_PixelToProbe - [200,0,0] 
                                half3 shifted_p2p_dir_2 = (sqrt(pow2(VRoP2P) - (d_PixelToProbe_square - pow2(cb4_12.w))) - VRoP2P) * VR + v_PixelToProbe - half3(200, 0, 0);
                                
                                tmp1 = max(2.5 * d_rate - 1.5, 0);  //��� (���ص�̽��ľ��� / ̽��Ӱ��뾶R) < 0.6 -> ��ʽһ�ɷ��� 0 
                                half rate_factor = 1.0 - (3.0 - 2.0 * tmp1) * pow2(tmp1); //������������ 
                                //shifted_p2p_dir_2 �ǲ���cubemap�ķ���ָ�� 
                                //IBL_cubemap_array��index�� cb4[12 + 341].y ��ã���ǰֵΪ "13" 
                                //ע�⣬����û����Cubemap_array��ʽ����ԭʼ��Դ�������²�����uv������û�е���ά(array����) 
                                half4 ibl_raw_2 = SAMPLE_TEXTURECUBE_LOD(_IBL, sampler_IBL, shifted_p2p_dir_2, lod_lv_spc2).rgba; 
                                //���� ibl_spec2_output -> cb4_353.x=1 
                                ibl_spec2_output = (cb4_353.x * ibl_raw_2.rgb) * rate_factor * threshold_2 * RN_shift_intensity + ibl_spec2_output; 
                                //���� threshold_2 -> spec_second_intensity 
                                threshold_2 = threshold_2 * (1.0 - rate_factor * ibl_raw_2.a); 
                            }
                        }

                        //�ڶ��β�����պ�  
                        if (true)  //���ǽ��� 
                        {
                            half sky_lod_2 = 1.8154297 - (1.0 - 1.2 * log(frxx_condi.y)) - 1;
                            half3 sky_raw_2 = SAMPLE_TEXTURECUBE_LOD(_Sky, sampler_Sky, VR, sky_lod_2).rgb;
                            gi_spec_second_base = sky_raw_2 * V_CB1_180 * RN_shift_intensity + gi_spec_second_base; //Ϊgi_spec׷����պеĹ��� 
                        }
                        
                        half spec_second_intensity_final = threshold_2; //���������£������Ϳ 
                        half3 ibl_scale_3chan = half3(1, 1, 1);  //������� cb1_156_xyz �е����� -> ���� ibl_spec2 
                        half3 scale_second_spec = half3(1, 1, 1);          //������� cb1_134_yyy �е����� -> ���� �ڶ��߹���ܺ� 
                        
                        //ibl_spec2_output * ibl_scale_3chan -> ��Ҫ���ԡ�IBL��ͼ��ɫ���롮�ڶ��߹�ǿ�ȡ��Ļ�� -> ������ GI_Spec_second_Mirror 
                        //gi_spec_second_base * spec_second_intensity_final -> ��Ҫ���ԡ�������ɫ���롮�ڶ��߹�ǿ�ȡ��Ļ�� -> ������ GI_Spec_second_Diffuse 
                        //gi_spec_2 -> �Ǿ��������ĵ�һ�߹���ɫ 
                        Specular_Final = (ibl_spec2_output * ibl_scale_3chan + gi_spec_second_base * spec_second_intensity_final)* scale_second_spec + gi_spec_2; 
                    }
                    else  //���� #4��Ҳ���� #0 �� #7 ������������Ⱦͨ�� 
                    {
                        half2 lut_uv_1 = half2(NoV_sat, rifr.w);  //���ǵ�һ��lut_uv��rifr.w->��Ӧ�ֲڶ�rough2 
                        half2 lut_raw_1 = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, lut_uv_1); 
                        half shifted_lut_bias = saturate(df_base.y * 50.0) * lut_raw_1.y; 
                        half gi_spec_brdf_1 = df_base.xyz * lut_raw_1.x + shifted_lut_bias;  //��һ�� GI_Spec �е�Ԥ���� brdf���ֵ  
                        half3 gi_spec_1 = prefilter_Specular * gi_spec_brdf_1; 
                        Specular_Final = gi_spec_1;
                    }

                    Specular_Final = min(Specular_Final, half3(0, 0, 0));
                    output.xyz = Specular_Final;
                }
                else
                {
                    //o0.xyz = R10��ɫ 
                    //����û�и߹�Ĳ��� -> ֱ�ӷ���R10��ɫ -> R10��ɫ������Ϊ�� GI_Diffuse_Final 
                    output.xyz = R10.xyz; 
                }
                //TODO test
                return half4((output).xyz * 1, 1);
            }
            ENDHLSL
        }
    }
}
