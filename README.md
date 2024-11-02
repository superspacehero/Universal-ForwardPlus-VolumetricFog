# Universal Forward+ Volumetric Fog (Global)

![Sample](./Documentation~/Images/VolumetricFogSample.png) 

This repository is copied from Unity HDRP Volumetric Fog.

Note that this feature is working as a global fog volume while HDRP requires local volumes.
Since it shows unexpected behaviors when the screen size of Scene View and the screen size of Game View are different,
volumetric lighting is only enabled in a scene view in edit mode. If playing, only enabled in a game view.

This package is available on URP Forward+ from 2022.3.0f1 (2022 LTS) version.

To enable RenderGraph in Unity6, add `ENABLE_URP_VOLUEMTRIC_FOG_RENDERGRAPH` define to `Scripting Define Symbols` in the `Player>Script Compilation` setting.


## How to Use
1. Add 'FP Volumetric Fog' renderer feature to Renderer data (Make sure to use Forward+)
2. Create 'Volumetric Config' via 'Create/UniversalVolumetric/VolumetricFogConfig'
3. Link the config asset to the renderer feature

NOTE - If you use Unity 6 LTS and the rendering result is not as expected, change `Shader Precision Model` setting in `Project Settings > Player > Other Settings > Shader Settings`.

![How To Use](./Documentation~/Images/HowToUse.png) 


## Smoke Volume
While this package assumes a global volume, you can put a local smoke volume to make a ground smoke effect for a specific area. Smoke volume component uses a box collider to determine its area. Due to performance, it supports 4 smoke volumes at maximum.

To add a smoke volume to your scene, create a new gameObject and add 'Smoke Volume' component to the gameObject. You might need to create your own noise texture to use, but I added a default noise texture which can be found at 'Runtime/Textures/' directory.

![Smoke Volume](./Documentation~/Images/Smoke.png)
![Smoke Volume2](./Documentation~/Images/Smoke2.png)
![Smoke Volume Component](./Documentation~/Images/SmokeVolumeComponent.png)


## Limitations
1. XR not supported
2. Additional Directional & Local(point & spot) lights are only available in Forward+
   
   (In other words, only MainLight is working for Forward)
   
3. TAA not supported
4. DiffuseGI does not contribute to lighting
5. Noise texture is not supported 
6. The number of LocalSmokeVolume is 4 at maximum.
7. Volumetric lighting is only enabled in a scene view in edit mode. If playing, only enabled in a game view.
