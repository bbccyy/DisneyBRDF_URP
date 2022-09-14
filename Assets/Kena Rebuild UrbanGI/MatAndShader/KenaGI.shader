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

            static float4 screen_param = float4(1708, 960, 1.0/1708, 1.0/960);  //���ǽ�֡ʱ����Ļ������Ϣ 

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

            static float3 camPosWS = float3(-58890.16015625, 27509.392578125, -6150.4560546875);

            static float2 cb0_6 = float2(0.998231828212738, 0.998937487602233);

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
                half4 posWS = mul(M_Inv_VP, hclip);

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
                    half RN = dot(d_norm, d_norm); 
                    half RN_Len = sqrt(RN); 
                    RN = d_norm / max(RN_Len, 0.00001); 
                    
                    //����AO_from_RN 
                    half bias_N = (norm - RN) * RN_Len + RN; //��RN����Norm�ķ���ƫ��һ������ -> r17.xyz 
                    half RNoN = dot(RN, norm); 
                    //TODO:���AO����㷽ʽ��ժ¼ 
                    half AO_from_RN = RN_Len * (1 - RNoN) + RNoN;  //ͨ��ȫ�ַ��������õ�AO -> r11.w 

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
                    half3 ao_diffuse = half3(0, 0, 0); //�� #6 ����Ⱦͨ·ʹ��0Ĭ��ֵ 
                    if (matCondi2.x)  // #6 ����Ⱦͨ· ʹ�����¹�ʽ���� ao_diffuse 
                    {
                        half4 neg_norm = half4(-norm.xyz, 1); 
                        half3 bias_neg_norm1 = mul(M_CB1_181, neg_norm); 
                        neg_norm = norm.yzzx * norm.xyzz; 
                        half3 bias_neg_norm2 = mul(M_CB1_184, neg_norm); 
                        //base_disturb * scale + bias 
                        ao_diffuse = V_CB1_187 * (norm.x*norm.x-norm.y*norm.y) + (bias_neg_norm1+bias_neg_norm2);
                        ao_diffuse = V_CB1_180 * max(ao_diffuse, half3(0, 0, 0));
                        //#6����Ⱦͨ·��disturb����ֵ�����ǻ���"�����Ŷ�" & "AO" & "���ʲ���"�Ļ�� 
                        ao_diffuse = AO_final * ao_diffuse * frxxPow2;
                    }

                    tmp1 = matCondi2.y | matCondi2.z; //#2 �� #3 ����Ⱦͨ�� 
                    R15 = tmp1 ? (frxxPow2 + R15) : R15;   //base_diffuse 

                    if (matCondi2.w) // #7 ����Ⱦͨ· �������еĻ��� Diffuse -> ���ǵ� R15.xyz  
                    {
                        half3 refractDirRaw = NoV * (-norm) + viewDir; 
                        half3 refractDir = normalize(refractDirRaw); 
                        half rough_7 = min(1.0, max(rifr.w, 0.003922)); 
                        half3 RoV = dot(refractDir, -viewDir); 
                        half3 RoN = dot(refractDir, norm); 
                        half ang_NoV = acos(abs(NoV)); 
                        half ang_RoN = acos(abs(RoN)); 

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

                        tmp1 = tmp1 * (0.953479 * pow5(1 - sqrt(satruate(RoV * 0.5 + 0.5))) + 0.046521); 
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
                        R15.xyz = R10.xyz * half3(-3.141593, -3.141593, -3.141593); //�� * (������нǺʹֲڶ�ϵ���Ȼ����������df) -> һ�ֻ��������� 
                    }

                    uint is8 = condi.x == uint(8);






                    test.x = AO_final;
                }
                else //���� #0 �� ��Ⱦͨ��  
                {

                }



                return half4((test).xxx, 1 );
            }
            ENDHLSL
        }
    }
}
