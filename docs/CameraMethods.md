# Camera Methods

!!! warning
    Any method that starts with the character `_` is not meant to be called. 

-----

## new 

_Camera.new(): <span style="color: teal;">SUCamera</span>_ 

Creates a new camera instance.

## SetEnabled

_Camera:SetEnabled(Enabled: <span style="color: teal;">boolean</span>)_ 

Enables or disables the camera based on the passed value: `true` to enable and `false` to disable the camera.    

## Destroy

_Camera:Destroy()_ 
  
Cleans up references and connections established by the module. Once the destroy method is invoked on a camera, that camera should never be used again.

## ShakeWithInstance

_Camera:ShakeWithInstance(CShakeInstance: <span style="color: teal;"> [CameraShakeInstance](https://github.com/Sleitnick/RbxCameraShaker?tab=readme-ov-file#camerashakeinstance) </span>, Sustain: <span style="color: teal;">boolean</span>)_ 
   
Shake the camera by providing a [CameraShakeInstance](https://github.com/Sleitnick/RbxCameraShaker?tab=readme-ov-file#camerashakeinstance). You can create a [CameraShakeInstance](https://github.com/Sleitnick/RbxCameraShaker?tab=readme-ov-file#camerashakeinstance) through the [CameraShakeInstance](https://github.com/Sleitnick/RbxCameraShaker?tab=readme-ov-file#camerashakeinstance)'s  `.new()` constructor or by using one of the presets.   
The `Sustain` parameter determines if the camera shake should be sustained or not.

```lua 
local NewCameraShakeInstance = ShiftUnlockedModule.CameraShakeInstance.new(5, 5, 0.2, 1.5)
local PresetCameraShakeInstance = ShiftUnlockedModule.CameraShakePresets.Explosion

-- One time explosion

ShiftUnlockedCamera:ShakeWithInstance(PresetCameraShakeInstance, false)

-- Sustained custom shake 

ShiftUnlockedCamera:ShakeWithInstance(NewCameraShakeInstance, true)
```

## Shake

_Camera:Shake(Magnitude: <span style="color: teal;">number</span>, Roughness: <span style="color: teal;">number</span>, Sustain: <span style="color: teal;">boolean?</span>,  FadeInTime: <span style="color: teal;">number?</span>, FadeOutTime: <span style="color: teal;">number?</span>, PositionInfluence: <span style="color: teal;">[Vector3](https://create.roblox.com/docs/reference/engine/datatypes/Vector3)?</span>, RotationInfluence: <span style="color: teal;">[Vector3](https://create.roblox.com/docs/reference/engine/datatypes/Vector3)?</span>)_ 
  
Shake the camera by passing the properties of a [CameraShakeInstance](https://github.com/Sleitnick/RbxCameraShaker?tab=readme-ov-file#camerashakeinstance) as arguments directly to the `:Shake` method, without the need to provide a predefined [CameraShakeInstance](https://github.com/Sleitnick/RbxCameraShaker?tab=readme-ov-file#camerashakeinstance). This is particularly useful in scenarios where a preconfigured shake is not applicable.
