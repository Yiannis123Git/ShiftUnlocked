# Camera Properties

All of these properties can be set during runtime, although some properties should only be set when the camera is disabled to ensure the best user experience.   
  
While there are some guardrails in place to prevent you from messing up setting up the camera properties, the module asumes you are passing correct value types.
  
!!! warning
    Any property that starts with the character `_` is not meant to be changed. 

-----

## CameraOffset
  
_Camera.CameraOffset: <span style="color: teal;">[Vector3](https://create.roblox.com/docs/reference/engine/datatypes/Vector3)</span>_   
  
The offset of the camera from our player's character, more specifically the offset from our player's character's humanoid root part, defaults to the legacy value of Roblox's native shift lock.

## FOV
  
_Camera.FOV: <span style="color: teal;">number</span>_  
  
The camera's [field of view](https://create.roblox.com/docs/reference/engine/classes/Camera#FieldOfView) can be set to any number between 0 and 120.

## PitchLimit 
  
_Camera.PitchLimit: <span style="color: teal;">number</span>_  

The maximum degrees to which the camera can be angled up and down. This value can be set to any number between 1 and 89.9.

## LockedIcon 
  
_Camera.LockedIcon: <span style="color: teal;">string</span>_  
  
The icon will be displayed when the [`MouseLocked`](#mouselocked) property is set to true. Setting this to nil disables the icon functionality on mobile and consoles.

## UnlockedIcon 
  
_Camera.UnlockedIcon: <span style="color: teal;">string</span>_  

The icon will be displayed when the [`MouseLocked`](#mouselocked) property is set to false. This functionality is only available on PC.

## AdjustedControllerIconDisplay

_Camera.AdjustedControllerIconDisplay: <span style="color: teal;">boolean</span>_ 

Roblox adjusts the mouse/cursor position when using a gamepad. If you want consistent icon behavior across all devices, set this property to true. If set to true, the mouse icon will be readjusted to reflect the PC position when playing on a gamepad. Due to technical limitations, this adjustment is only visual; the actual mouse will still be offset by Roblox. To account for this, please write your code accordingly. For example, if a gun relies on the mouse position, the bullets will not fire at the cursor position that the player can see but at the invisible cursor that is positioned above the visible cursor. This property would be more applicable to a "melee fighting" style of game rather than a shooter game.

## MouseLocked
  
_Camera.MouseLocked: <span style="color: teal;">boolean</span>_ 
  
Regardless of the property's name, it affects the camera across all platforms. Setting this value to false will unlock the mouse and set the camera to a static state, where no inputs will be accepted. This value is intended for scenarios where the player needs to interact with some form of UI, such as an inventory menu.

## ZoomLocked
  
_Camera.ZoomLocked: <span style="color: teal;">boolean</span>_  

Determines whether the player can control the camera's zoom functionality.   

## MaxZoom

_Camera.MaxZoom: <span style="color: teal;">number</span>_  
  
The maximum distance the camera can zoom away from its subject.
   
## MinZoom

_Camera.MinZoom: <span style="color: teal;">number</span>_  
  
The maximum distance the camera can zoom in towards its subject.

## StartZoom

_Camera.StartZoom: <span style="color: teal;">number</span>_  
  
The camera will always start from this value when it is enabled. This value must be between the minimum and maximum zoom values.

## ZoomStiffness

_Camera.ZoomStiffness: <span style="color: teal;">number</span>_  
    
Controls the speed of the camera zoom functionality as it adjusts to the desired zoom level.

## ZoomSpeedMouse

_Camera.ZoomSpeedMouse: <span style="color: teal;">number</span>_  

Controls the speed at which the desired zoom level is adjusted in response to mouse wheel inputs. The default value aligns with Roblox's default behavior.

## ZoomSpeedKeyboard

_Camera.ZoomSpeedKeyboard: <span style="color: teal;">number</span>_  
  
Controls the speed at which the desired zoom level is adjusted in response to keyboard inputs. The default value aligns with Roblox's default behavior.

## ZoomSpeedTouch

_Camera.ZoomSpeedTouch: <span style="color: teal;">number</span>_  
  
Controls the speed at which the desired zoom level is adjusted in response to touch inputs. The default value aligns with Roblox's default behavior.

## ZoomSensitivityCurvature

_Camera.ZoomSensitivityCurvature: <span style="color: teal;">number</span>_  
  
Determines how the zoom level changes in response to user input, making the zoom speed non-linear and dependent on the current zoom level.

## ZoomControllerKey

_Camera.ZoomControllerKey: <span style="color: teal;">[Enum.KeyCode](https://create.roblox.com/docs/reference/engine/enums/KeyCode) | nil</span>_  

The key responsible for zooming in and out on a gamepad. Setting this to `nil` will disable the zoom functionality on the gamepad.

## ZoomInKeyboardKey

_Camera.ZoomInKeyboardKey: <span style="color: teal;">[Enum.KeyCode](https://create.roblox.com/docs/reference/engine/enums/KeyCode) | nil</span>_  

The key responsible for zooming in on keyboard. Setting this to `nil` will disable the zoom in functionality on keyboard.

## ZoomOutKeyboardKey

_Camera.ZoomOutKeyboardKey: <span style="color: teal;">[Enum.KeyCode](https://create.roblox.com/docs/reference/engine/enums/KeyCode) | nil</span>_  

The key responsible for zooming out on keyboard. Setting this to `nil` will disable the zoom out functionality on keyboard.

## SyncZoom

_Camera.SyncZoom: <span style="color: teal;">boolean</span>_ 
  
When this property is set to true, the camera will attempt to sync its zoom with Roblox's default camera zoom when the camera gets enabled or disabled. Enabling this behavior will introduce yielding when disabling the camera via the [`SetEnabled`](CameraMethods.md#setenabled) method until the sync is achieved.

## MouseRadsPerPixel

_Camera.MouseRadsPerPixel: <span style="color: teal;">[Vector2](https://create.roblox.com/docs/reference/engine/datatypes/Vector2)</span>_     
  
Affects the sensitivity of mouse camera movement inputs.

## GamepadSensitivityModifier
  
_Camera.GamepadSensitivityModifier: <span style="color: teal;">[Vector2](https://create.roblox.com/docs/reference/engine/datatypes/Vector2)</span>_    

Affects the sensitivity of gamepad camera movement inputs.    

## TouchSensitivityModifier
  
_Camera.TouchSensitivityModifier: <span style="color: teal;">[Vector2](https://create.roblox.com/docs/reference/engine/datatypes/Vector2)</span>_    

Affects the sensitivity of touch camera movement inputs.    

## GamepadLowerKValue

_Camera.GamepadLowerKValue: <span style="color: teal;">number</span>_  
  
Controls the thumbstick input sensitivity for negative inputs: lower values result in more responsive extremes, while higher values provide smoother, more linear control.

## GamepadKValue

_Camera.GamepadKValue: <span style="color: teal;">number</span>_  
  
Controls the thumbstick input sensitivity for positive inputs: lower values result in more responsive extremes, while higher values provide smoother, more linear control.

## GamepadDeadzone

_Camera.GamepadDeadzone: <span style="color: teal;">number</span>_  
  
This specifies the range of gamepad input values near 0 that will be mapped to an output of 0 to prevent unintentional inputs.

## RaycastChannel 
  
_Camera.RaycastChannel: <span style="color: teal;">[Channel](https://yiannis123git.github.io/SmartRaycast/api/Channel) | nil</span>_ 

The [Channel](https://yiannis123git.github.io/SmartRaycast/api/Channel) that will be used for that camera's raycast operations. For more information, please visit SmartRaycast's [documentation page](https://yiannis123git.github.io/SmartRaycast/).

## ObstructionRange
  
_Camera.ObstructionRange: <span style="color: teal;">number</span>_   
  
If the camera moves closer to the player's character than this range, the character will start to become transparent for better camera visibility.

## RotateCharacter
  
_Camera.RotateCharacter: <span style="color: teal;">boolean</span>_   
  
Sets whether or not the Humanoid will automatically rotate to face in the direction the camera is looking.

## CorrectionReversion

_Camera.CorrectionReversion: <span style="color: teal;">boolean</span>_  
  
Whether or not camera collision corrections will be reverted gradually or instantly.

## CorrectionReversionSpeed

_Camera.CorrectionReversionSpeed: <span style="color: teal;">number</span>_  
  
The speed at which the camera's collision correction is reverted. This value is scaled based on the current [camera offset](#cameraoffset).

## TimeUntilCorrectionReversion

_Camera.TimeUntilCorrectionReversion: <span style="color: teal;">number</span>_ 
  
The time required for the camera correction reversal process to commence after collision corrections are no longer applied to the camera. Corrections to the camera's zoom will revert slightly more quickly than other types of corrections. This process is executed on a per-axis basis.

## VelocityOffset

_Camera.VelocityOffset: <span style="color: teal;">boolean</span>_
  
Determines whether the camera will "lag behind" at certain velocity speeds to make the camera movement feel more dynamic.

## AllowVelocityOffsetOnTeleport

_Camera.AllowVelocityOffsetOnTeleport: <span style="color: teal;">boolean</span>_
  
Whether or not the camera should treat the player's character teleportation as regular motion. The module tries its best to detect when teleportation occurs, but the ideal way to handle spikes in velocity due to teleportation is to manually set [`VelocityOffset`](#velocityoffset) to true or false accordingly during runtime, based on whether a teleport is about to be performed on the player's character. If you are planning to introduce your own logic to detect teleportation, then you should set this property to true.

## VelocityOffsetVelocityThreshold

_Camera.VelocityOffsetVelocityThreshold: <span style="color: teal;">number</span>_ 
  
The minimum camera movement velocity required to start applying the velocity offset.   

## VelocityOffsetFrequency

_Camera.VelocityOffsetFrequency: <span style="color: teal;">number</span>_ 
  
Governs the rate at which the camera's offset adjusts to match the current velocity.

## VelocityOffsetDamping

_Camera.VelocityOffsetDamping: <span style="color: teal;">number</span>_ 
  
The amplitude of oscillations as the velocity offset reaches its target.

## FreeCamMode
  
_Camera.FreeCamMode: <span style="color: teal;">boolean</span>_   
  
This property controls the current mode of the camera. Setting this property to true will disable the normal camera update process. The camera will rely on the  [`FreeCamCFrame`](#freecamcframe) property for its position and orientation. The camera can still be influenced via the camera shake functionality in this mode.

## FreeCamCFrame

_Camera.FreeCamCFrame: <span style="color: teal;">[CFrame](https://create.roblox.com/docs/reference/engine/datatypes/CFrame)</span>_ 
  
This property will be used to determine the camera's position and orientation when [`FreeCamMode`](#freecammode) is set to true. You can use this property to animate or statically position the camera during cutscenes.

  




