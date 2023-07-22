#ifndef UNITY_VOLUMETRIC_LIGHTING_COMMON_INCLUDED
#define UNITY_VOLUMETRIC_LIGHTING_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
real LerpWhiteTo(real b, real t) { return (1.0 - t) + b * t; }  // To prevent compile error
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/VolumeRendering.hlsl"

CBUFFER_START(ShaderVariablesFog)
    uint        _FogEnabled;
    uint        _EnableVolumetricFog;
    uint        _FogColorMode;
    uint        _MaxEnvCubemapMip;
    float4      _FogColor;
    float4      _MipFogParameters;
    float4      _HeightFogParams;
    float4      _HeightFogBaseScattering;
CBUFFER_END

#define FOGCOLORMODE_SKY_COLOR              1   // 0 = Constant color
#define ENVCONSTANTS_CONVOLUTION_MIP_COUNT  _MaxEnvCubemapMip
#define _MipFogNear                         _MipFogParameters.x
#define _MipFogFar                          _MipFogParameters.y
#define _MipFogMaxMip                       _MipFogParameters.z
#define _HeightFogBaseHeight                _HeightFogParams.x
#define _HeightFogBaseExtinction            _HeightFogParams.y
#define _HeightFogExponents                 _HeightFogParams.zw

CBUFFER_START(ShaderVariablesVolumetric)
    uint        _VolumetricFilteringEnabled;
    uint        _VBufferHistoryIsValid;
    uint        _VBufferSliceCount;
    float       _VBufferAnisotropy;
    float       _CornetteShanksConstant;
    float       _VBufferVoxelSize;
    float       _VBufferRcpSliceCount;
    float       _VBufferUnitDepthTexelSpacing;
    float       _VBufferScatteringIntensity;
    float       _VBufferLastSliceDist;
    float       __vbuffer_pad00__;
    float       __vbuffer_pad01__;
    float4      _VBufferViewportSize;
    float4      _VBufferLightingViewportScale;
    float4      _VBufferLightingViewportLimit;
    float4      _VBufferDistanceEncodingParams;
    float4      _VBufferDistanceDecodingParams;
    float4      _VBufferSampleOffset;
    float4      _RTHandleScale;
    float4x4    _VBufferCoordToViewDirWS;
CBUFFER_END


struct JitteredRay
{
    float3 originWS;
    float3 centerDirWS;
    float3 jitterDirWS;
    float3 xDirDerivWS;
    float3 yDirDerivWS;
    float  geomDist;

    float maxDist;
};

struct VoxelLighting
{
    float3 radianceComplete;
    float3 radianceNoPhase;
};

// Returns the forward (up) direction of the current view in the world space.
float3 GetViewUpDir()
{
    float4x4 viewMat = GetWorldToViewMatrix();
    return viewMat[1].xyz;
}

float GetInversePreviousExposureMultiplier()
{
    return 1.0f;
    // float exposure = GetPreviousExposureMultiplier();
    // return rcp(exposure + (exposure == 0.0)); // zero-div guard
}
float GetCurrentExposureMultiplier()
{
    return 1.0f;
// #if SHADEROPTIONS_PRE_EXPOSITION
//     // _ProbeExposureScale is a scale used to perform range compression to avoid saturation of the content of the probes. It is 1.0 if we are not rendering probes.
//     return LOAD_TEXTURE2D(_ExposureTexture, int2(0, 0)).x * _ProbeExposureScale;
// #else
//     return _ProbeExposureScale;
// #endif
}

// Copied from EntityLighting
real3 DecodeHDREnvironment(real4 encodedIrradiance, real4 decodeInstructions)
{
    // Take into account texture alpha if decodeInstructions.w is true(the alpha value affects the RGB channels)
    real alpha = max(decodeInstructions.w * (encodedIrradiance.a - 1.0) + 1.0, 0.0);

    // If Linear mode is not supported we can skip exponent part
    return (decodeInstructions.x * PositivePow(alpha, decodeInstructions.y)) * encodedIrradiance.rgb;
}

bool IsInRange(float x, float2 range)
{
    return clamp(x, range.x, range.y) == x;
}

