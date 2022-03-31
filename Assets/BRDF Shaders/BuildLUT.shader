Shader "Example/BuildLUT"
{
    Properties
    {
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

            float GeometrySchlickGGX(float nv, float roughness)
            {
                float k = (roughness * roughness) / 2.0;
                float nom = nv;
                float denom = nv * (1.0 - k) + k;
                return nom / denom;
            }

            float GeometrySmith(float nv, float nl, float roughness) 
            {
                return GeometrySchlickGGX(nv, roughness) * GeometrySchlickGGX(nl, roughness);
            }

            float2 IntegrateBRDF(float nv, float roughness) 
            {
                float3 V;
                V.x = sqrt(1.0 - nv * nv);  //sqrt(1-(cos¦È)^2) = sin¦È
                V.y = 0;
                V.z = nv;   //cos¦È
                float A = 0.0;  //output scale
                float B = 0.0;  //output bias
                float3 N = float3 (0.0, 0.0, 1.0); //default normal in model space

                const uint SAMPLE_COUNT = 1024u;
                for (uint i = 0u; i < SAMPLE_COUNT; i++) {
                    float2 Xi = Hammersley(i, SAMPLE_COUNT);  //sample solid angle as incident ray direction
                    float3 H = ImportanceSampleGGX(Xi, N, roughness);  //apply importance sampling to H
                    float3 L = normalize(2.0 * dot(V, H) * H - V); //cal light dir according to H and V
                    //prepare params
                    float nl = max(L.z, 0.0);
                    float nh = max(H.z, 0.0);
                    float vh = max(dot(V, H), 0.0);
                    if (nl > 0.0)  //the incoming light should above the horizon line
                    {
                        float G = GeometrySmith(nv, nl, roughness);  //cal SmithG
                        float G_Vis = (G * vh) / (nh * nv); //trun G to macro space by appling coefs 
                        float Fc = pow(1.0 - vh, 5.0);      //the core part of Shlick Fresnel

                        A += (1.0 - Fc) * G_Vis;            //accumulate results 
                        B += Fc * G_Vis;
                    }
                }
                A /= float(SAMPLE_COUNT);   //divide by N 
                B /= float(SAMPLE_COUNT);
                return float2(A, B);
            }

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float4 positionCS : SV_POSITION;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = IN.uv;
                return OUT;
            }

            float4 frag (Varyings IN) : SV_Target
            {
                float2 col = IntegrateBRDF(IN.uv.x, IN.uv.y);

                return float4(col, 0, 1);
            }
            ENDHLSL
        }
    }
}
