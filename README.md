# cove
**[Documentation](https://panduh.gitbook.io/panduh-docs
)**

Cove ported to work as a library, featuring much more than just the UI segment.
<img width="587" height="460" alt="image" src="https://github.com/user-attachments/assets/8929b5df-7b67-4b50-972c-f663ec44684a" />

---

# cover

Icy menu for Roblox (book open / close, snow, frost, loader + key) with a full **weather and environment** system. Everything is client-side and visual only: it changes what you see, nothing else.

## Run it

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ccoovveerr/cover/master/cover.lua"))()
```

The key is `test`. Press **Insert** to open / close the menu. Running it again replaces the old copy cleanly.

### In Roblox Studio

`game:HttpGet` only exists in executors, so in Studio cover runs as a LocalScript in `StarterPlayer > StarterPlayerScripts`. To install (or update) it, **stop playing** and paste this into the command bar:

```lua
local h=game:GetService("HttpService") h.HttpEnabled=true local f=game:GetService("StarterPlayer").StarterPlayerScripts for _,n in ipairs({"cover","CoverMenuTest"}) do local o=f:FindFirstChild(n) if o then o:Destroy() end end local src=h:GetAsync("https://raw.githubusercontent.com/ccoovveerr/cover/master/cover.lua",true) local s=Instance.new("LocalScript") s.Name="cover" game:GetService("ScriptEditorService"):UpdateSourceAsync(s,function() return src end) s.Parent=f print("cover installed ("..#s.Source.." chars), press Play")
```

Then press Play. It turns on **Allow HTTP Requests** for the place (needed to download the file) and replaces any older copy. It uses `ScriptEditorService` because Roblox won't let code set a script's `Source` past 200,000 characters directly, and `cover.lua` is bigger than that.

After a push, the raw link can take a few minutes to serve the new version.

## Tabs

| Tab | Sections |
|---|---|
| general | example controls |
| player | trail, flex (watch, chain, aura) |
| weather | weather presets, environment (time of day), configs, particles, options |
| sky | sky, clouds, fog, atmosphere |
| light | lighting, ground, colour correction, visual effects |
| menu | toggle key, unload |

### Weather presets

clear, sakura, snow, blizzard, rain, heavy rain, autumn, sunset, night, foggy morning.

A preset moves everything at once over the **transition** time: time of day, lighting, atmosphere, clouds, sky, colour correction, bloom, sun rays, wind, ground colours and particles. Every slider updates to the preset's values, so you can keep tweaking from there.

- **sakura**: pink sky + air, falling petals, butterflies, a few fireflies, fresh green grass
- **snow / blizzard**: snowfall, ground and grass turn white, cold grade; blizzard adds strong gusting wind, sideways snow drift and a whiteout
- **rain / heavy rain**: rain with splashes, ground mist, wet shiny surfaces, overcast clouds; heavy rain adds lightning bolts, flashes and thunder
- **autumn**: falling leaves, gusts, golden-hour light, warm grass

### Good to know

- **Fog style**: *soft* uses Roblox's Atmosphere (density + haze). *distance* uses start / end fog. Roblox only draws distance fog when there is no Atmosphere, so the atmosphere is set aside while distance fog is on, and comes back after.
- Moving a slider in a section that's switched off switches that section on.
- **clear view in menu** (weather > options) turns off the menu's blur / cold tint / snow, so you can watch changes live with the menu open.
- **quality** and **render distance** control how many particles there are and how far out they go. **hide indoors** stops rain and snow under a roof.
- **configs** save to `cover_environment.json` in your executor's workspace folder. Where files can't be written (Studio), they're kept until you leave.
- **reset everything** fades back to the game's own look. **unload** puts everything back instantly.

## Checking it works

1. Pick each preset: the whole scene should change over the transition time, with no snapping.
2. After a preset, drag a few sliders: changes should glide in, and the preset look should stay otherwise.
3. Set fog style to *distance* and move start / end, then back to *soft*: the atmosphere returns.
4. Turn **weather particles** off and on, and change **quality**: particles should drop / rise without stutter.
5. Press **reset everything**: lighting, sky, fog, clouds, wind and ground colours fade back to how the game looked.
6. Press **unload**: the menu, effects and every weather object are gone, and the game looks untouched.

## Files

| Path | What it is |
|---|---|
| `cover.lua` | the whole menu + weather system |
| `loader.lua` | the one-line loadstring |
| `assets/` | images, sounds and models (`pinksky.rbxm` is the sakura sky) |

Roblox can't load an image or sound straight from a GitHub link. Upload it to Roblox (Creator Hub > Development Items) and use its `rbxassetid://<id>`.
