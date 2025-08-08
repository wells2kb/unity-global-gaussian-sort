// SPDX-License-Identifier: MIT
Shader "Gaussian Splatting/Render Splats"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }

        Pass
        {
            ZWrite Off
            Blend OneMinusDstAlpha One
            Cull Off

CGPROGRAM
#pragma vertex vert
#pragma fragment frag
#pragma require compute
#pragma use_dxc

#include "GaussianSplatting.hlsl"

StructuredBuffer<uint> _OrderBuffer;

struct v2f
{
    half4 col : COLOR0;
    float2 pos : TEXCOORD0;
    float4 vertex : SV_POSITION;
};

StructuredBuffer<SplatViewData> _SplatViewData;
ByteAddressBuffer _SplatSelectedBits;
uint _SplatBitsValid;

v2f vert (uint vtxID : SV_VertexID, uint instID : SV_InstanceID)
{
    v2f o = (v2f)0;
    instID = _OrderBuffer[instID];
    SplatViewData view = _SplatViewData[instID];
    float4 centerClipPos = view.pos;
    bool behindCam = centerClipPos.w <= 0;
    if (behindCam)
    {
        o.vertex = asfloat(0x7fc00000); // NaN discards the primitive
    }
    else
    {
        o.col.r = f16tof32(view.color.x >> 16);
        o.col.g = f16tof32(view.color.x);
        o.col.b = f16tof32(view.color.y >> 16);
        o.col.a = f16tof32(view.color.y);

        // Render with the most efficient number of tris
        float costRatio = 0.5;
        float scale = length(view.axis1) * length(view.axis2);
        float triangleCost = 3 * costRatio + 3 * sqrt(3) * scale;
        float rectangleCost = 6 * costRatio + 4 * scale;
        float pentagonCost = 9 * costRatio + 5 * sqrt(5 - 2 * sqrt(5)) * scale;

        // TODO pentagon math
        // \left(0,\ b\left(\sqrt{5}-1\right)\right)
        // \left(a\sqrt{\frac{1}{2}\left(5-\sqrt{5}\right)},\ \frac{b}{2}\left(3-\sqrt{5}\right)\right)
        // \left(a\sqrt{5-2\sqrt{5}},-b\right)
        float2 quadPos;
        if (pentagonCost < rectangleCost)
        {
           if (vtxID == 0)
                quadPos = float2(-1, -1);
            else if (vtxID == 1)
                quadPos = float2(1, -1);
            else if (vtxID == 2)
                quadPos = float2(-1, 1);
            else if (vtxID == 3)
                quadPos = float2(1, -1);
            else if (vtxID == 4)
                quadPos = float2(1, 1);
            else if (vtxID == 5)
                quadPos = float2(-1, 1);
            else
                o.vertex = asfloat(0x7fc00000); // NaN discards the primitive
            o.col = float4(0.0, 0.0, 1.0, 1.0);
        }
        else if (rectangleCost < triangleCost)
        {
           if (vtxID == 0)
                quadPos = float2(-1, -1);
            else if (vtxID == 1)
                quadPos = float2(1, -1);
            else if (vtxID == 2)
                quadPos = float2(-1, 1);
            else if (vtxID == 3)
                quadPos = float2(1, -1);
            else if (vtxID == 4)
                quadPos = float2(1, 1);
            else if (vtxID == 5)
                quadPos = float2(-1, 1);
            else
                o.vertex = asfloat(0x7fc00000); // NaN discards the primitive

            o.col = float4(0.0, 1.0, 0.0, 1.0);
        }
        else
        {
           if (vtxID == 0)
                quadPos = float2(-sqrt(3), -1);
            else if (vtxID == 1)
                quadPos = float2(sqrt(3), -1);
            else if (vtxID == 2)
                quadPos = float2(0, 2);
            else
              o.vertex = asfloat(0x7fc00000); // NaN discards the primitive
          o.col = float4(1.0, 0.0, 0.0, 1.0);
        }

        quadPos *= 2;
        o.pos = quadPos;
        float2 deltaScreenPos = (quadPos.x * view.axis1 + quadPos.y * view.axis2) * 2 / _ScreenParams.xy;

        o.vertex = centerClipPos;
        o.vertex.xy += deltaScreenPos * centerClipPos.w;

        // is this splat selected?
        if (_SplatBitsValid)
        {
            uint wordIdx = instID / 32;
            uint bitIdx = instID & 31;
            uint selVal = _SplatSelectedBits.Load(wordIdx * 4);
            if (selVal & (1 << bitIdx))
            {
                o.col.a = -1;
            }
        }
    }
    FlipProjectionIfBackbuffer(o.vertex);
    return o;
}

half4 frag (v2f i) : SV_Target
{
    float power = -dot(i.pos, i.pos);
    half alpha = exp(power);
    if (i.col.a >= 0)
    {
        alpha = saturate(alpha * i.col.a);
    }
    else
    {
        // "selected" splat: magenta outline, increase opacity, magenta tint
        half3 selectedColor = half3(1,0,1);
        if (alpha > 7.0/255.0)
        {
            if (alpha < 10.0/255.0)
            {
                alpha = 1;
                i.col.rgb = selectedColor;
            }
            alpha = saturate(alpha + 0.3);
        }
        i.col.rgb = lerp(i.col.rgb, selectedColor, 0.5);
    }
    
    if (alpha < 1.0/255.0)
        discard;

    half4 res = half4(i.col.rgb * alpha, alpha);
    return res;
}
ENDCG
        }
    }
}
