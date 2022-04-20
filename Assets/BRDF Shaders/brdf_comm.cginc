#ifndef UNITY_BRDF
#define UNITY_BRDF

#define UNITY_PI 3.14159265359f
#define UNITY_TWO_PI 6.28318530718f

//------- For Sampling -------
//Ver De Corput
float RadicalInverse_VdC(uint bits)
{
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}

//key words: sampling, low-discrepancy sequences, radical inverse function
float2 Hammersley(uint i, uint N)
{
    return float2(float(i) / float(N), RadicalInverse_VdC(i));
}

float3 ImportanceSampleGGX(float2 Xi, float3 N, float roughness) {
    float a = roughness * roughness;
    //spherical coordinate
    float phi = 2.0 * UNITY_PI * Xi.x;
    float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a * a - 1.0) * Xi.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
    //to cartesian coordinate
    float3 H;
    H.x = cos(phi) * sinTheta;
    H.y = sin(phi) * sinTheta;
    H.z = cosTheta;
    //tangent vector to world space sample vector
    float3 up = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
    float3 tangent = normalize(cross(up, N));
    float3 bitangent = cross(N, tangent);

    float3 sampleVector = tangent * H.x + bitangent * H.y + N * H.z;
    return normalize(sampleVector);
}

float NormalDistributionF_PreFilter(float nh, float roughness) {
    roughness *= roughness;
    float a2 = roughness * roughness;
    float nh2 = nh * nh;
    float den = nh2 * (a2 - 1.0) + 1.0;
    return nh2 / (UNITY_PI * den * den);
}
//------- End Sampling -------


//------- Common Input -------

#ifdef BRDF_TEX
    TEXTURE2D(_Metallic); SAMPLER(sampler_Metallic);
    TEXTURE2D(_Roughness); SAMPLER(sampler_Roughness);

    TEXTURECUBE(_IrradianceMap); SAMPLER(sampler_IrradianceMap);
    TEXTURE2D(_LUT); SAMPLER(sampler_LUT);
    TEXTURECUBE(_PrefilterMap); SAMPLER(sampler_PrefilterMap);
    TEXTURE2D(_AO); SAMPLER(sampler_AO);

    CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;
    float _RoughnessOffset;
    float _RoughnessScale;
    float _Anisotropic;
    float _Subsurface;
    float _Specular;
    float _SpecularTint;
    float _Sheen;
    float _SheenTint;
    float _Clearcoat;
    float _ClearcoatGloss;

    float _MetalicOffset;
    float _MetalicScale;

    float _BrightnessScale;

    float _BumpScale;
    float _PrefilterScale;
    float _IrradianceScale;
    CBUFFER_END
#else
    TEXTURECUBE(_IrradianceMap); SAMPLER(sampler_IrradianceMap);
    TEXTURE2D(_LUT); SAMPLER(sampler_LUT);
    TEXTURECUBE(_PrefilterMap); SAMPLER(sampler_PrefilterMap);
    TEXTURE2D(_AO); SAMPLER(sampler_AO);

    CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;
    float _Metallic;
    float _Smoothness;
    float _Anisotropic;
    float _Subsurface;
    float _Specular;
    float _SpecularTint;
    float _Sheen;
    float _SheenTint;
    float _Clearcoat;
    float _ClearcoatGloss;

    float _BumpScale;
    CBUFFER_END
#endif

//------- End Input -------

// ------- common structure starts here -------
struct FragLightOutput
{
        float3 directLight;
        float3 Fs;
        float Gs;
        float Ds;
        float3 diffuse;
};
//------- End structure -------

// ------- common functions starts here -------
float pow2(float v) {
    return v * v;
}

float pow5(float v) {
    float v2 = v * v;
    return v2 * v2 * v;
}

float SchlickFresnel(float v) {
    v = clamp(1 - v, 0, 1);
    return pow5(v);
}

float3 Specular_Fresnel(float3 Ctint, float3 Cdlin, float Flh, float Metallic) {
    float3 F0 = lerp(_Specular * 0.08 * lerp(float3(1, 1, 1), Ctint, _SpecularTint), Cdlin, Metallic);
    float3 F = lerp(F0, float3(1, 1, 1), Flh);
    return F;
}

float Disney_Diffuse_Kfd(float roughness, float lh, float Fnl, float Fnv) {
    float FD90 = 0.5 + 2 * roughness * pow2(lh);
    return lerp(1.0, FD90, Fnl) * lerp(1.0, FD90, Fnv);
}

float Disney_Subsurface_ss(float roughness, float lh, float Fnl, float Fnv, float nl, float nv) {
    float Fss90 = pow2(lh) * roughness;
    float Fss = lerp(1.0, Fss90, Fnl) * lerp(1.0, Fss90, Fnv);
    return 1.25 * (Fss * (1 / (nl + nv) - 0.5) + 0.5);
}

//Ds
float Disney_Specular_GTR2_aniso(float hx, float hy, float nh, float ax, float ay) {
    return 1.0 / (ax * ay * pow2(pow2(hx / ax) + pow2(hy / ay) + pow2(nh)) * UNITY_PI);
}

float Disney_Specular_GTR2_iso(float nh, float a) {
    float a2 = pow2(a);
    float den = 1.0 + (a2 - 1.0) * pow2(nh);
    return a2 / (pow2(den) * UNITY_PI);
}

//Gs
float SmithsG_GGX_aniso(float nv, float vX, float vY, float ax, float ay) {
    return 1 / (nv + sqrt(pow2(vX * ax) + pow2(vY * ay) + pow2(nv)));
}

//Dr
float Disney_Clear_GTR1(float nh, float a) {
    if (a >= 1) {
        return 1 / UNITY_PI;
    }
    float a2 = pow2(a);
    return (a2 - 1) / (log(a2) * (1 + (a2 - 1) * pow2(nh)) * UNITY_PI);
}

//Gr
float Disney_Clear_GGX(float nv, float nl, float a) {
    float a2 = pow2(0.25);
    float GGXnv = 1 / (nv + sqrt(a2 + (1 - a2) * pow2(nv)));
    float GGXnl = 1 / (nl + sqrt(a2 + (1 - a2) * pow2(nl)));
    return GGXnv * GGXnl;
}

float3 fresnelSchlickRoughness(float cosTheta, float3 F0, float roughness) {
    return F0 + (max(float3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness), F0) - F0) * pow5(1.0 - cosTheta);
}

float3 ReflectionProbe_BoxProjection(float3 dir, float3 pos, float4 cubemapPos, float3 boxMin, float3 boxMax) {
    if (cubemapPos.w > 0) {

        float3 factors = ((dir > 0 ? boxMax : boxMin) - pos) / dir;
        float scalar = min(min(factors.x, factors.y), factors.z);

        dir = pos + dir * scalar + pos - cubemapPos.xyz;
    }
    return dir;
}

//------- common functions ends here -------


#endif