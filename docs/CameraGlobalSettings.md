# Global Settings
These settings don't just affect individual camera instances; they affect the module as a whole.

-------

## GCWarn 

_shiftUnlocked.GCWarn: <span style="color: teal;">boolean</span>_   
  
Whether the module should issue a warning when there is more than one camera instance in your game.

## GlobalRaycastChannelName

_shiftUnlocked.GlobalRaycastChannelName: <span style="color: teal;">string</span>_
  
The name of the SmartRaycast [Channel](https://yiannis123git.github.io/SmartRaycast/api/Channel) to be used as a fallback if a camera's channel is not set.

## AutoExcludeChars

_shiftUnlocked.AutoExcludeChars: <span style="color: teal;">boolean</span>_  

Whether or not the module should handle the exclusion of player characters from camera collision detection by adding them to the raycast [Channel](https://yiannis123git.github.io/SmartRaycast/api/Channel)'s filter list. If you are using an include filter list for your channel, this feature will be disabled.
## CameraShakeDefaultPosInfluence

_shiftUnlocked.CameraShakeDefaultPosInfluence: <span style="color: teal;">[Vector3](https://create.roblox.com/docs/reference/engine/datatypes/Vector3)</span>_
  
The `PositionInfluence` vector is used as a fallback when the `PositionInfluence` argument of the [`:Shake`](CameraMethods.md#shake) camera method is `nil`.

## CameraShakeDefaultRotInfluence

_shiftUnlocked.CameraShakeDefaultRotInfluence: <span style="color: teal;">[Vector3](https://create.roblox.com/docs/reference/engine/datatypes/Vector3)</span>_
  
The `RotationInfluence` vector is used as a fallback when the `RotationInfluence` argument of the [`:Shake`](CameraMethods.md#shake) camera method is `nil`.

## CameraShakeInstance
  
_shiftUnlocked.CameraShakeInstance: <span style="color: teal;">table</span>_
    
This setting just points to the CameraShakeInstance module for easy use.

!!! warning
    This setting is not intended to be modified.

## CameraShakePresets
  
_shiftUnlocked.CameraShakePresets: <span style="color: teal;">table</span>_
  
This setting points to the CameraShakePresets module for easy use. You can change this value to point to your own presets if convenient.