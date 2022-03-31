Shader "Example/BuildIrradiance"
{
    Properties
    {
        _Skybox         ("Sky box", CUBE)               = "white" {}
        _SampleStep     ("Sample", Range(0.01, 0.5))    = 0.1
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

            TEXTURECUBE(_Skybox); SAMPLER(sampler_Skybox);

            CBUFFER_START(UnityPerMaterial)
                float _SampleStep;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionOS : TEXCOORD0;
                float4 positionCS : SV_POSITION;
            };

            Varyings vert (Attributes IN)
            {
                //according UnityCamera.RenderToCubemap's paradigm,
                //the input vertex should be one of six faces of a virtual box wrapped around our camera,
                //yet it's size associates to camera's near/far plane distance.
                Varyings OUT = (Varyings)0;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.positionOS = IN.positionOS;
                return OUT;
            }

            float4 frag (Varyings IN) : SV_Target
            {
                //主要目的main purpose: to compute the irradiance on each pixel of the box
                float3 irradiance = float3(0,0,0);
                //how to get irradiance: to integral the semisphere based on "local normal"
                //so need TBN matrix to convert sample_vector from tangent space to world!
                float3 normal = normalize(IN.positionOS.xyz);  //use model's vertex pos(not normal) as normal -> sphere sampling 
                float3 up = float3(0, 1, 0); //TODO: make sure up diffs with normal
                float3 right = cross(up, normal); //normal perpendicular with right
                up = cross(right, normal);  //up, normal and right form an orthogonal basis
                //Note that, since we are going to integral the whole semisphere, how to pick up should not affect the final results

                int count = 0;
                for (float phi = 0.0; phi < UNITY_TWO_PI; phi += _SampleStep) {
                    for (float theta = 0.0; theta < UNITY_PI * 0.5; theta += _SampleStep) { //why 0.5? -> consider 2*PI of phi!
                        //convert the sample_vector from spherical coord to cartesian coord(yet in tangent space)
                        float3 sample_vectorTS = float3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
                        //apply the TBN matrix to convert our sample_vector from tangent space to worold space
                        float3 sample_vectorWS = sample_vectorTS.x * right + sample_vectorTS.y * up + sample_vectorTS.z * normal;
                        //use sample_vector to sample skybox (better with box projection), the result sould be radiance 
                        float3 radiance = SAMPLE_TEXTURECUBE_LOD(_Skybox, sampler_Skybox, sample_vectorWS, 0).rgb;
                        irradiance += radiance * sin(theta) * cos(theta); //apply correction based on irradiance map theory
                        count++;  //inc sampling number 
                    }
                }

                irradiance = UNITY_PI * irradiance / count;

                return float4(irradiance, 1);
            }
            ENDHLSL
        }
    }
}
