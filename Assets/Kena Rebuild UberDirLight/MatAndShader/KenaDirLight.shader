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
				float4 vertex	: POSITION;
				float2 uv		: TEXCOORD0;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct v2f
			{
				float4 positionPS	: SV_POSITION;
				float2 uv			: TEXCOORD0;
				float3 viewDir		: TEXCOORD1;
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


			static float4 screen_param = float4(1708, 960, 1.0 / 1708, 1.0 / 960);






			ENDHLSL
		}
	}
}