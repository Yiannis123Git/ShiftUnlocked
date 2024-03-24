# Setting up the camera in your project

## Creating a new camera object
Creating a new camera object is straightforward. Simply require the ShiftUnlocked module and use the [.new()](CameraMethods.md#new) function.

``` lua
-- First lets require our module by doing the folowing

local ShiftUnlockedModule = require(PathToOurModule.shiftunlocked)

-- Now we can create a camera object 

local ShiftUnlockedCamera = ShiftUnlocked.new()
```

## Adjusting the camera
It is good practice to set up the camera properties to suit our needs before we actually enable the camera. The camera will work fine without any setup, but it is recommended to make some adjustments before enabling the camera. For a full list of the adjustments that can be made, refer to the [camera's properties](CameraProperties.md).
  
Making adjustments is easy; we can set the properties of the camera to meet our project's needs. 

```lua
-- Let's adjust the camera's maximum zoom value, as the default value is a bit too large

ShiftUnlockedCamera.MaxZoom = 100 

-- Actually, let's just disable the zoom functionality completely

ShiftUnlockedCamera.ZoomLocked = true 
```
  
### Changing the RaycastChannel
A beneficial adjustment to consider is modifying the camera's raycast [Channel](https://yiannis123git.github.io/SmartRaycast/api/Channel). This is because ShiftUnlocked is quite strict with its collision detection to ensure an immersive environment. However, camera clipping through an object is not always a bad thing. At times, small or insignificant objects like a mug on a coffee table or a street lamp could be ignored to improve user experience. 
  
The easiest way to achieve this is by using a plugin like [Tag Editor](https://devforum.roblox.com/t/tag-editor-plugin/101133), which can enable you to tag objects you want to ignore with the [Collection Service](https://create.roblox.com/docs/reference/engine/classes/CollectionService). (You don't have to manually tag each object.)
  
After we have tagged our objects using the collection service, we can proceed with the following steps through code:

```lua
local SmartRaycast = require(PathToOurModule.smartraycast)

local OurChannel = SmartRaycast.CreateChannel(
    "ShiftUnlocked",
    {"OurCollectionServiceTag"},
    nil,
    nil,
    Enum.RaycastFilterType.Exclude, 
    -- ...
)

ShiftUnlockedCamera.RaycastChannel = OurChannel

```

This a simple implementation, you can introduce more paramaters for your [Channel](https://yiannis123git.github.io/SmartRaycast/api/Channel) as needed.
