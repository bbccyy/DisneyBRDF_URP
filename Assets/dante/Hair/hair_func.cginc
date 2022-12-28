#ifndef UNITY_BRDF
#define UNITY_BRDF

#define UNITY_PI 3.14159265359f
#define UNITY_TWO_PI 6.28318530718f

float pow2(float i){
    return i * i;
}

float pow5(float i){
    return pow2(i) * pow2(i) * i;
}

struct BRDFSingleLightOutput{
    float3 SingleLightBRDF;
};

struct HairAngles{
    float LdotV;
    float sinThetaL;
    float sinThetaV;
    float cosThetaD;
    float3 thetaD;
    float3 LOnNp;
    float3 VOnNp;
    float cosPhi;
    float cosHalfPhi;
    float NdotL;
};

//hair color from medulla absorption
//ref: UE4 HairShadingCommon.ush
//Article ref:
//A Practical and Controllable Hair and Fur Model for Production Path Tracing
//An Energy-Conserving Hair Reflectance Model
float3 HairAbsorptionToColor(float3 A, float B = 0.3f){
	const float b2 = B * B;
	const float b3 = B * b2;
	const float b4 = b2 * b2;
	const float b5 = B * b4;
	const float D = (5.969f - 0.215f * B + 2.532f * b2 - 10.73f * b3 + 5.574f * b4 + 0.245f * b5);
	return exp(-sqrt(A) * D);
}

float3 HairColorToAbsorption(float3 C, float B = 0.3f){
	const float b2 = B * B;
	const float b3 = B * b2;
	const float b4 = b2 * b2;
	const float b5 = B * b4;
	const float D = (5.969f - 0.215f * B + 2.532f * b2 - 10.73f * b3 + 5.574f * b4 + 0.245f * b5);
	return pow2(log(C) / D);
}

float3 GetHairColorFromMelanin(float InMelanin, float InRedness, float3 InDyeColor){
	InMelanin = saturate(InMelanin);
	InRedness = saturate(InRedness);
	const float Melanin		= -log(max(1 - InMelanin, 0.0001f));
	const float Eumelanin 	= Melanin * (1 - InRedness);
	const float Pheomelanin = Melanin * InRedness;

	const float3 DyeAbsorption = HairColorToAbsorption(saturate(InDyeColor));
	const float3 Absorption = Eumelanin * float3(0.506f, 0.841f, 1.653f) + Pheomelanin * float3(0.343f, 0.733f, 1.924f);

	return HairAbsorptionToColor(Absorption + DyeAbsorption);
}

//Mp
float Mp_Logistic(float thetaH, float lambda){
    //UE4 uses -alpha instead of +alpha
    float up = exp((thetaH) / lambda);
    float down = lambda * pow2(1 + exp((thetaH) / lambda));
    return up / down;
}

float Mp_Gaussian(float thetaH, float lambda){
    //UE4 uses -alpha instead of +alpha
    float up = exp(-0.5 * pow2(thetaH) / pow2(lambda));
    float down = sqrt(UNITY_TWO_PI) * lambda;
    return up / down;
}

//Np
//UE4 approx
float NR(float cosHalfPhi){
    return 0.25f * cosHalfPhi;
}

float NTT(float cosPhi){
    return exp(-3.65 * cosPhi - 3.98);
}

float NTRT(float cosPhi){
    return exp(17 * cosPhi - 16.78);
}

//Fp in Ap
//p = R, FR = fresnel. p = TT, FTT = fattentt. p = TRT, FTRT = fattentrt
float Fresnel(float cosAngle, float ior = 1.55){
    float F0 = pow2((1 - ior) / (1 + ior));
    return F0 + (1 - F0) * pow5(1 - cosAngle);
}

float FAttenTT(float Fresnel){
    return pow2(1 - Fresnel);
}

float FAttenTRT(float Fresnel){
    return pow2(1 - Fresnel) * Fresnel;
}

float ModifiedIor(float3 thetaD, float ior = 1.55){
    return sqrt(pow2(ior) - pow2(sin(thetaD))) / cos(thetaD);
}

