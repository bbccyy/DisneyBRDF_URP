Shader "Kena/KenaDirLight"
{
	Properties
	{
		[NoScaleOffset] _SSS("SSS", 2D)						= "white" {}
		[NoScaleOffset] _Depth("Depth", 2D)					= "white" {}
		[NoScaleOffset] _Normal("Normal", 2D)				= "white" {}
		[NoScaleOffset] _Comp_M_D_R_F("Comp_M_D_R_F", 2D)	= "white" {}
		[NoScaleOffset] _Albedo("Albedo", 2D)				= "white" {}
		[NoScaleOffset] _Comp_F_R_X_I("Comp_F_R_X_I", 2D)	= "white" {}
		[NoScaleOffset] _SSAO("SSAO", 2D)					= "white" {}
		[NoScaleOffset] _ShadowTex("ShadowTex", 2D)			= "white" {}
		[NoScaleOffset] _LUT("LUT", 2D)						= "white" {}
	}

	SubShader
	{
		Tags {"RenderType"="Opaque"}
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
				float4 positionOS	: POSITION;
				float2 uv			: TEXCOORD0;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct v2f
			{
				float4 positionPS	: SV_POSITION;
				float2 uv			: TEXCOORD0;
				float3 viewDirWS		: TEXCOORD1;
				UNITY_VERTEX_OUTPUT_STEREO
			};

			TEXTURE2D(_SSS); SAMPLER(sampler_SSS);
			TEXTURE2D(_Depth); SAMPLER(sampler_Depth);
			TEXTURE2D(_Normal); SAMPLER(sampler_Normal);
			TEXTURE2D(_Comp_M_D_R_F); SAMPLER(sampler_Comp_M_D_R_F);
			TEXTURE2D(_Albedo); SAMPLER(sampler_Albedo);
			TEXTURE2D(_Comp_F_R_X_I); SAMPLER(sampler_Comp_F_R_X_I);
			TEXTURE2D(_SSAO); SAMPLER(sampler_SSAO);
			TEXTURE2D(_ShadowTex); SAMPLER(sampler_ShadowTex);
			TEXTURE2D(_LUT); SAMPLER(sampler_LUT);


			static float4 screen_param = float4(1707, 960, 0.00059, 0.00104);

			static float4 zBufferParams = float4(0.00, 0.00, 0.10, -1.00000E-08); //CB0[65].xyzw 

			static float4 cameraPosWSoffset = float4(-58625.35547, 27567.39453, -6383.71826, 0);

			static float3x3 Matrix_Inv_VP = float3x3(
				float3(0.7495,			0.11887,	-0.5012),
				float3(-0.49857,		0.1787,		-0.75428),
				float3(-2.68273E-08,	0.4585,		0.42411)
				);


			v2f vert(appdata IN)
			{
				v2f OUT = (v2f)0;
				UNITY_SETUP_INSTANCE_ID(IN);
				//OUT.uv = (IN.uv * screen_param.xy) * screen_param.zw;
				OUT.uv = IN.uv;
				OUT.positionPS = TransformObjectToHClip(IN.positionOS);

				float2 ndc_xy = IN.uv * 2 - 1;  //放到[-1,1]区间 
				ndc_xy = ndc_xy * float2(1.0, -1.0);

				OUT.viewDirWS = mul(Matrix_Inv_VP, float3(ndc_xy.xy, 1));

				return OUT;
			}

			half4 frag(v2f IN) : SV_Target
			{
				half4 test = half4(0,0,0,1);

				test.xyz = normalize(IN.viewDirWS);

				//采样Comp，提取Flag位
				half4 comp_m_d_r_f = SAMPLE_TEXTURE2D(_Comp_M_D_R_F, sampler_Comp_M_D_R_F, IN.uv);
				uint raw_flag = (uint)round(comp_m_d_r_f.w * 255); 
				uint mat_type = raw_flag & (uint)15;

				half deviceZ = SAMPLE_TEXTURE2D(_Depth, sampler_Depth, IN.uv);

				half sceneDepth = deviceZ* zBufferParams.x + zBufferParams.y + 1.0 / (deviceZ * zBufferParams.z - zBufferParams.w);

				half3 posWS = normalize(IN.viewDirWS) * sceneDepth + cameraPosWSoffset.xyz;

				test.xyz = abs(posWS - cameraPosWSoffset.xyz) / 35000;


				uint tmp = mat_type == (uint)7;


				return half4(tmp.xxx, 1);
			}

			ENDHLSL
		}
	}
}