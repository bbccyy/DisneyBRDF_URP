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

                //�������ֵ
                half4 output = half4(0, 0, 0, 0);

                //������ʱ����(��ż����м���) 
                half tmp1 = 0; 
                half2 tmp2 = half2(0, 0);
                half3 tmp3 = half3(0, 0, 0);
                half3 tmp_col = half3(0, 0, 0);

                //Start here 
                half2 suv = IN.vertex.xy * screen_param.zw;     //screen uv 
                half2 coord = (IN.vertex.xy * screen_param.zw - 0.5) * IN.vertex.w * 2.0;  //[-1, +1] 
                //test = IN.vertex.wwww / 2; //ʹ��Renderdoc��֡ץȡ�����ɫ֪ -> IN.vertex.w == 1.0 -> ��������ͶӰ��HClip.w�Ķ��� 

                //Sample Depth
                half d = SAMPLE_TEXTURE2D(_Depth, sampler_Depth, suv); 
                d = 1 / (d * 0.1);  // ����֮ǰ͸���������¼�� HClip.z -> ��ֵ�ϵ����ӿռ�z�� 
                
                //get h-clip space 
                half2 hclipXY = coord * d;  //��һ�����ڽ�DNC�ռ��ƽ�棬չ������βü�ǰ��͸��ͶӰ�ռ��� 
                float4 hclip = float4(hclipXY.xy, d, 1);  //�ϸ�˵�ⲻ��hclip�ı��� -> ���һάӦ����d������1 
                                                          //ʹ��1��Ϊ���һά���� -> ��float4(coord.xy, d, 1)��Ϊ��hclip�е�һ���㣬�������任 

                //use matrix_Inv_VP to rebuild posWS 
                float4 posWS = mul(M_Inv_VP, hclip);  //ע��UE4�£�posWS�ĵ�λ�� "����" 

                //cameraToPixelDir (ȡ����viewDir: ���ӵ㴥��ָ�������) 
                half3 cameraToPixelDir = normalize(posWS.xyz - camPosWS); 
                half3 viewDir = -cameraToPixelDir;
                /*
                //������δ������ڽ�����֤ posWS��׼ȷ�� -> ���posWS�������ص����������
                //��ô������������굽posWS�������ĵ�ľ��벻������ɽ���Զ�ķֲ�Ч�� 
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
                uint2 condi = flag & uint2(15, 16);//condi.x����������Ⱦ�߼�(��ɫ���ַḻ������ܼ������ֵ�һ��ɿ�ͬɫ), y������ɫ���;  
                /* ��condi�ļ����Ч���´���: 
                uint2 condi = uint2(flag & 0x0000000F, flag & 0x00000010); */ 

                //Sample _F_R_X_X
                float4 frxx = SAMPLE_TEXTURE2D(_F_R_X_X, sampler_F_R_X_X, suv);
                //����frxx_condi�����ݸ���:�·�����ɫ(�����ߺͻ���),��Ҷ(��ɫ����������������),ͷ������(��) 
                float4 frxx_condi = condi.y ? float4(0, 0, 0, 0) : frxx.xyzw; //��xͨ���������Fresnel��� 

                //������Ⱦͨ��mask, matCondi.xyz �ֱ��Ӧ 9, 5 �� 4����Ⱦͨ�� -> �ṩ�������΢С��� 
                uint3 matCondi = condi.xxx == uint3(9, 5, 4).xyz; 

                //Sample Diffuse 
                half4 df = SAMPLE_TEXTURE2D(_Diffuse, sampler_Diffuse, suv); 
                //test = df;   

                //spec_power_mask 
                half spec_base_intensity = rifr.y * 0.08; 
                half factor_RoughOrZero = matCondi.x ? 0 : rifr.x;  //#9��ͨ��ʱ�ֲڶ�Ϊ0�� �������ʹ����ͼ�����rifr.xֵ(�ֲڶ�:rough1) 
                //�ӡ�spec_base_intensity���� diffuse���������ص���������ɫ���в�ֵ 
                //��һ����roughnessԽ��spec_power_maskԽ�󣬷�֮spec_power_mask�ӽ���0 
                half4 spec_power_mask = half4( lerp(spec_base_intensity.xxx, df.xyz, factor_RoughOrZero).xyz, 0 ); //���Կ��� spec_power_mask �ƺ��ǲ�ͬ����Specǿ�Ȼ���ֵ
                //test.xyz = spec_power_mask; 
                
                //����R10��ɫ -> diffuse_base_col 
                uint is9or5 = matCondi.x | matCondi.y; 
                uint flag_r7z = 0;  // 0 < cb1[155].x ?  -> ע: �޸����¼�������flag���Ἣ��Ӱ��diffuse���� 
                uint flag_r7w = 1;  // 0 < cb1[200].z ? 
                uint and_r7z_w = flag_r7z & flag_r7w; 
                uint flag_ne_r7w = 0; // 0 != cb1[155].x ? 
                half3 R8 = flag_ne_r7w ? half3(1, 1, 1) : df.xyz; 
                //R11 -> ���� �� û�о��� ���̴���� spec_power_mask 
                half4 R11 = and_r7z_w ? half4(spec_power_mask.xyz, rifr.y) * chessMask.y : half4(spec_power_mask.xyz, rifr.y);
                half4 R10 = half4(0, 0, 0, 0); 
                R10.xyz = and_r7z_w ? chessMask.xxx : R8.xyz; 
                R10.w = R11.w; 
                R10 = is9or5 ? R10 : half4(df.xyz, rifr.y);  //Ŀǰͨ��������������R10==df 

                //�����Ż���� NoV ����� spec_power_mask.w �� -> ����Lambert(NoL)��Ҳ����Phong(NoH)��Ӧ�ú�Fresnel��������ǿ����� 
                half NoV = dot(norm, viewDir);
                half NoV_sat = saturate(NoV);
                half a = (NoV_sat * 0.5 + 0.5) * NoV_sat - 1.0; //��������[-1, 0]�����ϳɶ������߷ֲ���N��V��ֱ��-1 
                half b = saturate(1.25 - 1.25 * rifr.w); //������.rough2�ɷ��ȣ��ҵ�����ƫ�ƺ����� 
                spec_power_mask.w = a * b; //�������ͼ�Ա� NoV ��˵��������[-1, 0]���������Ե��ֵ����ֵ���м�ֵ�ӽ�0 
                //�������ֵת���� [0, 1] ���䣬�����ֲڶȴ������������������NoV 
                half NoV_nearOne = spec_power_mask.w + 1.0;  //��ֵ���б�Ե���м�����Ч��
                //NoV_nearOne ����� NoV_sat ɫ������С������������� 
                
                //����R12��ɫ -> �����ӽǵĴ�С�����ֳ��ɰ������Ĺ���(��Ե���м���) 
                //���⣬col - (col^2 - col)*t -> ����ģʽ����ɫ������Ч�ڶ�ԭʼ��ɫ���� "����������" 
                half3 R12 = R10.xyz * 1.111111; 
                half3 NoV_soft = 0.85 * (NoV_sat - 1) * (1 - (R12 - 0.78 * (R12 * R12 - R12))) + 1; 
                R12 = R12 * NoV_soft;    //������NoV�Ļ�����ǿ�� -> ���õ� R10 ��ɫ��(��Եѹ�����м��������) 

                //NoV_nearOne�����������(1 - frxx_condi.x * fresnel)�������� -> ��Եѹ��(�м��������)
                //R12��ɫ������Ϊ�ǻ���R10(���������ɫ)����Եѹ����Ľ��������ʽtmp_col�ȸ��Ӱ���,����ɲο������test��� 
                //ע��R12 = R10 * (һ��NoVѹ��:NoV_nearOne) * (�ڶ���NoVѹ��:NoV_soft) 
                R12 = 0.9 * NoV_nearOne * R12;

                //����Fresnel����ֵ��1�Ļ�����������tmp_col��ʹ֮��������R12������Ч�������������һЩ 
                float p5 = pow5(1 - NoV_sat); 
                float fresnel = lerp(p5, 1, 0.04);                    //��΢����(����)fresnel 
                //Fresnel�����ɫ������֪(��Ե���м䰵)��frxx_condi.x����������������֣�ֻ������+��Ҷ�����������ֵ 
                //frxx_condi.x * fresnel -> �Է�������������֣�����ֻ������+��Ҷ��FresnelЧ��(��ֵ����0) 
                //(1 - frxx_condi.x * fresnel) -> ȡ�����������ε�������ֵΪ 1������Ͳ�Ҷ�ȱ�Ϊ��ɫ(��Ե���м���) -> ��������NoV 
                //R10��ɫ�Ʋ�ΪGI_Diffuse_Col -> ���������������� -> ��������Ͳ�Ҷ�ı�Ե������ 
                tmp_col = R10.xyz * (1 - frxx_condi.x * fresnel);     //�����ǽ� Fresnel �� -> ���õ� R10 ��ɫ�� 
                //test.xyz = tmp_col - R12; 
                
                //factor_RoughOrZero��Ҫ������ͼrifr.xͨ����ֻ�������é���ݶ���ֵ 
                //frxx_condi.x * factor_RoughOrZero���Ӻ���������ֵ������ 
                //ͨ��lerp����������������ʽ�м������R12��ɫ(��Ը��Ӱ���һЩ)������������tmp_col��ɫ(�����һЩ) 
                R12 = lerp(tmp_col, R12, frxx_condi.x * factor_RoughOrZero); 
                
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
                half4 g_norm_ld = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.zy); //���� 
                half4 g_norm_rd = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.xy); //���� 
                half4 g_norm_lu = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.zw); //���� 
                half4 g_norm_ru = SAMPLE_TEXTURE2D(_GNorm, sampler_GNorm, tmp_uv.xw); //���� 

                //����(ȫ�ַ��� & ���)�Ĳ������Ŷ�������ɫ R13 
                //�������������Ļ���������ġ���ż���ԣ���ϳ�����״��Ļ�ռ����� 
                //�ӹ����Ͽ���scr_pat.xyzw �ֱ��Ӧ���������£��ң��Ϻ�����4����λ������(���)��˥��ֵ(���߽�Ȩ��)  
                tmp2 = (half2(1, 1) - delta_half_pixels).yx; 
                half4 scr_pat = half4(tmp2.x * tmp2.y, 
                    (delta_half_pixels * tmp2).xy, 
                    delta_half_pixels.x * delta_half_pixels.y); 
                //���4�β�������� 
                half4 depth4 = half4(g_norm_ld.w, g_norm_rd.w, g_norm_lu.w, g_norm_ru.w); //ע,�����wͨ����ŵ�λΪ����ľ��� 
                depth4 = 1.0 / (abs(depth4 - d) + 0.0001) * scr_pat;   //[���4����λ�����ĵ�����ĵ��� (����Խ����ֵԽС)] * [4����λ�Ĳ�ͬ˥������] 
                half g_depth_factor = 1.0 / dot(depth4, half4(1.0, 1.0, 1.0, 1.0));  //���depth4��4��ͨ����ȡ���� -> ��Ϊ��ƽ���ĳ��� 
                //�������ƾ�������Ĺ��̣���������ȡ��Ļ�ռ䷨�ߵ�һ�ּ��㷽ʽ 
                //�����������: depth4.xyzw�������Ե�ǰ���ص�Ϊ������Χ4�������һ��"�ݶ�"��ͨ���������Ӧ����Ĳ���������˺��ۼӣ��൱���ǽ��ݶ�ֵ��С����Ȩ����4�ܷ��߼�Ȩ���  
                //���ս�� d_norm Ӧ������˷������ƣ��־��нϺ������ԣ����ܹ����ֱ�Ե���ı仯 
                //d_norm -> depth-based normal:������Ⱥ�4�����ֵ������ռ䷨���� 
                //d_norm -> ��û��һ������ģ����������������ƽ̹�̶�: ��Խƽ̹��ģ��Խ�� -> ��Ҫ��������ʽ�� 1/abs(depth4 - d) ���� -> Խƽ̹��ֵԽ�� 
                half3 d_norm = g_norm_ld.xyz * depth4.xxx + g_norm_rd.xyz * depth4.yyy + g_norm_lu.xyz * depth4.zzz + g_norm_ru.xyz * depth4.www; 

                //1/0.0001667 = 6000 -> �Ʋ��Ǳ������ʱʹ�õļ���ֵ��20000�Ʋ�������ϵ�� 
                //������˵:��d>20000ʱscale��Ϊ0; ��14000<d<20000ʱscale��[0,1]���������Էֲ�; ��d<14000ʱscale��Ϊ1 
                half scale = saturate((20000 - d) * 0.00016666666);      //Scale, ���������->1��Զ��->0 
                d_norm = lerp(norm, d_norm * g_depth_factor, scale);     //���Ż���4������Ȳ��Ŷ����d_norm��������_GNorm����(������΢ģ����һ��?) 
                //test.xyz = d_norm;
                //if (condi.x)  //���� #1 ~ #15 ����Ⱦͨ����˵���ܽ��� 
                if (true)       //�����޸�ԭʼ���壬�����������ؽ��뵱ǰ��֧ -> ����GI_Diffuse_Col 
                {
                    //�����Ƿ��� #4��ͨ�� -> ������ͬ diffuse (R12�����R10������������Ը��Ӱ���һЩ) 
                    //GI_Diffuse - GI_Diffuse * factor_RoughOrZero -> �����������é�ݶ������� 
                    half3 R15 = matCondi.z ? (R12.xyz - R12.xyz * factor_RoughOrZero) : (R10.xyz - R10.xyz * factor_RoughOrZero);

                    //RN �ǹ�һ����� d_norm -> RebuiltedNorm (��RN) 
                    half RN_Len = sqrt(dot(d_norm, d_norm));  //ǰ���Լ��ἰ��RN_Len��������������ƽ̹�̶� 
                    half3 RN = d_norm / max(RN_Len, 0.00001); 
                    
                    //������ʹ�õı��淨������(���� #7����Ⱦͨ�������д���ֵ)
                    half3 bias_N = lerp(RN, norm, RN_Len);  //����ƽ̹����ʹ��norm����Ե�Լ����ͱ���ʹ��RN 

                    //����AO_from_RN 
                    half RNoN = dot(RN, norm); //������ȵķ��� RN �������� norm ֮������ƶ� 
                    half AO_from_RN = lerp(RNoN, 1, RN_Len);  //�Ʋ�ΪAO -> ��ȫƽ̹ʱ����1����᫶��ʹ�����RNoN -> ��ʱ���ֵҲ���С  

                    //���� computed_ao 
                    //��ע1:log2_n = 1.442695 * ln_n 
                    //��ע2:�Ʋ��Ǿ��鹫ʽ(����) -> ������� computed_ao �ɼ���������Ե�Ͱ����ļ��Ч���ܺ� 
                    half computed_ao = saturate(40.008 /(exp(-0.01*(RN_Len * 10.0 - 5))+1) - 19.504); 
                    computed_ao = pow(computed_ao, 0.7);    //0.7 -> cb0[8].w 
                    computed_ao = lerp(computed_ao, 1, 0);  //  0 -> cb0[1].w 

                    //���¼���AO_final -> ʹ���� ���������ao(df.w)����Ļ�ռ�ao(ao)���Լ���������computed_ao���ж��ػ��� 
                    uint AO_blend_Type = (0 == 1);                  //���� 1 ���� cb0[9].x 
                    half min_of_texao_and_ssao = min(df.w, ao);     //min(Tex_AO, SSAO) 
                    half min_of_3_ao = min(computed_ao, min_of_texao_and_ssao); 
                    half mul_of_compuao_and_min_tx_ss_ao = computed_ao * min_of_texao_and_ssao; 
                    half AO_final = AO_blend_Type ? min_of_3_ao : mul_of_compuao_and_min_tx_ss_ao; 

                    uint4 matCondi2 = condi.xxxx == uint4(6, 2, 3, 7).xyzw; 
                    half3 frxxPow2 = frxx_condi.xyz * frxx_condi.xyz;  //�ñ��������Ʋ�����Ϊ��ɫ���� -> ֻ������+��Ҷ��Ч(����������) 
                    half3 ao_scale_from_6 = half3(0, 0, 0);
                    half3 ao_scale = half3(0, 0, 0);  //�� #6 ����Ⱦͨ·Ҳ���ں������������µķ������� common ���� 
                    //if (matCondi2.x)  // #6 ����Ⱦͨ· ʹ�����¹�ʽ���� virtual_light_from_6 
                    if(false) //TODO DELETE 
                    {
                        half4 neg_norm = half4(-norm.xyz, 1); 
                        half3 bias_neg_norm1 = mul(M_CB1_181, neg_norm);  //������ƻҶ�ͼ����Ҫ�����˳��Ϻͳ��·���ķ��� 
                        half3 rd_norm = norm.yzzx * norm.xyzz; 
                        half3 bias_neg_norm2 = mul(M_CB1_184, rd_norm);   //ֻ��ĳ���ض���������Ӧ������ط���ֵ������0 
                        //base_disturb * scale + bias 
                        half3 virtual_light_from_6 = V_CB1_187 * (norm.x*norm.x-norm.y*norm.y) + (bias_neg_norm1+bias_neg_norm2);
                        virtual_light_from_6 = V_CB1_180 * max(virtual_light_from_6, half3(0, 0, 0));

                        //#6����Ⱦͨ·��Ӧ�� AO -> ʹ���� frxxPow2 ��Ϊ���֣�ֻ������(���в�Ҷ��)��Ч 
                        ao_scale_from_6 = AO_final * virtual_light_from_6 * frxxPow2;
                    }

                    uint is2or3 = matCondi2.y | matCondi2.z;  //#2 �� #3 ����Ⱦͨ��
                    is2or3 = 0;         //TODO: �����ֶ�������  
                    R15 = is2or3 ? (frxxPow2 + R15) : R15;    //TODO: frxxPow2 + R15 -> T11.xyz �ľ��庬�� 
                    //test.xyz = R15;

                    //if (matCondi2.w) // #7 ����Ⱦͨ· �������еĻ��� Diffuse -> ���ǵ� R15.xyz 
                    if ( false ) //TODO DELETE 
                    {
                        //ʹ�� M_Inv_VP ��ǰ3x3����(ȥ������任����) �Դ���NDC�ռ��е�����(����z��̶�Ϊ1)���任
                        //���Ľ��������Ϊ��: �����������Ļ���ص�ĳ���(Direction)ͨ��������任��ת��������ռ���
                        //TODO -> �Ż�ʱ�ɾ��� 
                        half3 camToPixelDirRaw2 = V_CB1_48.xyz * coord.xxx;
                        camToPixelDirRaw2       = V_CB1_49.xyz * coord.yyy      + camToPixelDirRaw2;
                        camToPixelDirRaw2       = V_CB1_50.xyz * half3(1, 1, 1) + camToPixelDirRaw2;
                        half3 camToPxlDir2 = normalize(camToPixelDirRaw2); 
                        half3 viewDir2 = -camToPxlDir2;
                        //test.xyz = abs(viewDir - viewDir2);  //��֤�������������� viewDir �� ֮ǰͨ�����ص�������������������������� viewDir ��һ�µ� 

                        //����֤: ���湫ʽ�����ӷ��������ʹ�� camToPxlDir2 ��� viewDir2 -> ���������ӽ��������䷽�� 
                        //���������������㽫�ῴ����������"����" 
                        half3 viewTangentRaw = dot(viewDir2, norm) * (-norm) + camToPxlDir2;  //viewTangentRaw(vt) 
                        half3 viewTangent = normalize(viewTangentRaw); 
                        bias_N = viewTangent;    //ע: �÷�֧��Ҫ��д��bias_N��ȡֵ��bias_N����������������� 

                        half rough_7 = min(1.0, max(rifr.w, 0.003922)); 

                        half ToV = dot(viewTangent, viewDir);   //ToV -> ����ʱ�õ����ֵ1;����ʱ����Сֵ0; 45��б��ʱ��0.5
                        half ToN = dot(viewTangent, norm);      //ToN -> ��Ϊ0����ΪTangent��Nornmal���ഹֱ 
                        //test = ToN.xxxx * 1000; //��Ϊ��֤�����Կ�����δ���(��ȷ�����ǽ��뵱ǰ��֧) 
                        half ang_NoV = acos(NoV); //����֪��NoV=1����V��Nͬ��(����) -> ang_NoV = acos(1) = 0���ȸ���ʱƫ������֮����ʱƫ��(����pi/2) 
                        //test = ang_NoV.xxxx / (_pi); //��֤�� 
                        half ang_ToN = acos(ToN); //Ӧ�ú�Ϊ pi/2  -> TODO: �Ż�ʱ�ɾ��� 
                        //test = ang_ToN.xxxx / (_pi/2) * 0.5; //��Ϊ��֤��ʹ��renderdoc��ȡ��������������ؼ���֪�������� 0.5 -> ����acos(0) = pi/2 �Ľ�� 

                        half cos_half_angle_TtoV = cos(abs(ang_NoV - ang_ToN) * 0.5); //����ʱΪcos(��/4)=sqrt(2)/2������ʱΪcos(0)=1 
                        //test = cos_half_angle_TtoV.xxxx; //ʹ��renderoc��֡�鿴���ӽǶ����� -> ��Сֵ��0.75���� -> ����Ԥ����sqrt(2)/2 

                        half3 dir_A = norm * (-ToN) + viewTangent; //����ToN��Ϊ0������ֵ��Ϊ viewTangent��������dir_A��ʾ��ʾ���� 
                        //test.xyz = abs(dir_A - viewTangent); 

                        half AoTraw = dot(dir_A, viewTangentRaw);
                        tmp1 = sqrt(dot(dir_A, dir_A) * dot(viewTangentRaw, viewTangentRaw) + 0.0001); //�൱���� |dir_A| * |viewTangentRaw|
                        half cos_AtoT = AoTraw * (1.0 / tmp1); //�൱���� dir_A �� viewTangentRaw�нǵ�����ֵ -> cos(AtoT) = cos(0) = 1  

                        //���¿��Կ����Ƕ�cosֵ�� Scale �� Transform 
                        half2 cos_AtoT_ST = half2(0.5, 17.0) * cos_AtoT + half2(0.5, -16.780001); 
                        cos_AtoT_ST.x = saturate(cos_AtoT_ST.x); 
                        half sqrt_cosAtoTst = sqrt(cos_AtoT_ST.x); //��ֵĿǰ����Ϊ 1  

                        rough_7 = rough_7 * rough_7; 
                        half rough_factor_1 = rough_7 + 0.2; 
                        half rough_factor_2 = rough_7 * 2 + 0.2; 

                        half sin_NaV = sqrt(1 - NoV * NoV); 
                        half sin_NaV_ST = (0.997551 * sqrt_cosAtoTst) * sin_NaV + (-0.069943 * NoV);  //��cos_half_angle_TtoV���ֵ�����һ�£�����ʱ��ֵƫС������ʱ��ֵƫ�� 

                        tmp2 = (sqrt_cosAtoTst * rough_factor_1) * half2(1.414214, 3.544908);     //�������� -> (sqrt(2), 2*sqrt(��)) 
                        tmp1 = sqrt_cosAtoTst * exp(-0.5 * pow2((NoV + ToN) + 0.139886 * sin_NaV_ST) / pow2(tmp2.x)) / tmp2.y; //sqrt_cosAtoTst�ƺ����Ժ�tmp2.y�Ĺ���Ԫ�ػ���Լȥ 
                        //��ʽpow5�ᵼ�·���ֵ�ǳ��ӽ�0�����ʹ��pow2���ܱ������ӽǶȵĸ����� 
                        //dark_fresnel_intensity �������һ����ֵ����ӽ�0�����������ӷ������������ǿ��ͼ 
                        half dark_fresnel_intensity = tmp1 * (0.953479 * pow5(1 - sqrt(saturate(ToV * 0.5 + 0.5))) + 0.046521);
                        
                        //R10.w��Ҫ��������rifr.yͨ�������������GI_Intensity����
                        half gi_fresnel_dark_intensity = R10.w * dark_fresnel_intensity;

                        half ToV_sat = saturate(-ToV);   //��˼: �����T��V��ˣ�����ֵ���������������㽫���������壻���������ǵ��V����ǰ�еĴ������ 
                        half factor_ToV = 1 - ToV_sat;   //һ��������ֵ���� 1

                        half bright_fresnel_intensity = exp((-0.5 * pow2((NoV + ToN) - 0.14)) / pow2(rough_factor_2)) / (rough_factor_2 * 2.506628); //2.506=sqrt(2��) 
                        
                        tmp1 = 0.953479 * pow5(1 - 0.5 * cos_half_angle_TtoV) + 0.046521; 
                        half lambert_intensity = pow2(1 - tmp1) * tmp1; //ע�����ǿ��������ǰ����������ֲ�ͬ�����ڸ���ʱǿ��ֵ������� 

                        half3 df_chan7 = pow(R10.xyz, 0.8/cos_half_angle_TtoV); //��R10��������ɫ���������ӽ��²��䣬�������������  
                        df_chan7 = df_chan7 * bright_fresnel_intensity * exp(cos_AtoT_ST.y) * lambert_intensity + factor_ToV * 0.5 * gi_fresnel_dark_intensity; 
                        //test.xyz = df_chan7; //���ӽڵ��� -> �ϰ��ĳ��� + ���������� + ���ͻ����Ƥ���ʹ�����ɫ 

                        //����������Ҫ�������� rifr.x -> ���� + é���ݶ� 
                        half mask_RoughOrZero = lerp(min(0.25*(1 + dot(viewTangent, viewTangent)), 1.0), (1 - abs(ToN)), 0.33) * factor_RoughOrZero * 0.318310;

                        //sqrt(R10.xyz) -> ����diffuse -> ֮����Ӧ��������ȡ������ݶ�(˳��ѹ������) -> ���׷��df_chan7 
                        R10.xyz = sqrt(R10.xyz) * mask_RoughOrZero + df_chan7; 
                        R10.xyz = min(-R10.xyz, half3(0, 0, 0)); //�������� -�� -> ��һ��������Ĩȥ���� 
                        tmp3 = R10.xyz * half3(-_pi, -_pi, -_pi); //�� * ���������� -> ����Ħ�һ����Ϊ����ɫ�㸽���������ǿ�Ȼ��ֺ��ǿ��ֵ  
                        R15.xyz = tmp3;
                        //test.xyz = R15;
                    }
                    
                    uint is8 = condi.x == uint(8); 
                    is8 = 0; //TODO: �ֶ������� 
                    R10.xyz = frxxPow2.xyz * frxx_condi.w + R15.xyz; 
                    R10.xyz = is8 ? R10.xyz : R15.xyz; 
                    
                    //�����߼���֮ǰ���� #6 ��Ⱦͨ��ʱ��ͬ 
                    //�Ʋ��Ǽ��� GI_Virtual_Directional_Light ������ǿ�ȣ���Ϊ�����������ڱ��淨�ߵ�ĳ����ά�� 
                    half4 biasN = half4(bias_N.xyz, 1.0);   //���Ե���Ϊbias_N.xzy �� bias_N.xyz�Ա� 
                    half3 bias_biasN = mul(M_CB1_181, biasN); 
                    half4 mixN = biasN.yzzx * biasN.xyzz; 
                    half3 bias_mixN = mul(M_CB1_184, mixN);  //ֵ��С��0���鿴ʱʹ�� -bias_mixN  
                    //base_disturb * scale + bias 
                    half3 virtual_light = V_CB1_187 * (biasN.x * biasN.x - biasN.y * biasN.y) + (bias_biasN + bias_mixN);
                    virtual_light = V_CB1_180 * max(virtual_light, half3(0, 0, 0));   //����V_CB1_180���ź󣬷���ֵ���ܻ����1.0 
                    //test.xyz = virtual_light * 0.5;
                    //#6����Ⱦͨ·��disturb����ֵ�����ǻ���"�����Ŷ�" & "AO" & "���ʲ���"�Ļ�� 
                    ao_scale = AO_from_RN * AO_final * virtual_light + V_CB0_1 * (1 - AO_final); 
                    
                    R10.xyz = R10.xyz * ao_scale + ao_scale_from_6;  //���Ǹ���ɫ, �Ʋ�Ϊ������ Diffuse 
                    //test.xyz = R10.xyz;

                    half intense = dot(half3(0.3, 0.59, 0.11), R10.xyz); 
                    half check = 1.0 == 0;      //����false -> �൱�ڹر���alphaͨ�� -> cb1[200].z == 0 ? 
                    //output.alpha ��Ҫ�����ڴ�R10(gi_diffuse)��ɫ��ȡ�Ĺ�ǿ��ֵ -> intense 
                    //����֮�⻹��Ҫ�ֶ����� check����λ �Լ����� #9��#5����Ⱦͨ������Ȼalpha���ֵΪ0 
                    output.w = half((uint(check) & uint(intense)) & is9or5);    //�˴����غ�Ϊ 0 
                }
                else //���� #0 �� ��Ⱦͨ��  
                {
                    R10 = half4(0, 0, 0, 0); 
                    output.w = 0; 
                }

                //����Ϊֹ����� GI_Diffuse 
                //test.xyz = R10; 

                uint2 is0or7 = condi.xxx != uint2(0, 7).xy; 
                //if ((is0or7.x & is0or7.y) != 0)  //�Ȳ��� #0�� Ҳ���� #7 ����Ⱦͨ�� 
                if (true)  //TODO DELETE 
                {
                    //GI_Spec ���㲿���ڴ� 
                    half3 Specular_Final = half3(0, 0, 0);
                    half3 gi_spec_base = half3(0, 0, 0);

                    //���������Ƿ���9or5����Ⱦͨ����ѡ��R11=spec_power_mask(?*����Mask.y) �� spec_power_mask 
                    spec_power_mask.xyz = is9or5 ? R11.xyz : spec_power_mask.xyz;
                    
                    //����tmp1��ֵ�ձ���0.5���ң�����ı�Ե����������ֵ����0.4���� 
                    tmp1 = (frxx_condi.x * spec_power_mask.w + 1) * 0.08; //spec_power_mask.w����rough��NoV�йص�ֵ������[-1,0]���䣻frxx_condi.x��Ϊ������������ָ������ 
                    R11.xyz = lerp(tmp1, R12, factor_RoughOrZero); //R11��ɫ�ǻ��� R12(�������԰��������ӽ�df) ����lerp  
                    spec_power_mask.xyz = matCondi.z ? R11.xyz : spec_power_mask.xyz;  //����� #4 ��Ⱦͨ�� ���� spec_power_mask Ϊ ������������R11��ɫ 
                    
                    half3 VR = (NoV + NoV) * norm + cameraToPixelDir;  //View_Reflection -> VR:���߷��䷽�� 
                    
                    half roughSquare = rifr.w* rifr.w;
                    //��ʽ��Ӧ����ͼ�� -> �ɽ���Ϊ���ڳ���Ķ������ߣ���y����1��ͬʱ��x������1�ཻ 
                    half rate = (roughSquare + sqrt(1 - roughSquare)) * (1 - roughSquare);  //Լ 0.63 -> ĳ��rateϵ�� 
                    half3 VR_lift = lerp(norm, VR, rate);  //���Ҷ���Ϊ����̧�ӷ���(ע:û�й�һ��) �����巴��������̧�Ƕ���rough���� -> ����֮Խ�ֲڣ���������Խ�ӽ����߳��� 
                    
                    //ʹ����ĻUV���� T12 -> ��������������ˮ��,�����ۻ����������˴��� -> ���ƹ��� spec 
                    //T12.xyz�����Ʋ��ǶԸ߹�������Եĸ��Ӳ�����
                    //T12.w�����Ǹ߹����ǿ�� 
                    half4 spec_add_raw = SAMPLE_TEXTURE2D(_Spec, sampler_Spec, suv);
                    half spec_mask = 1 - spec_add_raw.w;  //���������õ�������ڶ��߹Ⲩ��ǿ�ȵ��ؽ������� -> ǿ������ -> �˴���Ϊ0 
                    //���¿�֪ frxx_condi.x ��0��1 -> ��0ʱʹ�ò���T12����Ĳ�������ֵ(w����ȡ1�Ļ�����)����1ʱxyz�߹⸽����ɫ������Ϊ0(��wͨ������Ϊ1) 
                    half4 spec_add = matCondi.z ? (frxx_condi.x * half4(-spec_add_raw.xyz, spec_add_raw.w) + half4(spec_add_raw.xyz, spec_mask)) : half4(spec_add_raw.xyz, spec_mask);

                    //����������Ǳ�T12.wͨ����������'AO����'��Ƶ����ϵ�� 
                    half mixed_ao = df.w * ao + NoV_sat; //TexAO * Computered_AO(SSAO.r) + saturate(NdotV) -> mixed_AO 
                    half AOwthRoughNoise = df.w * ao + pow(mixed_ao, roughSquare); 
                    AOwthRoughNoise = saturate(AOwthRoughNoise - 1);  //-> r0.y -> ֻ��ȡ����1�Ĳ��֣��ⲿ�ֿ��Կ�����AO������Rough��ĸ�Ƶ���� 
                    //half spec_scaler = spec_add.w;    //spec_add.w�Ǹ߹�ǿ�ȿ��Ʒ� 
                    half spec_scaler = 0.5;             //TODO: ������㣬ʹ��0.5���spec_add.w 
                    half spec_first_intensity = spec_scaler * AOwthRoughNoise; 

                    //�����߼����ڼ������� -> �������ڻ�ȡIBL��ͼ 
                    uint2 screenPixelXY = uint2(IN.vertex.xy); 
                    uint logOfDepth = uint(max(log(d * 1 + 1) * 1, 0));  //�޳���ȶ���С��0�Ĳ��� -> �ų�̫���ӽ��ľ��� 
                    //test.xyz = logOfDepth/3;  //����������˵����logOfDepth����ֵ����2 
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
                    half smoothness = 0;            //�ò�����gi_spec_base�������߼���֧����Ҫ����Ŀ�� 
                    if (true)  //������֧��cb[0].x ���ƣ����ǿ��Խ��� 
                    {
                        half RN_raw_Len = sqrt(dot(d_norm, d_norm));
                        smoothness = RN_raw_Len;  //�ؽ���norm�Ƕ��norm�ϳ�ֵ���������ϳɵ�norms����ϴ󣬻��ɢ���������RN������ģ����С 
                        //test = smoothness;
                        //���������ʹ�õ���: |Rn_raw|, roughness, asin(dot(Rn,'��̧�ӷ�')/|Rn|) -> �Ʋ�Ϊ���鹫ʽ 
                        if (true) //cb1[189].x ��ʮ�����ƽ����� 0x00000001 -> true 
                        {
                            //if (is6) //���� #6 ��Ⱦͨ�� 
                            if(false)  //TODO DELETE 
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

                                smoothness = saturate((_pi* RN_raw_Len - 0.1) * 5.0)* tmp1; //���� smoothness 
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
                    half lod_lv = 6 - (1.0 - 1.2 * log(rifr.w));  //��ֲڶ��йصĲ���LOD�ȼ���ħ������6����cb0 
                    half threshold = spec_first_intensity;
                    half3 ibl_spec_output = half3(0, 0, 0);  //��������forѭ������Ҫ��� 
                    //ע��: ret_from_t3_buffer_1��ʹ�á���Ļ���ء��롮�����������ϳ����� -> �ٴ� T3 buffer ��ȡ�õ�ӳ��ֵ 
                    //��ӳ�䷵��ֵ��ȡֵ��ΧҪô�� 0, Ҫô 1 
                    //�Ʋ������ݾ���Զ�����Ƿ�����Ļ���ģ��ж��Ƿ�Ҫ������ǰ���صĻ�������ͼ�����߼� 
                    //���� spec_first_intensity �����Ƕ���AO�Լ�Rough����ó�  
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
                        //half probe_range = cb4_12.w;
                        half probe_range = 10000;
                        if (d_PixelToProbe < probe_range)  //���Ե�ǰ�����������������Ƿ���Ŀ��Probe�����÷�Χ�� 
                        //if (true)  //���Ե�ǰ�����������������Ƿ���Ŀ��Probe�����÷�Χ�� 
                        {
                            half d_rate = saturate(d_PixelToProbe / probe_range); //����ռ�� 
                            half VRLoP2P = dot(VR_lift, v_PixelToProbe); 
                            //��ʽ��ʽΪ: Scale * VR_lift + v_PixelToProbe - [200,0,0] 
                            half3 shifted_p2p_dir = (sqrt(pow2(VRLoP2P) - (d_PixelToProbe_square - pow2(probe_range))) - VRLoP2P) * VR_lift + v_PixelToProbe - half3(200, 0, 0);
                            tmp1 = max(2.5 * d_rate - 1.5, 0);  //��� (���ص�̽��ľ��� / ̽��Ӱ��뾶R) < 0.6 -> ��ʽһ�ɷ��� 0 
                            half rate_factor = 1.0 - (3.0 - 2.0 * tmp1) * pow2(tmp1); //������������ 
                            //shifted_p2p_dir �ǲ���cubemap�ķ���ָ�� 
                            //IBL_cubemap_array��index�� cb4[12 + 341].y ��ã���ǰֵΪ "13"  
                            //ע�⣬����û����Cubemap_array��ʽ����ԭʼ��Դ�������²�����uv������û�е���ά(array����) 
                            half4 ibl_raw = SAMPLE_TEXTURECUBE_LOD(_IBL, sampler_IBL, shifted_p2p_dir, lod_lv).rgba;
                            //���� ibl_spec_output 
                            ibl_spec_output = (cb4_353.x * ibl_raw.rgb) * rate_factor * threshold * smoothness + ibl_spec_output;
                            //���� threshold -> spec_first_intensity 
                            threshold = threshold * (1.0 - rate_factor * ibl_raw.a); 
                            //test.xyz = ibl_spec_output;  
                        }
                        
                    }

                    //���·�֧���ڲ�����պ���ɫ 
                    if (true) 
                    {
                        half sky_lod = 1.8154297 - (1.0 - 1.2 * log(rifr.w)) - 1;
                        half3 sky_raw = SAMPLE_TEXTURECUBE_LOD(_Sky, sampler_Sky, VR_lift, sky_lod).rgb;
                        gi_spec_base = sky_raw * V_CB1_180 * smoothness + gi_spec_base;
                        //test.xyz = gi_spec_base;
                    }

                    spec_first_intensity = threshold;  //�����Ҹ�threshold���������������ɻ� 
                    //��ʽ�������� Lc -> �� GI_Spec_Light_IN -> ���߰�ѧ��з�: prefilter specular -> ԭʼ���ݲ���Ԥ���ֵĻ�������ͼIBL 
                    half3 prefilter_Specular = (ibl_spec_output + gi_spec_base * spec_first_intensity) * 1.0 + spec_add;
                    
                    //if (matCondi.z) //�� #4 ����Ⱦͨ����˵��spec��Ҫ�ܶ���⴦�� 
                    if(true)  //TODO DELETE 
                    {
                        //��ɵ�һ�黷����߹� 
                        half2 lut_uv_1 = half2(NoV_sat, rifr.w);//���ǵ�һ��lut_uv��rifr.w->��Ӧ�ֲڶ�rough2 
                        half2 lut_raw_1 = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, lut_uv_1); 
                        half shifted_lut_bias = saturate(spec_power_mask.y * 50.0) * lut_raw_1.y * (1.0 - frxx_condi.x);
                        half3 gi_spec_brdf_1 = spec_power_mask.xyz * lut_raw_1.x + shifted_lut_bias; //��һ�� GI_Spec �е�Ԥ���� brdf���ֵ 
                        half3 gi_spec_1 = prefilter_Specular * gi_spec_brdf_1; //��������Ԥ���ּ����ع����� GI_Spec 
                        //test.xyz = gi_spec_1 * 1;
                        
                        //��ɵڶ��黷����߹�(����) 
                        half2 lut_uv_2 = half2(NoV_sat, frxx_condi.y); //���ǵڶ���lut_uv��frxx_condi.y->��Ӧ�ֲڶ�rough3 
                        half2 lut_raw_2 = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, lut_uv_2);
                        //�ڶ��� GI_Spec �еĹ��շ������ֵ��ǰ���frxx_condi.x�������Ϊ��ĳЩ���ص����֣�����Ԥ���ֵ�Lc 
                        half gi_spec_brdf_2 = frxx_condi.x * (0.04 * lut_raw_2.x + lut_raw_2.y); 
                        //gi_spec_2 �Ʋ��ǶԲ��ִ��ڵڶ��߹Ⲩ��Ĳ��ʽ��ж��λ�����߹���Ⱦ�Ľ�� (�ڼ���Ҫ�۳�һ��'�ع�'�����еĶ��ⲿ��) 
                        half3 gi_spec_2 = gi_spec_1 * (1 - gi_spec_brdf_2) + spec_add_raw.xyz * gi_spec_brdf_2; 
                        
                        //spec_mask -> ���Ը߹���ͼalphaͨ����1���Ľ�� (������ǿ��) 
                        //gi_spec_brdf_2 -> �����ǻ����ӽǺͷ��߼�����Ĺ���ǿ�ȷֲ�(Ҳ��ǿ��) 
                        //AOwthRoughNoise -> ���ǹ���ǿ������ 
                        half spec_second_intensity = spec_mask * gi_spec_brdf_2 * AOwthRoughNoise;  //�ò��������Ӱ��ڶ��߹��ǿ�� 
                        half smoothness_2 = 0;                //������Ŷ�ǿ�� 
                        half3 gi_spec_second_base = half3(0, 0, 0);    //����ĵڶ�������ɫ 
                        //����ķ�֧����������� #4 ��ͨ��ר�е� gi_spec_second_base(�ȵڶ�������ɫ) 
                        //�Լ� smoothness_2 (����RN�Ŷ���ǿ��) 
                        if (true)  //������֧��cb[0].x ���ƣ����ǿ��Խ��� 
                        {
                            half RN_raw_Len = sqrt(dot(d_norm, d_norm));
                            smoothness_2 = RN_raw_Len;
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

                                smoothness_2 = saturate((_pi * RN_raw_Len - 0.1) * 5.0) * tmp1; //���� smoothness_2
                            }
                            
                            half rn_shift_rate = 0; //������ cb0_1_w �ĵ��ڱ��ʣ���Ϊ0
                            smoothness_2 = lerp(smoothness_2, 1.0, rn_shift_rate);
                            gi_spec_second_base = V_CB0_1.xyz * (1.0 - smoothness_2); //�ڶ��߹Ⲩ�����ͨ����ɫǿ�� 
                        }
                        else
                        {
                            gi_spec_second_base = half3(0, 0, 0);
                            smoothness_2 = 1.0;
                        }

                        //����ͨ��ʹ��view_reflection�ڶ��β���IBL -> ���� �ڶ��߹Ⲩ���ǿ�� �Լ� �ڶ��߹���ɫ 
                        half lod_lv_spc2 = 6 - (1.0 - 1.2 * log(frxx_condi.y));  //��ڶ�����ֲڶ�(frxx.y)�йصĲ���LOD�ȼ���ħ������6����cb0 
                        half threshold_2 = spec_second_intensity; //�ڶ��߹Ⲩ���ǿ�� -> ��spec_maskӰ�죬��ֻ��Ϊ0 
                        half3 ibl_spec2_output = half3(0, 0, 0);  //�ڶ��߹���ɫ 

                        [unroll] for (uint i = 0; i < ret_from_t3_buffer_1 && threshold_2 >= 0.001; i++) //��Ϊthreshold_2��Ե�ʣ��������ȥ 
                        {
                            //�жϵ�ǰ�����������IBL̽�룬�����ǰ���ص��ܱ�ĳ��IBLӰ�죬������ڲ� if ��ִ֧���߼� 
                            uint tb4_idx = i + ret_from_t3_buffer_2;
                            //����������ʹ�� tb4_idx ����ȡ�����Ĳ��� -> t4��t3һ����Ҳ����ӳ��� 
                            //ld_indexable(buffer)(short,short,short,short) out, tb4_idx, t4.x  -> ʹ��tb4_idx=[0-8]�������ض���"6" 
                            //����ʹ���Ӽ����"��ȷֵ" -> out = 12 ����� 
                            half3 v_PixelToProbe = posWS - cb4_12.xyz;  //r7.xyz
                            half d_PixelToProbe_square = dot(v_PixelToProbe, v_PixelToProbe); //���ص�̽������ƽ�� 
                            half d_PixelToProbe = sqrt(d_PixelToProbe_square);      //���ص�̽��ľ��� 
                            //half probe_range_2 = cb4_12.w;
                            half probe_range_2 = 10000;
                            if (d_PixelToProbe < probe_range_2)  //���Ե�ǰ�����������������Ƿ���Ŀ��Probe�����÷�Χ�� 
                            {
                                half d_rate = saturate(d_PixelToProbe / probe_range_2); //����ռ��  
                                half VRoP2P = dot(VR, v_PixelToProbe);  //ע:��һ����specʱʹ�õ��� VR_Lift 
                                //��ʽ��ʽΪ: Scale * VR + v_PixelToProbe - [200,0,0] 
                                half3 shifted_p2p_dir_2 = (sqrt(pow2(VRoP2P) - (d_PixelToProbe_square - pow2(probe_range_2))) - VRoP2P) * VR + v_PixelToProbe - half3(200, 0, 0);
                                
                                tmp1 = max(2.5 * d_rate - 1.5, 0);  //��� (���ص�̽��ľ��� / ̽��Ӱ��뾶R) < 0.6 -> ��ʽһ�ɷ��� 0 
                                half rate_factor = 1.0 - (3.0 - 2.0 * tmp1) * pow2(tmp1); //������������ 
                                //shifted_p2p_dir_2 �ǲ���cubemap�ķ���ָ�� 
                                //IBL_cubemap_array��index�� cb4[12 + 341].y ��ã���ǰֵΪ "13" 
                                //ע�⣬����û����Cubemap_array��ʽ����ԭʼ��Դ�������²�����uv������û�е���ά(array����) 
                                half4 ibl_raw_2 = SAMPLE_TEXTURECUBE_LOD(_IBL, sampler_IBL, shifted_p2p_dir_2, lod_lv_spc2).rgba; 
                                //���� ibl_spec2_output -> cb4_353.x=1 
                                ibl_spec2_output = (cb4_353.x * ibl_raw_2.rgb) * rate_factor * threshold_2 * smoothness_2 + ibl_spec2_output;
                                //���� threshold_2 -> spec_second_intensity 
                                threshold_2 = threshold_2 * (1.0 - rate_factor * ibl_raw_2.a); 
                            }
                        }

                        //�ڶ��β�����պ�  
                        if (true)  //���ǽ��� 
                        {
                            half sky_lod_2 = 1.8154297 - (1.0 - 1.2 * log(frxx_condi.y)) - 1;
                            half3 sky_raw_2 = SAMPLE_TEXTURECUBE_LOD(_Sky, sampler_Sky, VR, sky_lod_2).rgb;
                            gi_spec_second_base = sky_raw_2 * V_CB1_180 * smoothness_2 + gi_spec_second_base; //Ϊgi_spec׷����պеĹ��� 
                        }
                        
                        half spec_second_intensity_final = threshold_2; //���������£������Ϳ 
                        half3 ibl_scale_3chan = half3(1, 1, 1);         //������� cb1_156_xyz �е����� -> ���� ibl_spec2 
                        half3 scale_second_spec = half3(1, 1, 1);       //������� cb1_134_yyy �е����� -> ���� �ڶ��߹���ܺ� 
                        
                        //ibl_spec2_output * ibl_scale_3chan -> ��Ҫ���ԡ�IBL��ͼ��ɫ���롮�ڶ��߹�ǿ�ȡ��Ļ�� -> ������ GI_Spec_second_Mirror 
                        //gi_spec_second_base * spec_second_intensity_final -> ��Ҫ���ԡ�������ɫ���롮�ڶ��߹�ǿ�ȡ��Ļ�� -> ������ GI_Spec_second_Diffuse 
                        //gi_spec_2 -> �Ǿ��������ĵ�һ�߹���ɫ 
                        Specular_Final = (ibl_spec2_output * ibl_scale_3chan + gi_spec_second_base * spec_second_intensity_final)* scale_second_spec + gi_spec_2; 

                        //test.xyz = Specular_Final;
                    }
                    else  //���� #4��Ҳ���� #0 �� #7 ������������Ⱦͨ�� 
                    {
                        half2 lut_uv_1 = half2(NoV_sat, rifr.w);  //���ǵ�һ��lut_uv��rifr.w->��Ӧ�ֲڶ�rough2 
                        half2 lut_raw_1 = SAMPLE_TEXTURE2D(_LUT, sampler_LUT, lut_uv_1); 
                        half shifted_lut_bias = saturate(spec_power_mask.y * 50.0) * lut_raw_1.y;
                        half3 gi_spec_brdf_1 = spec_power_mask.xyz * lut_raw_1.x + shifted_lut_bias;  //��һ�� GI_Spec �е�Ԥ���� brdf���ֵ  
                        half3 gi_spec_1 = prefilter_Specular * gi_spec_brdf_1; 
                        Specular_Final = gi_spec_1;
                    }

                    Specular_Final = min(-Specular_Final, half3(0, 0, 0)); 
                    output.xyz = -Specular_Final + R10.xyz; 
                    //test.xyz = output.xyz; 
                }
                else
                {
                    //o0.xyz = R10��ɫ 
                    //����û�и߹�Ĳ��� -> ֱ�ӷ���R10��ɫ -> R10��ɫ������Ϊ�� GI_Diffuse_Final 
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
