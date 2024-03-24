# Using the camera

## Enabling and disabling the camera

After we have finished adjusting our camera, we can enable it by doing the following.

```lua
ShiftUnlockedCamera:SetEnabled(true)
```

To disable the camera, simply pass false as the value.

```lua
ShiftUnlockedCamera:SetEnabled(false)
```

## Destroying the camera

After we finish using a camera object, we can destroy it to free up memory by doing the following.

```lua
ShiftUnlockedCamera:Destroy()
```