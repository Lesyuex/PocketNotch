#include <metal_stdlib>
using namespace metal;

static uint haloParticleHash(uint value) {
    value += 0x9E3779B9u;
    value = (value ^ (value >> 16)) * 0x85EBCA6Bu;
    value = (value ^ (value >> 13)) * 0xC2B2AE35u;
    return value ^ (value >> 16);
}

static float haloParticleNoise(uint seed) {
    return float(haloParticleHash(seed) & 0x00FFFFFFu) / float(0x01000000u);
}

[[ stitchable ]] half4 haloParticleDissolve(
    float2 position,
    half4 color,
    float2 size,
    float progress,
    float cellSize,
    float coarseCellSpan,
    float fineNoiseWeight,
    float initialThreshold,
    float frontTravel,
    float noiseSpread,
    float fadeWidth
) {
    float2 safeSize = max(size, float2(1.0));
    float safeCellSize = max(cellSize, 0.5);
    uint columns = max(uint(ceil(safeSize.x / safeCellSize)), 1u);
    uint2 cell = uint2(floor(position / safeCellSize));

    uint fineSeed = (cell.y * columns + cell.x) * 5u + 1u;
    uint coarseSpan = max(uint(round(coarseCellSpan)), 1u);
    uint coarseColumns = max(
        uint(ceil(float(columns) / float(coarseSpan))),
        1u
    );
    uint2 coarseCell = cell / coarseSpan;
    uint coarseSeed = (coarseCell.y * coarseColumns + coarseCell.x) * 7u + 3u;

    float fineNoise = haloParticleNoise(fineSeed);
    float coarseNoise = haloParticleNoise(coarseSeed);
    float noise = mix(coarseNoise, fineNoise, fineNoiseWeight);
    float horizontalProgress = clamp(
        (float(cell.x) + 0.5) / float(columns),
        0.0,
        1.0
    );
    float threshold = initialThreshold
        + (1.0 - horizontalProgress) * frontTravel
        + noise * noiseSpread;
    float normalizedProgress = clamp(
        (progress - threshold + fadeWidth * 0.5) / max(fadeWidth, 0.001),
        0.0,
        1.0
    );
    float remainingOpacity = 1.0 - smoothstep(0.0, 1.0, normalizedProgress);

    return color * half(remainingOpacity);
}
