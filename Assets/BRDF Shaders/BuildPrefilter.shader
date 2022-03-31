Shader "Example/BuildPrefilter"
{
    Properties
    {
        _Skybox     ("Sky box", CUBE)            = "white" {}
        _Roughness  ("Sample", Range(0, 1))      = 0.1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #define UNITY_PI 3.14159265359f
            #define UNITY_TWO_PI 6.28318530718f

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "brdf_comm.cginc"

            TEXTURECUBE(_Skybox); SAMPLER(sampler_Skybox);
            
            CBUFFER_START(UnityPerMaterial)
                float _Roughness;
            CBUFFER_END
            
            

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float3 normal : TEXCOORD0;
                float4 positionCS : SV_POSITION;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.normal = IN.positionOS.xyz;

                return OUT;
            }

            float4 frag(Varyings IN) : SV_Target
            {
                float3 N = normalize(IN.normal);
                float3 R = N;
                float3 V = R;

                const uint SAMPLE_COUNT = 1024u;
                float totalWeight = 0.0f;
                float3 filterColor = float3(0.0, 0.0, 0.0);
                for (uint i = 0; i < SAMPLE_COUNT; i++)
                {
                    float2 Xi = Hammersley(i, SAMPLE_COUNT);
                    float3 H = ImportanceSampleGGX(Xi, N, _Roughness);
                    float3 L = normalize(2.0 * dot(V, H) * H - V);
                    float nl = max(dot(N, L), 0);

                    if (nl > 0)
                    {
                        float nh = max(dot(N, H), 0);
                        float hv = max(dot(H, V), 0);
                        float D = NormalDistributionF_PreFilter(nh, _Roughness);

                        //sample cubemap based on pdf and roughness
                        float pdf = D * nh / (4.0 * hv) + 0.0001;
                        const float resolution = 512.0;  //resolution of skybox cube
                        const float texel = 4.0 * UNITY_PI / (6.0 * resolution * resolution); //solid angle per sampling
                        float sasample = 1.0 / (float(SAMPLE_COUNT) * pdf + 0.0001);
                        float mipmap = _Roughness == 0.0 ? 0.0 : 0.5 * log2(sasample / texel);

                        filterColor += SAMPLE_TEXTURECUBE_LOD(_Skybox, sampler_Skybox, L, mipmap).rgb * nl;
                        totalWeight += nl;
                    }
                }

                filterColor /= totalWeight;

                return float4(filterColor, 1);
            }
            ENDHLSL
        }
    }
}
