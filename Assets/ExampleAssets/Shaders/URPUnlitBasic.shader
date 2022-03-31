Shader "Example/URPUnlitBasic"
{
    Properties
    {
        [MainTexture] _MainTex("Base Texture", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)
    }
        SubShader
        {
            // SubShader Tags define when and under which conditions a SubShader block or a pass is executed.
            Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

            Pass
            {
                // The HLSL code block. Unity SRP uses the HLSL language.
                HLSLPROGRAM

    #pragma vertex vert // This line defines the name of the vertex shader.
    #pragma fragment frag // This line defines the name of the fragment shader.

                // The Core.hlsl file contains definitions of frequently used HLSL
                // macros and functions, and also contains #include references to other
                // HLSL files (for example, Common.hlsl, SpaceTransforms.hlsl, etc.).
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            // This macro declares _MainTex as a Texture2D object.    
            TEXTURE2D(_MainTex);
            // This macro declares the sampler for the _MainTex texture.
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                // The following line declares the _BaseMap_ST variable, so that you
                // can use the _BaseMap variable in the fragment shader. The _ST
                // suffix is necessary for the tiling and offset function to work.
                float4 _MainTex_ST;
            CBUFFER_END

            struct Attributes {
                // The positionOS variable contains the vertex positions in object space.
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                half3 normal : NORMAL;
            };

            struct Varyings {
                // The positions in this struct must have the SV_POSITION semantic.
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                half3 normal : TEXCOORD1;
            };

            Varyings vert(Attributes IN)
            {
                // Declaring the output object (OUT) with the Varyings struct.
                Varyings OUT;

                // The TransformObjectToHClip function transforms vertex positions
                // from object space to homogenous clip space.
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);

                // Use the TransformObjectToWorldNormal function to transform the
                // normals from object to world space. This function is from the
                // SpaceTransforms.hlsl file, which is referenced in Core.hlsl.
                OUT.normal = TransformObjectToWorldNormal(IN.normal);

                // The TRANSFORM_TEX macro performs the tiling and offset transformation.
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                half4 normalColor = 0;
                normalColor.rgb = IN.normal * 0.5 + 0.5;
                return _BaseColor * texColor * normalColor;
            }

            ENDHLSL

        }
    }
}