//h
float hTT(float cosPhi, float cosHalfPhi, float3 thetaD){
    float a = 1 / ModifiedIor(thetaD);
    return (1 + a * (0.6 - 0.8 * cosPhi)) * cosHalfPhi;
}

float3 TTT(float h, float3 thetaD, float cosPhi, float cosHalfPhi, float3 C){
    float power = sqrt(1 - pow2(hTT(cosPhi, cosHalfPhi, thetaD)) * pow2(1 / ModifiedIor(thetaD))) / (2 * cos(thetaD));
    return pow(C, power);
}

float3 TTRT(float3 thetaD, float3 C){
    float power = 0.8 / cos(thetaD);
    return pow(C, power);
}

//c(olor) or albedo, m(etallic), l(ight), v(iew), n(ormal), s(hadow)
float3 KajiyaDiffuse(float3 C, float m, float3 l, float3 v, float3 n, float s){
    float KajiyaDiffuse = 1 - abs(dot(n, l));
    float3 fakeNormal = normalize(v - n * dot(v, n));
    n = fakeNormal;

    float Wrap = 1;
    float NoL = saturate((dot(n ,l) + Wrap) / pow2(1 + Wrap));
    float diffuseScatter = (1 / UNITY_PI) * lerp(NoL, KajiyaDiffuse, 0.33) * m;
    float3 Luminance = (0.3f, 0.59f, 0.11f);
    float luma = dot(C, Luminance);
    float3 ScatterTint = pow(abs(C / luma), 1 - s);
    return sqrt(abs(C)) * diffuseScatter * ScatterTint;
}

float3 SRvalue(float alpha, float lambda, HairAngles hairAngles){
    float sa = sin(alpha);
    float ca = cos(alpha);
    float ModifiedShift = 2 * sa * (ca * hairAngles.cosHalfPhi * sqrt(1 - hairAngles.sinThetaV * hairAngles.sinThetaV) + sa * hairAngles.sinThetaV);
    float GaussianX = hairAngles.sinThetaL + hairAngles.sinThetaV - ModifiedShift;
    float MRValue = Mp_Gaussian(GaussianX, lambda);
    //float MRValue = Mp_Logistic(GaussianX, lambda);
    float NRValue = NR(hairAngles.cosHalfPhi);
    float FRValue = Fresnel(sqrt(saturate(0.5f + 0.5f * hairAngles.LdotV)));
    float3 TR = (1, 1, 1);
    return MRValue * NRValue * FRValue * TR * hairAngles.NdotL;
}

float3 STTvalue(float alpha, float lambda, HairAngles hairAngles, float3 outColor){
    float GaussianX = hairAngles.sinThetaL + hairAngles.sinThetaV - alpha;
    float MTTValue = Mp_Gaussian(GaussianX, lambda);
    float NTTValue = NTT(hairAngles.cosPhi);
    float htt = hTT(hairAngles.cosPhi, hairAngles.cosHalfPhi, hairAngles.thetaD);
    float cosTTH = cos(asin(htt));
    float FTTValue = FAttenTT(Fresnel(hairAngles.cosThetaD * cosTTH));
    float3 TTTValue = TTT(htt, hairAngles.thetaD, hairAngles.cosPhi, hairAngles.cosHalfPhi, outColor);
    return MTTValue * NTTValue * FTTValue * TTTValue;
}

float3 STRTvalue(float alpha, float lambda, HairAngles hairAngles, float3 outColor){
    float GaussianX = hairAngles.sinThetaL + hairAngles.sinThetaV - alpha;
    float MTRTValue = Mp_Gaussian(GaussianX, lambda);
    //float MTRTValue = Mp_Logistic(GaussianX, lambda);
    float NTRTValue = NTRT(hairAngles.cosPhi);
    float hTRT = 0.8660254037844386; //sqrt(3)/2
    float cosTRTH = cos(asin(hTRT));
    float FTRTValue = FAttenTRT(Fresnel(hairAngles.cosThetaD * cosTRTH));
    float3 TTRTValue = TTRT(hairAngles.thetaD, outColor);
    return MTRTValue * NTRTValue * FTRTValue * TTRTValue;
}



#endif