VoxelLighting EvaluateVoxelLightingDirectional(PositionInputs posInput, float extinction, float anisotropy,
                                               JitteredRay ray, float t0, float t1, float dt, float3 centerWS, float rndVal)
{
    VoxelLighting lighting;
    ZERO_INITIALIZE(VoxelLighting, lighting);

    const float NdotL = 1;

    float tOffset, weight;
    ImportanceSampleHomogeneousMedium(rndVal, extinction, dt, tOffset, weight);

    float t = t0 + tOffset;
    posInput.positionWS = ray.originWS + t * ray.jitterDirWS;

    // Main light
    {
        float  cosTheta = dot(_MainLightPosition.xyz, ray.centerDirWS);
        float  phase = CornetteShanksPhasePartVarying(anisotropy, cosTheta);

        // Evaluate sun shadow
        float4 shadowCoord = TransformWorldToShadowCoord(posInput.positionWS);
        shadowCoord.w = max(shadowCoord.w, 0.001);
        float  atten = MainLightShadow(shadowCoord, posInput.positionWS, 0, 0);
        half3  color = _MainLightColor.rgb * lerp(_VBufferScatteringIntensity, atten, atten < 1);

        lighting.radianceNoPhase += color * weight;
        lighting.radianceComplete += color * weight * phase;
    }

    // Additional light
#if USE_FORWARD_PLUS
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
    #if USE_STRUCTURED_BUFFER_FOR_LIGHT_DATA
        float4 lightPositionWS = _AdditionalLightsBuffer[lightIndex].position;
        half3 color = _AdditionalLightsBuffer[lightIndex].color.rgb;
    #else
        float4 lightPositionWS = _AdditionalLightsPosition[lightIndex];
        half3 color = _AdditionalLightsColor[lightIndex].rgb;
    #endif
        
        color *= _VBufferScatteringIntensity;
        float  cosTheta = dot(lightPositionWS.xyz, ray.centerDirWS);
        float  phase = CornetteShanksPhasePartVarying(anisotropy, cosTheta);

        lighting.radianceNoPhase += color * weight;
        lighting.radianceComplete += color * weight * phase;
    }
#endif

    return lighting;
}


VoxelLighting EvaluateVoxelLightingLocal(float2 pixelCoord, float extinction, float anisotropy,
                                         JitteredRay ray, float t0, float t1, float dt,
                                         float3 centerWS, float rndVal)
{
    VoxelLighting lighting;
    ZERO_INITIALIZE(VoxelLighting, lighting);

#if USE_FORWARD_PLUS
    float sampleOpticalDepth = extinction * dt;
    float sampleTransmittance = exp(-sampleOpticalDepth);
    float rcpExtinction = rcp(extinction);
    float weight = (rcpExtinction - rcpExtinction * sampleTransmittance) * rcpExtinction;

    uint lightIndex;
    ClusterIterator _urp_internal_clusterIterator = ClusterInit(GetNormalizedScreenSpaceUV(pixelCoord), centerWS, 0);
    [loop]
    while (ClusterNext(_urp_internal_clusterIterator, lightIndex))
    {
        lightIndex += URP_FP_DIRECTIONAL_LIGHTS_COUNT;

    #if USE_STRUCTURED_BUFFER_FOR_LIGHT_DATA
        float4 lightPositionWS = _AdditionalLightsBuffer[lightIndex].position;
        half3 color = _AdditionalLightsBuffer[lightIndex].color.rgb;
        half4 distanceAndSpotAttenuation = _AdditionalLightsBuffer[lightIndex].attenuation;
        half4 spotDirection = _AdditionalLightsBuffer[lightIndex].spotDirection;
        uint lightLayerMask = _AdditionalLightsBuffer[lightIndex].layerMask;
    #else
        float4 lightPositionWS = _AdditionalLightsPosition[lightIndex];
        half3 color = _AdditionalLightsColor[lightIndex].rgb;
        half4 distanceAndSpotAttenuation = _AdditionalLightsAttenuation[lightIndex];
        half4 spotDirection = _AdditionalLightsSpotDir[lightIndex];
        uint lightLayerMask = asuint(_AdditionalLightsLayerMasks[lightIndex]);
    #endif

        // Jitter
        float lightSqRadius = rcp(distanceAndSpotAttenuation.x);
        float t, distSq, rcpPdf;
        ImportanceSamplePunctualLight(rndVal, lightPositionWS.xyz, lightSqRadius,
                                      ray.originWS, ray.jitterDirWS, t0, t1,
                                      t, distSq, rcpPdf);
        float3 positionWS = ray.originWS + t * ray.jitterDirWS;

        float3 lightVector = lightPositionWS.xyz - positionWS * lightPositionWS.w;
        float distanceSqr = max(dot(lightVector, lightVector), HALF_MIN);

        half3 lightDirection = half3(lightVector * rsqrt(distanceSqr));
        float attenuation = DistanceAttenuation(distanceSqr, distanceAndSpotAttenuation.xy) * AngleAttenuation(spotDirection.xyz, lightDirection, distanceAndSpotAttenuation.zw);
        half3 L = color * attenuation * _VBufferScatteringIntensity;

        // TODO: 1. IES & Cookie

        // TODO: 2. Shadow?

        float3 centerL  = lightPositionWS.wyz - centerWS;
        float  cosTheta = dot(normalize(centerL), ray.centerDirWS);
        float  phase = CornetteShanksPhasePartVarying(anisotropy, cosTheta);

        lighting.radianceNoPhase += L * weight * rcpPdf;
        lighting.radianceComplete += L * weight * phase * rcpPdf;
    }
#endif

    return lighting;
}

#endif