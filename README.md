# LABA HUB

A Roblox UI library — Obsidian x Rayfield design, built from scratch. No external library, no `loadstring` of third-party code; every pixel is `Instance.new`.

## Usage

```lua
local UI = loadstring(readfile("LABAHUB.luau"))()

local win = UI:CreateWindow({
    Title = "LABA HUB",
    Size = UDim2.fromOffset(560, 420),
    Intro = { Title = "LABA HUB", Subtitle = "Loading scripts...", Duration = 2.5 },
})

local Main = win:AddTab("Main")
Main:AddToggle({ Name = "Noclip", Value = false, Key = "Noclip", Callback = function(v) end })
Main:AddSlider({ Name = "WalkSpeed", Min = 16, Max = 100, Step = 5, Value = 16, Key = "WalkSpeed", Callback = function(v) end })
Main:AddButton({ Name = "Reset character", Callback = function() end })
Main:AddDropdown({ Name = "Selection", Options = { "A", "B", "C" }, Key = "Selection", Callback = function(o) end })
```

## Controls

- `Toggle`, `Slider`, `Button`, `TextBox`, `Paragraph`, `Segmented`, `List`, `Dropdown` (single + multi), `Label`
- `el:Get()` / `el:Set(v)` on most controls; `el:Value()` / `el:SetOptions(list)` on Dropdown
- Config system: `UI.Config` — `Create` / `Load` / `Delete` / `List`, JSON-backed, AutoLoad support
- `win:Notify(title, text, duration, style)` — info / success / warning / error
- `win:Destroy()` full teardown
- Window minimize-to-pill morph, draggable title bar

## License

See `LICENSE`. Personal / non-commercial use only. No rebranding — do not redistribute this code under a different name or author.
