--[[
	cover  -  menu + frost / snow backdrop + weather / environment system (visual only)

	HOW TO RUN
	  * Loadstring:  loadstring(game:HttpGet("https://raw.githubusercontent.com/ccoovveerr/cover/master/cover.lua"))()
	                 (it returns the menu library, so  local cover = loadstring(...)()  works too)
	  * Roblox Studio: put it in a LocalScript inside StarterPlayer > StarterPlayerScripts.

	Press INSERT to show / hide the menu. Drag it by the header or footer (it stops at the screen edges).
	Running it again replaces the old copy cleanly (it unloads the previous one first).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

if _G.__cover_unload then
	pcall(_G.__cover_unload)
end

local local_player = Players.LocalPlayer
local gui_parent = local_player and local_player:WaitForChild("PlayerGui") or game:GetService("CoreGui")

-- =====================================================================
-- > ( frost fx )  -  snow, frost, blur, vignette, cold colour grade
-- =====================================================================

local function create_frost_fx(parent, start_open)
	-- settings
	local BLUR_SIZE      = 8      -- world blur strength when open
	local FROST_TIME     = 2.6    -- seconds for frost to creep in after opening
	local FROST_AMOUNT   = 1      -- frost reach (0.6 = light, 1.5 = heavy)
	local BACKDROP_ALPHA = 0.55   -- 0 = solid black, 1 = invisible
	local SNOW_COUNT     = 160    -- 160 = default density
	local FADE_TIME      = 0.25   -- fade-in when opening
	local FADE_OUT_TIME  = 1.0    -- fade-out when closing (matches the book close)

	local fx_connections = {}

	local function new(class, props, p)
		local o = Instance.new(class)
		for k, v in pairs(props) do o[k] = v end
		o.Parent = p
		return o
	end

	-- cleanup on re-run
	local old = parent:FindFirstChild("MenuFX")
	if old then old:Destroy() end
	for _, name in ipairs({ "MenuBlur", "MenuCold" }) do
		local o = Lighting:FindFirstChild(name)
		if o then o:Destroy() end
	end

	local gui = new("ScreenGui", {
		Name = "MenuFX", IgnoreGuiInset = true, ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 50, -- below the menu (999)
	}, parent)

	-- world blur (blurs the 3D game behind the UI)
	local blur = new("BlurEffect", { Name = "MenuBlur", Size = BLUR_SIZE, Enabled = true }, Lighting)

	-- backdrop: translucent icy tint so the blurred game shows through, deep cold navy at
	-- the top fading to a pale frozen steel-blue near the ground
	local backdrop = new("Frame", {
		Name = "Backdrop", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = BACKDROP_ALPHA,
		BorderSizePixel = 0,
	}, gui)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(4, 10, 20)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(12, 26, 44)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(38, 62, 92)),
		}),
	}, backdrop)

	-- edge shading helper: smooth gradient strip hugging one screen edge
	local fadeables = {} -- { instance, transparency when open }
	local function edgeShade(p, side, depth, color, edgeT, z)
		local f = new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z }, p)
		if side == "L" then
			f.Size = UDim2.fromScale(depth, 1)
		elseif side == "R" then
			f.AnchorPoint = Vector2.new(1, 0); f.Position = UDim2.fromScale(1, 0); f.Size = UDim2.fromScale(depth, 1)
		elseif side == "T" then
			f.Size = UDim2.fromScale(1, depth)
		else
			f.AnchorPoint = Vector2.new(0, 1); f.Position = UDim2.fromScale(0, 1); f.Size = UDim2.fromScale(1, depth)
		end
		new("UIGradient", {
			Rotation = ({ L = 0, R = 180, T = 90, B = -90 })[side],
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0,    edgeT),
				NumberSequenceKeypoint.new(0.3,  edgeT + (1 - edgeT) * 0.45),
				NumberSequenceKeypoint.new(0.65, edgeT + (1 - edgeT) * 0.85),
				NumberSequenceKeypoint.new(1,    1),
			}),
		}, f)
		return f
	end


	-- snow -------------------------------------------------------------
	local snowLayer = new("Frame", {
		Name = "Snow", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true,
	}, backdrop)

	local rng = Random.new()
	local flakes = {}
	local SNOW_DENSITY = SNOW_COUNT / 160

	-- everything snowy registers here so it can fade smoothly as one: { frame, transparency when fully shown }
	local fadeParts = {}
	local function fadeable(frame, base)
		fadeParts[#fadeParts + 1] = { frame, base }
		return frame
	end
	local function applyFade(k) -- k: 0 = gone, 1 = fully shown
		for _, p in ipairs(fadeParts) do
			p[1].BackgroundTransparency = 1 - (1 - p[2]) * k
		end
	end

	-- snow: far away it's just tiny specks (that's how distant snow really looks); closer in
	-- it's real six-armed snowflakes, each one with its own randomly generated design.
	-- far -> near. depth drives parallax, wind strength and brightness
	local LAYERS = {
		{ count = 150, size = {1, 1.8},   stretch = {1.2, 1.5}, speed = {14, 26},  alpha = {0.45, 0.75}, sway = {3, 8},   flutter = 0.6, depth = 0.15,
		  color = Color3.fromRGB(200, 212, 228), kind = "dot" },
		{ count = 80,  size = {2.5, 4},   speed = {28, 50},  alpha = {0.25, 0.45}, sway = {8, 18},  flutter = 1.2, depth = 0.45,
		  color = Color3.fromRGB(228, 238, 250), kind = "star" },
		{ count = 28,  size = {5, 7.5},   speed = {48, 78},  alpha = {0.08, 0.28}, sway = {14, 30}, flutter = 2.0, depth = 0.8,
		  color = Color3.fromRGB(244, 248, 255), kind = "flake" },
		{ count = 6,   size = {8.5, 11},  speed = {85, 115}, alpha = {0.5, 0.65},  sway = {20, 36}, flutter = 2.6, depth = 1.0,
		  color = Color3.fromRGB(240, 246, 255), kind = "flake" }, -- a few big ones right by the camera
	}

	-- soft round speck
	local function blob(p, sx, sy, px, py, color, transp)
		local c = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(px, py),
			Size = UDim2.fromScale(sx, sy), BackgroundColor3 = color, BackgroundTransparency = transp,
			BorderSizePixel = 0, ZIndex = 3,
		}, p)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, c)
		return fadeable(c, transp)
	end

	-- one straight ice segment from (x1, y1) to (x2, y2), in 0..1 flake space
	local function seg(p, x1, y1, x2, y2, color, transp, thick)
		local dx, dy = x2 - x1, y2 - y1
		return fadeable(new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2),
			Size = UDim2.new(math.sqrt(dx * dx + dy * dy), 0, 0, thick or 1),
			Rotation = math.deg(math.atan2(dy, dx)),
			BackgroundColor3 = color, BackgroundTransparency = transp, BorderSizePixel = 0, ZIndex = 3,
		}, p), transp)
	end

	-- a real snowflake: six identical arms (that symmetry is what makes it read as a
	-- snowflake), but every flake gets its own random design
	local function buildFlake(root, kind, color, transp, px)
		local thick = px >= 20 and 2 or 1
		local fine = math.min(transp + 0.12, 0.95)   -- side branches a touch fainter than the arms
		local branches, tipPlate, hub = {}, false, false
		if kind == "star" then
			if rng:NextNumber() < 0.5 then branches[1] = { rng:NextNumber(0.5, 0.65), rng:NextNumber(0.18, 0.28) } end
		else
			local n = rng:NextInteger(2, 3)
			for i = 1, n do
				local at = 0.25 + (i - 1) * (0.55 / n) + rng:NextNumber(-0.04, 0.04) -- where on the arm
				branches[i] = { at, rng:NextNumber(0.18, 0.4) * (1 - at * 0.45) }   -- outer ones shorter
			end
			tipPlate = rng:NextNumber() < 0.4
			hub = rng:NextNumber() < 0.6
		end
		local spread = math.rad(rng:NextNumber(52, 64)) -- angle of the side branches
		local R = 0.5
		for k = 0, 2 do -- three full-length bars crossing = six arms
			local a = math.rad(k * 60)
			seg(root, 0.5 - math.cos(a) * R, 0.5 - math.sin(a) * R, 0.5 + math.cos(a) * R, 0.5 + math.sin(a) * R, color, transp, thick)
		end
		for k = 0, 5 do
			local a = math.rad(k * 60)
			local ca, sa = math.cos(a), math.sin(a)
			for _, br in ipairs(branches) do
				local bx, by = 0.5 + ca * R * br[1], 0.5 + sa * R * br[1]
				for _, s in ipairs({ -1, 1 }) do
					local ba = a + s * spread
					seg(root, bx, by, bx + math.cos(ba) * R * br[2], by + math.sin(ba) * R * br[2], color, fine)
				end
			end
			if tipPlate then
				blob(root, 0.1, 0.1, 0.5 + ca * R * 0.96, 0.5 + sa * R * 0.96, color, fine)
			end
		end
		if hub then
			blob(root, 0.2, 0.2, 0.5, 0.5, color, math.min(transp + 0.2, 0.95))
		end
	end

	local function place(f, anywhere)
		local L = f.layer
		local vw, vh = snowLayer.AbsoluteSize.X, snowLayer.AbsoluteSize.Y
		f.speed = rng:NextNumber(L.speed[1], L.speed[2])
		f.sway  = rng:NextNumber(L.sway[1], L.sway[2])
		f.freq  = rng:NextNumber(0.25, 0.9)
		f.phase = rng:NextNumber(0, math.pi * 2)
		f.seed  = rng:NextNumber(0, 1000)
		f.x     = rng:NextNumber(-0.05, 1.05) * vw
		f.y     = anywhere and rng:NextNumber(0, vh) or -f.size * 1.5
	end

	while snowLayer.AbsoluteSize.X < 1 do RunService.RenderStepped:Wait() end

	for _, L in ipairs(LAYERS) do
		for _ = 1, math.floor(L.count * SNOW_DENSITY + 0.5) do
			local size    = rng:NextNumber(L.size[1], L.size[2])
			local stretch = L.stretch and rng:NextNumber(L.stretch[1], L.stretch[2]) or 1 -- flakes stay square
			local transp  = rng:NextNumber(L.alpha[1], L.alpha[2])
			local root = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size * stretch),
				BackgroundTransparency = 1, ZIndex = math.floor(L.depth * 10),
			}, snowLayer)
			local f = { root = root, layer = L, size = size }
			if L.kind == "dot" then
				blob(root, 1, 1, 0.5, 0.5, L.color, transp)
			else
				buildFlake(root, L.kind, L.color, transp, size)
				-- flakes turn slowly as they fall, each at its own speed and direction
				f.spin = rng:NextNumber(12, 40) * (rng:NextNumber() < 0.5 and -1 or 1)
				f.rot = rng:NextNumber(0, 60)
				root.Rotation = f.rot
			end
			place(f, true)
			table.insert(flakes, f)
		end
	end

	-- cold mist: slow banks of freezing fog drifting low across the screen ----
	-- Each bank is ONE smooth piece: a CanvasGroup fades it at the sides, and the frame inside
	-- fades it top-to-bottom. (The old version stacked thin strips, and where strips met they
	-- overlapped by a pixel - those were the faint horizontal lines across the screen.)
	local MIST_AMOUNT = 1   -- 0 = no mist, 2 = thick
	local mistLayer = new("Frame", {
		Name = "Mist", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2,
	}, backdrop)
	local MIST_SIDES = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.4),
		NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.75, 0.4), NumberSequenceKeypoint.new(1, 1),
	})
	local MIST_LOW = NumberSequence.new({   -- thick near the ground, wispy on top, soft at the very bottom too
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.7),
		NumberSequenceKeypoint.new(0.72, 0.25), NumberSequenceKeypoint.new(0.88, 0.15), NumberSequenceKeypoint.new(1, 1),
	})
	local MIST_HIGH = NumberSequence.new({  -- floating band, densest in the middle
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.45),
		NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.7, 0.45), NumberSequenceKeypoint.new(1, 1),
	})
	local mist = {}
	for m = 1, 6 do
		local low = m <= 4 -- four low banks hugging the ground, two faint ones higher up
		local patch = new("CanvasGroup", {
			AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1, GroupTransparency = 1, ZIndex = 2,
			Size = UDim2.fromScale(rng:NextNumber(0.5, 0.95), low and rng:NextNumber(0.3, 0.46) or rng:NextNumber(0.12, 0.2)),
		}, mistLayer)
		new("UIGradient", { Transparency = MIST_SIDES }, patch) -- soft left / right edges for the whole bank
		local body = new("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(196, 216, 240),
			BorderSizePixel = 0, ZIndex = 2,
		}, patch)
		new("UIGradient", { Rotation = 90, Transparency = low and MIST_LOW or MIST_HIGH }, body)
		mist[m] = {
			frame = patch, x = rng:NextNumber(-0.5, 1.5),
			speed = rng:NextNumber(0.008, 0.02) * (rng:NextNumber() < 0.5 and -1 or 1),
			-- low banks always hang past the bottom of the screen (even with their bob), so their
			-- bottom edge is never visible - that edge was the "blue line" near the bottom
			y = low and rng:NextNumber(1.08, 1.14) or rng:NextNumber(0.55, 0.78),
			seed = rng:NextNumber(0, 100), density = low and rng:NextNumber(0.2, 0.34) or rng:NextNumber(0.07, 0.13),
		}
	end
	local function updateMist(dt, clock, k)
		for _, m in ipairs(mist) do
			m.x += m.speed * dt
			if m.x > 1.5 then m.x -= 2 elseif m.x < -0.5 then m.x += 2 end -- wraps off-screen
			m.frame.Position = UDim2.fromScale(m.x, m.y + math.noise(clock * 0.1, m.seed) * 0.02)
			local a = m.density * MIST_AMOUNT * k * math.clamp(0.6 + math.noise(clock * 0.15, m.seed + 5) * 0.8, 0.2, 1)
			m.frame.GroupTransparency = 1 - math.clamp(a, 0, 1)
		end
	end

	-- freezing: cold colour grade + frost creeping in from the edges --
	local cold = new("ColorCorrectionEffect", { Name = "MenuCold" }, Lighting)
	local COLD_ON  = { TintColor = Color3.fromRGB(198, 220, 255), Saturation = -0.48, Contrast = 0.1, Brightness = -0.02 }
	local COLD_OFF = { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0, Brightness = 0 }
	for k, v in pairs(COLD_ON) do cold[k] = v end
	local coldInfo = TweenInfo.new(FROST_TIME * 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

	local ICE = Color3.fromRGB(214, 234, 255)
	local frostLayer = new("Frame", {
		Name = "Frost", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3,
	}, backdrop)

	-- icy glaze along the edges
	local frostGlaze = {}
	for _, s in ipairs({ "L", "R", "T", "B" }) do
		local lr = (s == "L" or s == "R")
		table.insert(frostGlaze, edgeShade(frostLayer, s, (lr and 0.08 or 0.11) * FROST_AMOUNT,
			Color3.fromRGB(185, 212, 245), 0.84, 3))
	end

	-- frosted haze filling each corner (smooth diagonal fade, sits behind the fronds)
	local CORNER_REACH = 1   -- corner frost size multiplier
	do
		local S = 210 * CORNER_REACH * FROST_AMOUNT
		for _, c in ipairs({ { 0, 0, 45 }, { 1, 0, 135 }, { 1, 1, 225 }, { 0, 1, 315 } }) do
			local haze = new("Frame", {
				AnchorPoint = Vector2.new(c[1], c[2]), Position = UDim2.fromScale(c[1], c[2]),
				Size = UDim2.fromOffset(S, S), BackgroundColor3 = Color3.fromRGB(205, 222, 242),
				BorderSizePixel = 0, ZIndex = 3,
			}, frostLayer)
			new("UIGradient", { -- subtle: just a hint of fogged glass right in the corner
				Rotation = c[3],
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0,    0.7),
					NumberSequenceKeypoint.new(0.15, 0.82),
					NumberSequenceKeypoint.new(0.32, 0.94),
					NumberSequenceKeypoint.new(0.5,  1),
					NumberSequenceKeypoint.new(1,    1),
				}),
			}, haze)
			table.insert(frostGlaze, haze)
		end
	end

	-- frost: thin 1px ice needles grown into a MIX of crystal shapes --------------
	-- (every frond being the same symmetric fern is what made it look like rows of pine twigs)
	local FROST_SPACING = 95   -- average px between frost spots along an edge (lower = more frost)
	local EDGE_REACH    = 1    -- size of the frost along the sides
	local CORNER_FRONDS = 3    -- extra fronds in each corner
	local FROST_MOTION  = 1    -- how much each frond creeps in / out (0 = still, 2 = lots)

	local frostBars = {}   -- { frame, transparency when grown, order, frond, shown transparency }
	local fronds = {}      -- each frond breathes on its own rhythm
	local curFrond
	local W, H = frostLayer.AbsoluteSize.X, frostLayer.AbsoluteSize.Y

	local function addNeedle(x1, y1, x2, y2, order)
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		local b = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(((x1 + x2) / 2) / W, ((y1 + y2) / 2) / H),
			Size = UDim2.fromOffset(len + 2, 1),
			Rotation = math.deg(math.atan2(dy, dx)),
			BackgroundColor3 = ICE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4,
		}, frostLayer)
		local target = math.clamp(0.58 + order * 0.045 + rng:NextNumber(-0.05, 0.05), 0.55, 0.94)
		table.insert(frostBars, { b, target, order, curFrond, 2 })
		if order > curFrond.maxOrder then curFrond.maxOrder = order end
	end

	-- fern: curving stem with barbs; each side decided separately, uneven lengths and angles
	local function fern(x, y, ang, len, depth, order, curve, decay)
		if depth <= 0 or len < 1.6 then return end
		local x2, y2 = x + math.cos(ang) * len, y + math.sin(ang) * len
		addNeedle(x, y, x2, y2, order)
		fern(x2, y2, ang + curve + rng:NextNumber(-0.18, 0.18), len * decay, depth - 1, order + 1,
			curve + rng:NextNumber(-0.03, 0.03), decay)
		if depth > 2 then
			for _, side in ipairs({ 1, -1 }) do
				if rng:NextNumber() < 0.7 then
					fern(x2, y2, ang + side * rng:NextNumber(0.5, 1.2), len * rng:NextNumber(0.3, 0.6),
						depth - rng:NextInteger(2, 4), order + 1, -curve * 0.5 + rng:NextNumber(-0.05, 0.05), decay)
				end
			end
		end
		if depth > 4 and rng:NextNumber() < 0.15 then
			local s = rng:NextNumber() < 0.5 and -1 or 1
			fern(x2, y2, ang + s * rng:NextNumber(0.35, 0.75), len * 0.75, depth - 2, order + 1, -curve, decay)
		end
	end

	-- dendrite: spiky, forks into two now and then, no barbs
	local function dendrite(x, y, ang, len, depth, order)
		if depth <= 0 or len < 1.6 then return end
		local x2, y2 = x + math.cos(ang) * len, y + math.sin(ang) * len
		addNeedle(x, y, x2, y2, order)
		if rng:NextNumber() < 0.35 then
			local s = rng:NextNumber(0.35, 0.8)
			dendrite(x2, y2, ang + s, len * rng:NextNumber(0.6, 0.85), depth - 1, order + 1)
			dendrite(x2, y2, ang - s * rng:NextNumber(0.5, 1.2), len * rng:NextNumber(0.6, 0.85), depth - 1, order + 1)
		else
			dendrite(x2, y2, ang + rng:NextNumber(-0.35, 0.35), len * rng:NextNumber(0.75, 0.92), depth - 1, order + 1)
		end
	end

	-- hoar-frost spikes: a small burst of straight needles from one point
	local function spikes(x, y, ang, len)
		for _ = 1, rng:NextInteger(3, 6) do
			local a = ang + rng:NextNumber(-0.9, 0.9)
			local l = len * rng:NextNumber(0.4, 1)
			local tx, ty = x + math.cos(a) * l, y + math.sin(a) * l
			addNeedle(x, y, tx, ty, 0)
			if rng:NextNumber() < 0.5 then
				local b = a + (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(0.4, 0.8)
				addNeedle(tx, ty, tx + math.cos(b) * l * 0.35, ty + math.sin(b) * l * 0.35, 1)
			end
		end
	end

	local function frond(x, y, ang, size)
		curFrond = {
			maxOrder = 1, front = 0,
			speed = rng:NextNumber(0.2, 0.65), seed = rng:NextNumber(0, 1000),
			pull = rng:NextNumber(0.2, 0.6),   -- how far back this one creeps
		}
		fronds[#fronds + 1] = curFrond
		local kind = rng:NextNumber()
		if kind < 0.55 then
			fern(x, y, ang, 10 * size, size > 1.1 and 8 or (size > 0.7 and 7 or 6), 0,
				rng:NextNumber(-0.12, 0.12), rng:NextNumber(0.8, 0.9))
		elseif kind < 0.85 then
			dendrite(x, y, ang, 9 * size, 7, 0)
		else
			spikes(x, y, ang, 14 * size)
		end
	end

	-- along every side: random spacing (bunches and gaps), patchy sizes, random lean
	local edgeSeed = rng:NextNumber(0, 100)
	local function edgeFrost(length, at, side)
		local pos = rng:NextNumber(0, FROST_SPACING)
		while pos < length do
			local t = pos / length
			local x, y, ang = at(t)
			local patch = math.clamp(0.5 + math.noise(pos / 300, edgeSeed + side * 13) * 1.2, 0, 1)
			local nearCorner = math.max(0, 1 - math.min(pos, length - pos) / 200)
			if patch > 0.1 or nearCorner > 0 then
				local size = (0.4 + patch * 0.8 + nearCorner * 0.4) * rng:NextNumber(0.6, 1.4) * EDGE_REACH * FROST_AMOUNT
				frond(x, y, ang + rng:NextNumber(-0.9, 0.9), size)
				if rng:NextNumber() < 0.3 then -- sometimes a second one right next to it
					local x2, y2 = at(math.clamp(t + rng:NextNumber(-12, 12) / length, 0, 1))
					frond(x2, y2, ang + rng:NextNumber(-0.9, 0.9), size * rng:NextNumber(0.5, 0.9))
				end
			end
			pos += FROST_SPACING * rng:NextNumber(0.3, 1.8)
		end
	end
	edgeFrost(W, function(t) return t * W, -2, math.pi / 2 end, 1)       -- top, growing down
	edgeFrost(W, function(t) return t * W, H + 2, -math.pi / 2 end, 2)   -- bottom, growing up
	edgeFrost(H, function(t) return -2, t * H, 0 end, 3)                 -- left, growing right
	edgeFrost(H, function(t) return W + 2, t * H, math.pi end, 4)        -- right, growing left

	-- corners: a few slightly bigger ones so they're a bit denser, not a web
	for _, c in ipairs({ { 0, 0, 1, 1 }, { W, 0, -1, 1 }, { 0, H, 1, -1 }, { W, H, -1, -1 } }) do
		local cx, cy, dx, dy = c[1], c[2], c[3], c[4]
		for _ = 1, CORNER_FRONDS do
			local along = rng:NextNumber(0, 70) * CORNER_REACH
			local horiz = rng:NextNumber() < 0.5
			frond(horiz and (cx + dx * along) or (cx - dx * 2), horiz and (cy - dy * 2) or (cy + dy * along),
				math.atan2(dy, dx) + rng:NextNumber(-0.8, 0.8), rng:NextNumber(1.1, 1.5) * CORNER_REACH * FROST_AMOUNT)
		end
	end

	-- glints: little points of light catching on the ice, twinkling at random
	local glints = {}
	for _ = 1, 45 do
		local fb = frostBars[rng:NextInteger(1, #frostBars)]
		local holder = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = fb[1].Position, Size = UDim2.fromOffset(7, 7),
			BackgroundTransparency = 1, Rotation = rng:NextNumber(0, 90), ZIndex = 5,
		}, frostLayer)
		local parts = {}
		for _, sz in ipairs({ { 1, 1 / 7 }, { 1 / 7, 1 } }) do -- tiny 4-point star
			parts[#parts + 1] = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(sz[1], sz[2]), BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5,
			}, holder)
		end
		glints[#glints + 1] = { parts = parts, bar = fb, speed = rng:NextNumber(0.4, 1.3), phase = rng:NextNumber(0, 6.3) }
	end

	local frostStart, frostReveal = os.clock(), 0

	-- r = how far the initial freeze has got (0..1)
	local function updateFrost(r, clock)
		local e = 1 - (1 - r) ^ 2
		-- every frond creeps in and out on its own slow, irregular rhythm (never in sync)
		for _, f in ipairs(fronds) do
			local n = math.clamp(0.5 + math.noise(clock * f.speed, f.seed) * 1.4, 0, 1)
			f.front = e * (f.maxOrder + 1) * math.max(0, 1 - f.pull * FROST_MOTION * n)
		end
		for _, fb in ipairs(frostBars) do
			local amt = math.clamp(fb[4].front - fb[3], 0, 1)
			local t = 1 - (1 - fb[2]) * amt
			if math.abs(t - fb[5]) > 0.01 then -- only touch needles that changed
				fb[5] = t
				fb[1].BackgroundTransparency = t
			end
		end
		-- glints only sparkle on ice that's currently grown in
		for _, g in ipairs(glints) do
			local vis = math.clamp((1 - g.bar[5]) / (1 - g.bar[2]), 0, 1)
			local tw = math.max(0, math.sin(clock * g.speed + g.phase)) ^ 12
			local a = 1 - tw * 0.9 * vis
			for _, p in ipairs(g.parts) do p.BackgroundTransparency = a end
		end
		-- edge glaze slowly breathes
		local b = math.clamp(0.5 + 0.4 * math.sin(clock * 0.85) + 0.2 * math.noise(clock * 0.35, 9.1), 0, 1)
		local g = 1 - e * (0.6 + 0.4 * b)
		for _, gl in ipairs(frostGlaze) do gl.BackgroundTransparency = g end
	end

	-- animation loop ---------------------------------------------------
	local isOpen = true
	local clock = 0
	local fadeK, fadeShown = 0, -1   -- 0 = snow hidden, 1 = fully shown (fades in on load)

	fx_connections[#fx_connections + 1] = RunService.RenderStepped:Connect(function(dt)
		if not gui.Enabled then return end
		clock += dt

		-- smooth snow fade: in quickly when opening, out gently when closing
		if isOpen then
			fadeK = math.min(1, fadeK + dt / FADE_TIME)
		else
			fadeK = math.max(0, fadeK - dt / FADE_OUT_TIME)
		end
		local show = fadeK * fadeK * (3 - 2 * fadeK) -- smoothstep, no hard start / stop
		if math.abs(show - fadeShown) > 0.005 or (show == 0 and fadeShown ~= 0) or (show == 1 and fadeShown ~= 1) then
			fadeShown = show
			applyFade(show)
		end

		-- frost creeping in (open) / thawing out (close)
		if isOpen then
			frostReveal = math.clamp((os.clock() - frostStart) / FROST_TIME, 0, 1)
		else
			frostReveal = math.max(0, frostReveal - dt / FADE_OUT_TIME)
		end
		updateFrost(frostReveal, clock)
		updateMist(dt, clock, show)

		-- fully faded out -> switch everything off
		if not isOpen and fadeK <= 0 and frostReveal <= 0 then
			gui.Enabled = false
			blur.Enabled = false
			return
		end

		-- snowfall with wind gusts
		local vw, vh = snowLayer.AbsoluteSize.X, snowLayer.AbsoluteSize.Y
		local wind = math.noise(clock * 0.07, 1.3) * 55 + math.max(0, math.noise(clock * 0.25, 7.7)) * 90
		local lift = math.noise(clock * 0.2, 4.1) * 10
		for _, f in ipairs(flakes) do
			local L = f.layer
			local d = L.depth
			local vy = f.speed - lift * d
			local vxWind = wind * (0.25 + d)
			f.y += vy * dt
			f.x += vxWind * dt
			local ph = clock * f.freq + f.phase
			-- small irregular flutter, like a flake catching air
			local flutter = math.noise(clock * 2.5, f.seed) * L.flutter * 3
			local sx = f.x + math.sin(ph) * f.sway + flutter
			if f.y > vh + f.size * 2 then
				place(f, false)
				sx = f.x
			end
			local pad = f.size * 2 + f.sway
			if sx < -pad then f.x += vw + pad * 2 elseif sx > vw + pad then f.x -= vw + pad * 2 end
			f.root.Position = UDim2.fromOffset(sx, f.y)
			if f.spin then
				-- snowflakes turn slowly; gusts make them spin a little faster
				f.rot += (f.spin + wind * 0.15 * d) * dt
				f.root.Rotation = f.rot
			else
				-- specks: point the stretched (motion-blurred) axis along the actual direction
				local vx = vxWind + math.cos(ph) * f.sway * f.freq
				f.root.Rotation = math.deg(math.atan2(vy, vx)) - 90
			end
		end
	end)

	-- open / close -----------------------------------------------------
	local infoIn  = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local infoOut = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	local function show(open)
		if open == isOpen and gui.Enabled == open then return end
		isOpen = open
		if open then
			if not gui.Enabled or fadeK <= 0 then
				-- coming back from fully closed: start the snow from invisible and fade in
				fadeK, fadeShown = 0, -1
				applyFade(0)
				frostReveal = 0
			end
			frostStart = os.clock() - frostReveal * FROST_TIME -- resume frost if reopened mid-fade
			gui.Enabled = true
			blur.Enabled = true
		end
		local info = open and infoIn or infoOut
		TweenService:Create(backdrop, info, { BackgroundTransparency = open and BACKDROP_ALPHA or 1 }):Play()
		for _, fd in ipairs(fadeables) do
			TweenService:Create(fd[1], info, { BackgroundTransparency = open and fd[2] or 1 }):Play()
		end
		TweenService:Create(cold, open and coldInfo or info, open and COLD_ON or COLD_OFF):Play()
		TweenService:Create(blur, info, { Size = open and BLUR_SIZE or 0 }):Play()
		-- the render loop fades the snow out and switches the gui off when done
	end

	-- the menu says open / closed; "clear view" keeps the backdrop (blur, cold tint, snow,
	-- frost) away even while the menu is open, so weather changes can be watched live
	local wantOpen, clearView = start_open and true or false, false
	local function set_open(open)
		wantOpen = open
		show(open and not clearView)
	end
	local function set_clear(clear)
		clearView = clear and true or false
		if wantOpen then show(not clearView) end
	end

	local function destroy()
		for _, c in ipairs(fx_connections) do c:Disconnect() end
		gui:Destroy()
		blur:Destroy()
		cold:Destroy()
	end

	-- start fully off (no snow / frost / mist / blur / cold) until set_open(true) is called -
	-- the loader plays on a plain dark screen, and all of this comes in with the menu
	if not start_open then
		isOpen = false
		fadeK, fadeShown = 0, -1
		applyFade(0)
		frostReveal = 0
		backdrop.BackgroundTransparency = 1
		for _, fd in ipairs(fadeables) do fd[1].BackgroundTransparency = 1 end
		for k, v in pairs(COLD_OFF) do cold[k] = v end
		blur.Size = 0
		blur.Enabled = false
		gui.Enabled = false
	end

	return { set_open = set_open, set_clear = set_clear, destroy = destroy }
end

local fx = create_frost_fx(gui_parent, false) -- off until the loader finishes

-- =====================================================================
-- > ( menu library )
-- =====================================================================

-- > ( theme )

-- Jura: thin, cold, slightly sci-fi - fits the frost theme. Michroma: wide techno face for titles.
local FONT = Enum.Font.Jura
local TITLE_FONT = Enum.Font.Michroma
local TEXT_SIZE = 14
local MB1 = Enum.UserInputType.MouseButton1
local TOUCH = Enum.UserInputType.Touch
local MOVE = Enum.UserInputType.MouseMovement

local colors = {
	-- icy palette: accent matches the frost, greys carry a faint cold blue
	accent = Color3.fromRGB(176, 214, 248),
	active_text = Color3.fromRGB(205, 214, 226),
	inactive_text = Color3.fromRGB(80, 86, 98),
	dark_text = Color3.fromRGB(74, 88, 108),
	highlighted = Color3.fromRGB(52, 66, 86),
	border = Color3.fromRGB(22, 27, 35),
	section = Color3.fromRGB(6, 8, 12),
	background = Color3.fromRGB(2, 3, 6),
	card = Color3.fromRGB(10, 13, 19),     -- frosted section cards
	success = Color3.fromRGB(176, 214, 248),
	alert = Color3.fromRGB(255, 225, 0),
	error = Color3.fromRGB(255, 60, 63),
}

local flags = {}
local connections = {}
local accent_objects = {}
local key_listeners = {}

local menu = {
	colors = colors,
	flags = flags,
	groups = {},
	menu_key = Enum.KeyCode.Insert,
}

-- > ( helpers )

local function track(connection)
	connections[#connections + 1] = connection
	return connection
end

local function is_click(input)
	return input.UserInputType == MB1 or input.UserInputType == TOUCH
end

local function is_move(input)
	return input.UserInputType == MOVE or input.UserInputType == TOUCH
end

local function new(class, props, children)
	local instance = Instance.new(class)
	for property, value in pairs(props or {}) do
		if property ~= "Parent" then
			instance[property] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if props and props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 4) })
end

local function stroke(parent, color)
	return new("UIStroke", {
		Color = color or colors.border,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function tween(object, properties, time)
	TweenService:Create(
		object,
		TweenInfo.new(time or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		properties
	):Play()
end

local function accent(object, property)
	accent_objects[#accent_objects + 1] = { object, property }
	object[property] = colors.accent
	return object
end

local function round(number, decimals)
	local mult = 10 ^ (decimals or 0)
	return math.floor(number * mult + 0.5) / mult
end

local function text_label(props)
	local merged = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = FONT,
		TextSize = TEXT_SIZE,
		TextColor3 = colors.inactive_text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for property, value in pairs(props) do
		merged[property] = value
	end
	return new("TextLabel", merged)
end

local function hit_area(parent)
	return new("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = parent,
	})
end

local function hover(button, target_stroke)
	button.MouseEnter:Connect(function()
		tween(target_stroke, { Color = colors.highlighted })
	end)
	button.MouseLeave:Connect(function()
		tween(target_stroke, { Color = colors.border })
	end)
end

local function on_drag(object, callback)
	local dragging = false
	track(object.InputBegan:Connect(function(input)
		if is_click(input) then
			dragging = true
			callback(input.Position)
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and is_move(input) then
			callback(input.Position)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if is_click(input) then
			dragging = false
		end
	end))
end

-- > ( signal )

local signal = {}
signal.__index = signal

function signal.new()
	return setmetatable({ callbacks = {} }, signal)
end

function signal:Connect(callback)
	local callbacks = self.callbacks
	callbacks[#callbacks + 1] = callback
	return {
		Disconnect = function()
			local index = table.find(callbacks, callback)
			if index then
				table.remove(callbacks, index)
			end
		end,
	}
end

function signal:Fire(...)
	for _, callback in ipairs(self.callbacks) do
		task.spawn(callback, ...)
	end
end

local function create_connection(sig, callback)
	return sig:Connect(callback)
end

-- > ( window )

local old_gui = gui_parent:FindFirstChild("cover_menu")
if old_gui then
	old_gui:Destroy()
end

local screen = new("ScreenGui", {
	Name = "cover_menu",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999,
	Parent = gui_parent,
})

local main = new("Frame", {
	Size = UDim2.fromOffset(575, 450),
	Position = UDim2.new(0.5, -287, 0.5, -225),
	BackgroundColor3 = colors.section,
	BorderSizePixel = 0,
	Parent = screen,
}, { corner(3) })
stroke(main)

-- unlocks the mouse in first person while the menu is open
new("TextButton", {
	Modal = true,
	Text = "",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(0, 0),
	Parent = main,
})

-- layout: header bar (title + tabs) on top, content in the middle, slim footer at the bottom
local HEADER_H, FOOTER_H = 46, 26

local header = new("Frame", {
	Name = "header",
	Size = UDim2.new(1, 0, 0, HEADER_H),
	BackgroundTransparency = 1,
	Active = true,
	Parent = main,
})

-- soft divider under the header, fading out toward both ends
local function divider(y_scale, y_offset)
	local line = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, y_scale, y_offset),
		Size = UDim2.new(1, -24, 0, 1),
		BackgroundColor3 = colors.border,
		BorderSizePixel = 0,
		Parent = main,
	})
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0),
			NumberSequenceKeypoint.new(0.85, 0), NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = line,
	})
	return line
end
divider(0, HEADER_H)
divider(1, -FOOTER_H)

local footer = new("Frame", {
	Name = "footer",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, FOOTER_H),
	BackgroundTransparency = 1,
	Active = true,
	Parent = main,
})

local content = new("Frame", {
	Name = "content",
	Position = UDim2.fromOffset(0, HEADER_H + 1),
	Size = UDim2.new(1, 0, 1, -(HEADER_H + 1 + FOOTER_H)),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Parent = main,
})

-- > ( prism shimmer )  -  accent <-> white sheen that sweeps across, with a faint
-- cyan / lilac split either side of the white like light through ice.
-- The pattern repeats every 0.25 of the gradient, so sliding Offset by 0.25 loops seamlessly.
local function prism_sequence(a)
	local white = Color3.new(1, 1, 1)
	local cyan = a:Lerp(Color3.fromRGB(205, 245, 255), 0.6)
	local lilac = a:Lerp(Color3.fromRGB(238, 215, 252), 0.6)
	local kps = {}
	for i = 0, 3 do
		local b = i * 0.25
		kps[#kps + 1] = ColorSequenceKeypoint.new(b, a)
		kps[#kps + 1] = ColorSequenceKeypoint.new(b + 0.085, cyan)
		kps[#kps + 1] = ColorSequenceKeypoint.new(b + 0.125, white)
		kps[#kps + 1] = ColorSequenceKeypoint.new(b + 0.165, lilac)
	end
	kps[#kps + 1] = ColorSequenceKeypoint.new(1, a)
	return ColorSequence.new(kps)
end

-- moving line pattern: soft accent line with a bright icy-prism streak (accent -> cyan ->
-- white -> lilac -> accent). Repeats every half of the (double-width) line so it loops seamlessly.
local function line_sequence(a)
	local dim = a:Lerp(Color3.new(0, 0, 0), 0.35)
	local cyan = a:Lerp(Color3.fromRGB(205, 245, 255), 0.6)
	local lilac = a:Lerp(Color3.fromRGB(238, 215, 252), 0.6)
	local white = Color3.new(1, 1, 1)
	local kps = {}
	for i = 0, 1 do
		local b = i * 0.5
		kps[#kps + 1] = ColorSequenceKeypoint.new(b, dim)
		kps[#kps + 1] = ColorSequenceKeypoint.new(b + 0.16, a)
		kps[#kps + 1] = ColorSequenceKeypoint.new(b + 0.21, cyan)
		kps[#kps + 1] = ColorSequenceKeypoint.new(b + 0.25, white)
		kps[#kps + 1] = ColorSequenceKeypoint.new(b + 0.29, lilac)
		kps[#kps + 1] = ColorSequenceKeypoint.new(b + 0.34, a)
	end
	kps[#kps + 1] = ColorSequenceKeypoint.new(1, dim)
	return ColorSequence.new(kps)
end
-- matching brightness: always faintly visible, fully bright in the streak
local LINE_ALPHA = (function()
	local kps = {}
	for i = 0, 1 do
		local b = i * 0.5
		kps[#kps + 1] = NumberSequenceKeypoint.new(b, 0.5)
		kps[#kps + 1] = NumberSequenceKeypoint.new(b + 0.15, 0.25)
		kps[#kps + 1] = NumberSequenceKeypoint.new(b + 0.25, 0)
		kps[#kps + 1] = NumberSequenceKeypoint.new(b + 0.35, 0.25)
	end
	kps[#kps + 1] = NumberSequenceKeypoint.new(1, 0.5)
	return NumberSequence.new(kps)
end)()

local prism_gradients = {} -- gradients that get the shimmer
local line_rows = {}       -- { inner_frame, gradient, direction, speed, base_alpha, pulse_phase }

-- title + beta tag sit in a row, both centred on the header's middle line
local brand = new("Frame", {
	Position = UDim2.fromOffset(16, 0),
	Size = UDim2.new(0, 0, 0, HEADER_H),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Parent = header,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 9),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local title = text_label({
	Text = "cover",
	Font = TITLE_FONT,
	TextColor3 = Color3.new(1, 1, 1), -- white so the gradient shows its true colours
	TextSize = 16,
	Size = UDim2.new(0, 0, 0, 20),
	AutomaticSize = Enum.AutomaticSize.X,
	LayoutOrder = 1,
	Parent = brand,
})
prism_gradients[#prism_gradients + 1] = new("UIGradient", { Rotation = 12, Parent = title })

-- little "beta" tag next to the title: no fill, just a thin sharp outline, sized to its text
local badge = new("Frame", {
	Size = UDim2.fromOffset(0, 15),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	LayoutOrder = 2,
	Parent = brand,
}, {
	corner(2),
	-- extra bottom padding lifts the text: Jura sits low in its line box, so plain
	-- centring makes lowercase "beta" look like it's sagging
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 3) }),
})
local badge_stroke = stroke(badge, colors.accent)
badge_stroke.Transparency = 0.5
accent(badge_stroke, "Color")
accent(text_label({
	Text = "beta",
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	Parent = badge,
}), "TextColor3")

-- moving gradient lines along the top and bottom edge of the menu.
-- Each edge: a bright 1px core sitting right on the border + 2 fainter glow rows just inside,
-- the glow drifting at a different speed (so two streaks play off each other) and pulsing.
-- The ends fade out before the rounded corners so the lines sit cleanly in the frame.
local LINE_INSET = 5   -- px kept clear at each end (rounded corner)
local LINE_FADE  = 46  -- px over which each end fades out
local function edge_line(y_scale, direction, speed)
	local inward = y_scale == 0 and 1 or -1 -- top rows stack downward, bottom rows upward
	for row, cfg in ipairs({ { 0, 1, 0 }, { 0.55, 0.62, 1.3 }, { 0.78, 0.62, 2.1 } }) do
		local holder = new("Frame", {
			AnchorPoint = Vector2.new(0, y_scale),
			Position = UDim2.new(0, LINE_INSET, y_scale, (row - 1) * inward),
			Size = UDim2.new(1, -LINE_INSET * 2, 0, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 6,
			Parent = main,
		})
		-- inner line is twice as wide and slides one holder-width, so it loops seamlessly
		local inner = new("Frame", {
			Size = UDim2.fromScale(2, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = cfg[1],
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = holder,
		})
		local g = new("UIGradient", { Transparency = LINE_ALPHA, Parent = inner })
		line_rows[#line_rows + 1] = { inner, g, direction, speed * cfg[2], cfg[1], cfg[3] }
	end
	-- end fades: soft caps the colour of the menu underneath
	for _, side in ipairs({ 0, 1 }) do
		local cap = new("Frame", {
			AnchorPoint = Vector2.new(side, y_scale),
			Position = UDim2.new(side, side == 0 and LINE_INSET or -LINE_INSET, y_scale, 0),
			Size = UDim2.fromOffset(LINE_FADE, 3),
			BackgroundColor3 = colors.section,
			BorderSizePixel = 0,
			ZIndex = 7,
			Parent = main,
		})
		new("UIGradient", { Transparency = side == 0 and NumberSequence.new(0, 1) or NumberSequence.new(1, 0), Parent = cap })
	end
end
edge_line(0, 1, 0.18)
edge_line(1, -1, 0.13)

-- title shimmer: a smooth half-accent / half-white wave rolling to the right.
-- It's rebuilt from the clock every frame (instead of sliding the gradient), so it loops
-- forever with no seam and never gets clamped at the edges of the text.
local SHIMMER_BAND  = 0.7  -- length of one accent+white cycle, as a fraction of the text width
local SHIMMER_SPEED = 0.45 -- cycles per second (higher = faster)
local function shimmer_wave(a, t)
	local white = Color3.new(1, 1, 1)
	local kps = {}
	for i = 0, 16 do
		local x = i / 16
		-- cosine wave between the accent and white: exactly 50 / 50 on average
		local k = 0.5 + 0.5 * math.cos((x / SHIMMER_BAND - t * SHIMMER_SPEED) * math.pi * 2)
		kps[#kps + 1] = ColorSequenceKeypoint.new(x, a:Lerp(white, k))
	end
	return ColorSequence.new(kps)
end

do
	local last_accent
	local t = 0
	track(RunService.RenderStepped:Connect(function(dt)
		t += dt
		if last_accent ~= colors.accent then -- rebuild line colours only when the accent changes
			last_accent = colors.accent
			local ls = line_sequence(last_accent)
			for _, l in ipairs(line_rows) do l[2].Color = ls end
		end
		local wave = shimmer_wave(colors.accent, t)
		for _, g in ipairs(prism_gradients) do
			g.Color = wave
			g.Offset = Vector2.zero
		end
		for _, l in ipairs(line_rows) do
			local p = (t * l[4]) % 1
			l[1].Position = UDim2.fromScale(l[3] > 0 and (p - 1) or -p, 0)
			if l[5] > 0 then -- glow rows breathe softly
				l[1].BackgroundTransparency = math.clamp(l[5] + 0.12 * math.sin(t * 1.6 + l[6]), 0, 0.95)
			end
		end
	end))
end

-- tabs live in the header, right-aligned, laid out horizontally
local tabs_list = new("Frame", {
	Name = "tabs",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 0),
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Parent = header,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

-- active-tab indicator: no box behind the tab. Instead a sharp beam of light lying right on
-- the header's divider under the tab - soft at both ends, a glow rising off it, and a bright
-- glint that keeps running along it. It glides from tab to tab instead of jumping.
local indicator = new("Frame", {
	Name = "indicator",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromOffset(0, HEADER_H + 1),
	Size = UDim2.fromOffset(0, 14),
	BackgroundTransparency = 1,
	ZIndex = 3,
	Parent = header,
})
local BEAM_ENDS = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, 0),
	NumberSequenceKeypoint.new(0.82, 0), NumberSequenceKeypoint.new(1, 1),
})
local indicator_line = new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 2),
	BorderSizePixel = 0,
	ZIndex = 3,
	Parent = indicator,
}, { new("UIGradient", { Transparency = BEAM_ENDS }) })
accent(indicator_line, "BackgroundColor3")
local indicator_glow = new("Frame", { -- soft light rising off the beam
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -2),
	Size = UDim2.new(1, -16, 0, 12),
	BorderSizePixel = 0,
	ZIndex = 3,
	Parent = indicator,
}, { new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0.76) }) })
accent(indicator_glow, "BackgroundColor3")
local indicator_glint = new("Frame", { -- white glint running along the beam
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 2),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	ZIndex = 4,
	Parent = indicator,
})
local glint_grad = new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0.1),
		NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1),
	}),
	Parent = indicator_glint,
})

local indicator_x, indicator_w = nil, nil
local glint_t = 0
track(RunService.RenderStepped:Connect(function(dt)
	local tab = menu.active_tab
	if not tab or not main.Visible then return end
	local tx = tab.button.AbsolutePosition.X - header.AbsolutePosition.X
	local tw = tab.button.AbsoluteSize.X
	if not indicator_x then
		indicator_x, indicator_w = tx, tw -- first frame: snap, no glide from nowhere
	end
	local a = 1 - math.exp(-dt * 16)
	indicator_x += (tx - indicator_x) * a
	indicator_w += (tw - indicator_w) * a
	indicator.Position = UDim2.fromOffset(indicator_x, HEADER_H + 1)
	indicator.Size = UDim2.fromOffset(indicator_w, 14)
	glint_t = (glint_t + dt / 2.4) % 1 -- glint crosses every 2.4 s, then loops
	glint_grad.Offset = Vector2.new(-0.6 + glint_t * 1.2, 0)
end))

-- drag window by the header or footer (clamped so it gets stuck at the screen edges)
do
	local dragging, start_mouse, start_position

	local function clamp_to_screen(pos)
		local screen_size = screen.AbsoluteSize
		local size = main.AbsoluteSize
		local max_x = math.max(0, screen_size.X - size.X)
		local max_y = math.max(0, screen_size.Y - size.Y)
		return Vector2.new(math.clamp(pos.X, 0, max_x), math.clamp(pos.Y, 0, max_y))
	end

	local function over(gui_object, pos)
		local p, s = gui_object.AbsolutePosition, gui_object.AbsoluteSize
		return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
	end
	local function begin_drag(input)
		if not is_click(input) then return end
		if over(tabs_list, input.Position) then return end -- clicking a tab isn't a drag
		dragging = true
		start_mouse = input.Position
		start_position = main.AbsolutePosition - screen.AbsolutePosition
	end
	track(header.InputBegan:Connect(begin_drag))
	track(footer.InputBegan:Connect(begin_drag))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and is_move(input) then
			local delta = input.Position - start_mouse
			local pos = clamp_to_screen(start_position + Vector2.new(delta.X, delta.Y))
			main.Position = UDim2.fromOffset(pos.X, pos.Y)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if is_click(input) then
			dragging = false
		end
	end))
	-- keep it on screen if the window gets resized
	track(screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local pos = clamp_to_screen(main.AbsolutePosition - screen.AbsolutePosition)
		main.Position = UDim2.fromOffset(pos.X, pos.Y)
	end))
end

-- > ( notifications )

-- toasts: centred at the bottom of the screen, just above the hotbar, stacking upward.
-- Styled like the menu: frosted card, soft 3px corners, a glowing accent beam along the top.
local TextService = game:GetService("TextService")
local TOAST_H = 34
local TOAST_ABOVE_BOTTOM = 104 -- px from the bottom of the screen (clears the hotbar)

local notification_holder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -TOAST_ABOVE_BOTTOM),
	Size = UDim2.fromOffset(600, 360), -- room for 7 + one fading out
	BackgroundTransparency = 1,
	-- topmost layer of the menu screen: above the menu (1), the book cover (10) and the loader (50),
	-- so a toast is never hidden behind the menu while it opens or sits on top of it
	ZIndex = 100,
	Parent = screen,
}, {
	new("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local notification_count = 0
local MAX_TOASTS = 7     -- never more than this on screen; the oldest makes room for a new one
local active_toasts = {} -- oldest first: { dismiss = function(fast) }

local function ease(object, props, time, style, direction)
	local t = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quart,
		direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local TOAST_BEAM = NumberSequence.new({ -- timer line: soft at both ends (like the tab indicator)
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.15),
	NumberSequenceKeypoint.new(0.8, 0.15), NumberSequenceKeypoint.new(1, 1),
})
local TOAST_TOP = NumberSequence.new({ -- top light: full strength all the way to both edges
	NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0.12),
})
local TOAST_INSET = 1 -- px kept clear at each end, just enough to stay inside the card's border

function menu.new_notification(text, kind, time)
	local color = (kind == 1 and colors.success) or (kind == 2 and colors.alert) or (kind == 3 and colors.error)
		or colors.accent
	local duration = math.clamp(time or 2.5, 0.5, 7)
	notification_count += 1

	-- Width = left area (icon) + the text's REAL rendered width + a right margin. The real width
	-- is read from the label itself just before the toast appears (estimates came out short for
	-- Jura and clipped the text; letting the card size itself automatically clipped the card).
	local PAD_L, PAD_R = 32, 22
	local guess = math.ceil(TextService:GetTextSize(text, TEXT_SIZE, FONT, Vector2.new(2000, 40)).X * 1.15)
	local W = PAD_L + guess + PAD_R -- only used while still invisible, until the real width is known

	-- slot reserves space in the stack and grows / shrinks so the others glide instead of jumping
	local slot = new("Frame", {
		Size = UDim2.fromOffset(W, 0),
		BackgroundTransparency = 1,
		LayoutOrder = notification_count, -- newest sits at the bottom, nearest the hotbar; older ones rise
		Parent = notification_holder,
	})
	-- the whole card fades as one (CanvasGroup) and floats up into place.
	-- The canvas is CANVAS_PAD px bigger than the card on every side: a CanvasGroup can lose its
	-- outermost pixel column when it lands between whole pixels, and that's exactly where the
	-- card's border was (the cut-off right edge). Now that outer ring is empty, so nothing is lost.
	local CANVAS_PAD = 4
	local card = new("CanvasGroup", {
		Position = UDim2.fromOffset(-CANVAS_PAD, 12 - CANVAS_PAD),
		Size = UDim2.fromOffset(W + CANVAS_PAD * 2, TOAST_H + CANVAS_PAD * 2),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Parent = slot,
	})
	local body = new("Frame", { -- the actual toast, sitting inside the padded canvas
		Position = UDim2.fromOffset(CANVAS_PAD, CANVAS_PAD),
		Size = UDim2.new(1, -CANVAS_PAD * 2, 1, -CANVAS_PAD * 2),
		BackgroundTransparency = 1,
		Parent = card,
	})
	local bg = new("Frame", { -- inset 1px so the outline isn't clipped by the card's edges
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundColor3 = colors.card,
		BorderSizePixel = 0,
		Parent = body,
	}, {
		corner(3),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 198, 212)) }),
	})
	stroke(bg, colors.border)

	-- glowing accent beam along the top edge + a white glint that runs across it on arrival
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 1),
		Size = UDim2.new(1, -TOAST_INSET * 2, 0, 1), -- reaches the corners
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = body,
	}, { new("UIGradient", { Transparency = TOAST_TOP }) })
	new("Frame", { -- soft light falling off the beam
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.new(1, -TOAST_INSET * 2, 0, 8), -- glow spans the full width too
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = body,
	}, { new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.85, 1) }) })
	local beam_glint = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 1),
		Size = UDim2.new(1, -TOAST_INSET * 2, 0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = body,
	})
	local glint_g = new("UIGradient", {
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = beam_glint,
	})

	-- diamond icon, same motif as the section headers
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 18, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		Rotation = 45,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.84,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = body,
	}, { corner(2) })
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 18, 0.5, 0),
		Size = UDim2.fromOffset(5, 5),
		Rotation = 45,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = body,
	}, { corner(1) })

	local toast_text = text_label({
		Text = text,
		TextColor3 = colors.active_text,
		Position = UDim2.fromOffset(PAD_L, 0),
		Size = UDim2.new(1, -PAD_L, 1, 0),
		ZIndex = 4,
		Parent = body,
	})

	-- time-left line along the bottom, shrinking toward the middle until the toast leaves
	local timer = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, -24, 0, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = body,
	}, { new("UIGradient", { Transparency = TOAST_BEAM }) })

	-- out: drift up a little and fade, then close the gap. Runs once, whichever comes first:
	-- the timer running out, or a newer toast needing the space (fast = quicker exit)
	local toast = {}
	local gone = false
	function toast.dismiss(fast)
		if gone then return end
		gone = true
		local i = table.find(active_toasts, toast)
		if i then table.remove(active_toasts, i) end
		local fade, close = fast and 0.18 or 0.32, fast and 0.14 or 0.22
		ease(card, { Position = UDim2.fromOffset(-CANVAS_PAD, -8 - CANVAS_PAD), GroupTransparency = 1 }, fade, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		task.delay(fade, function()
			if not slot.Parent then return end
			ease(slot, { Size = UDim2.fromOffset(slot.Size.X.Offset, 0) }, close)
			task.delay(close, function() slot:Destroy() end)
		end)
	end

	-- the stack is full: the oldest one bows out so this one has room
	while #active_toasts >= MAX_TOASTS do
		active_toasts[1].dismiss(true)
	end
	active_toasts[#active_toasts + 1] = toast

	-- in: as soon as the label knows its real text width, size the card to it, then
	-- make room, float up + fade in, glint runs across the beam, timer starts
	task.spawn(function()
		for _ = 1, 10 do
			if toast_text.TextBounds.X > 0 then break end
			RunService.RenderStepped:Wait()
		end
		if gone or not slot.Parent then return end
		local real = math.ceil(toast_text.TextBounds.X)
		if real > 0 then W = PAD_L + real + PAD_R end
		W += W % 2 -- even width, so a centred toast lands on whole pixels
		slot.Size = UDim2.fromOffset(W, 0)
		card.Size = UDim2.fromOffset(W + CANVAS_PAD * 2, TOAST_H + CANVAS_PAD * 2)

		ease(slot, { Size = UDim2.fromOffset(W, TOAST_H) }, 0.24)
		ease(card, { Position = UDim2.fromOffset(-CANVAS_PAD, -CANVAS_PAD), GroupTransparency = 0 }, 0.42)
		ease(glint_g, { Offset = Vector2.new(1, 0) }, 0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		ease(timer, { Size = UDim2.new(0, 0, 0, 1) }, duration, Enum.EasingStyle.Linear)
	end)

	task.delay(duration, toast.dismiss)
end

-- > ( elements )

local rainbow = {}
for i = 0, 6 do
	rainbow[#rainbow + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1))
end
rainbow = ColorSequence.new(rainbow)

local function create_element(section, info, opts)
	local el = { name = info.name, section = section }
	section.order += 1

	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = section.order,
		Parent = section.list,
	}, {
		new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	el.frame = holder

	local header, label
	local right_x = 0
	local function place_right(width)
		local x = right_x
		right_x += width + 4
		return UDim2.new(1, -(x + width), 0, 1)
	end

	if not opts.button then
		local left_offset = 0 -- toggles are switches on the right now, so labels start flush left
		header = new("Frame", {
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = holder,
		})
		label = text_label({
			Text = info.name,
			Position = UDim2.fromOffset(left_offset, 0),
			Size = UDim2.new(1, -left_offset, 1, 0),
			Parent = header,
		})
		el.label = label
	end

	-- toggle
	if opts.toggle then
		local p = opts.toggle
		el.toggle_flag = p.flag
		el.on_toggle_change = signal.new()

		-- sliding switch on the right: icy track fills in, knob glides across and lights up
		local track_frame = new("Frame", {
			Size = UDim2.fromOffset(24, 12),
			Position = place_right(24),
			BackgroundColor3 = colors.background,
			BorderSizePixel = 0,
			Parent = header,
		}, { corner(2) })
		local box_stroke = stroke(track_frame)
		local track_fill = new("Frame", { -- accent wash inside the track when on
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = track_frame,
		}, { corner(2) })
		accent(track_fill, "BackgroundColor3")
		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 2, 0.5, 0),
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = colors.inactive_text,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = track_frame,
		}, { corner(1) })

		local click = new("TextButton", {
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = header,
		})
		hover(click, box_stroke)

		function el:set_toggle(value)
			value = value and true or false
			flags[p.flag] = value
			tween(knob, {
				Position = UDim2.new(0, value and 14 or 2, 0.5, 0),
				BackgroundColor3 = value and colors.accent or colors.inactive_text,
			}, 0.18)
			tween(track_fill, { BackgroundTransparency = value and 0.78 or 1 }, 0.18)
			tween(label, { TextColor3 = value and colors.active_text or colors.inactive_text })
			el.on_toggle_change:Fire(value)
		end

		click.MouseButton1Click:Connect(function()
			el:set_toggle(not flags[p.flag])
		end)

		el:set_toggle(p.default)
	end

	-- colorpicker
	if opts.colorpicker then
		local p = opts.colorpicker
		el.color_flag = p.color_flag
		el.transparency_flag = p.transparency_flag
		el.on_color_change = signal.new()
		el.on_transparency_change = signal.new()

		local swatch = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(24, 12),
			Position = place_right(24),
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = header,
		}, { corner(2) })
		local swatch_stroke = stroke(swatch)
		hover(swatch, swatch_stroke)

		local panel = new("Frame", {
			Size = UDim2.new(1, 0, 0, 136),
			BackgroundColor3 = colors.background,
			BorderSizePixel = 0,
			Visible = false,
			LayoutOrder = 5,
			Parent = holder,
		}, { corner(2) })
		stroke(panel)

		local sv = new("Frame", {
			Position = UDim2.fromOffset(5, 5),
			Size = UDim2.new(1, -10, 0, 104),
			BorderSizePixel = 0,
			Parent = panel,
		}, { corner(2) })
		new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = sv,
		}, { corner(2), new("UIGradient", { Transparency = NumberSequence.new(0, 1) }) })
		new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Parent = sv,
		}, { corner(2), new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }) })
		local sv_knob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 3,
			Parent = sv,
		}, { corner(2) })
		stroke(sv_knob, Color3.new(0, 0, 0))

		local hue_bar = new("Frame", {
			Position = UDim2.fromOffset(5, 118),
			Size = UDim2.new(1, -10, 0, 10),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = panel,
		}, { corner(2), new("UIGradient", { Color = rainbow }) })
		local hue_knob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(4, 12),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 3,
			Parent = hue_bar,
		}, { corner(2) })
		stroke(hue_knob, Color3.new(0, 0, 0))

		local h, s, v = 0, 1, 1

		local function apply()
			local color = Color3.fromHSV(h, s, v)
			sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			sv_knob.Position = UDim2.fromScale(s, 1 - v)
			hue_knob.Position = UDim2.fromScale(h, 0.5)
			swatch.BackgroundColor3 = color
			flags[p.color_flag] = color
			el.on_color_change:Fire(color)
		end

		function el:set_colorpicker(color)
			h, s, v = color:ToHSV()
			apply()
		end

		function el:set_colorpicker_transparency(transparency)
			flags[p.transparency_flag] = transparency
			swatch.BackgroundTransparency = transparency
			el.on_transparency_change:Fire(transparency)
		end

		on_drag(hit_area(sv), function(position)
			s = math.clamp((position.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
			v = 1 - math.clamp((position.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
			apply()
		end)

		on_drag(hit_area(hue_bar), function(position)
			h = math.clamp((position.X - hue_bar.AbsolutePosition.X) / hue_bar.AbsoluteSize.X, 0, 1)
			apply()
		end)

		swatch.MouseButton1Click:Connect(function()
			panel.Visible = not panel.Visible
		end)

		el:set_colorpicker(p.default_color or Color3.fromRGB(255, 0, 0))
		el:set_colorpicker_transparency(p.default_transparency or 0)
	end

	-- keybind
	if opts.keybind then
		local p = opts.keybind
		el.keybind_flag = p.flag
		el.on_key_change = signal.new()
		el.on_key_press = signal.new()

		local position = place_right(40)
		local key_button = new("TextButton", {
			Text = "none",
			Font = FONT,
			TextSize = 11,
			TextColor3 = colors.dark_text,
			TextYAlignment = Enum.TextYAlignment.Center,
			BackgroundColor3 = colors.background,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, position.X.Offset + 40, 0.5, 0),
			-- a little taller than the text, with extra bottom padding: Jura sits low in its
			-- line box, so without this the key name sags toward the bottom of the box
			Size = UDim2.fromOffset(0, 16),
			AutomaticSize = Enum.AutomaticSize.X,
			ZIndex = 3,
			Parent = header,
		}, {
			corner(2),
			new("UIPadding", {
				PaddingLeft = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 3),
			}),
		})
		local key_stroke = stroke(key_button)
		hover(key_button, key_stroke)

		function el:set_key(key)
			el.key = key
			if p.flag then
				flags[p.flag] = key
			end
			key_button.Text = key and key.Name:lower() or "none"
			el.on_key_change:Fire(key)
		end

		key_button.MouseButton1Click:Connect(function()
			key_button.Text = "..."
			key_button.TextColor3 = colors.accent
			menu.binding = true
			local connection
			connection = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Keyboard then
					connection:Disconnect()
					task.defer(function()
						menu.binding = false
					end)
					key_button.TextColor3 = colors.dark_text
					el:set_key(input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode or nil)
				end
			end)
		end)

		key_listeners[#key_listeners + 1] = el
		el:set_key(p.default)
	end

	-- info text
	if opts.info then
		local info_label = text_label({
			Text = "",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = header,
		})
		function el:set_info(property, value)
			info_label[property] = value
		end
	end

	-- slider
	if opts.slider then
		local p = opts.slider
		local min, max, decimals = p.min or 0, p.max or 100, p.decimals or 0
		el.slider_flag = p.flag
		el.slider_min, el.slider_max = min, max
		el.on_slider_change = signal.new()

		local value_text = text_label({
			Text = "",
			TextColor3 = colors.dark_text,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = place_right(70) - UDim2.fromOffset(0, 1),
			Size = UDim2.fromOffset(70, 14),
			Parent = header,
		})

		-- slim icy track + glowing round knob. `bar` is the full-width hit area around it.
		local bar = new("Frame", {
			Size = UDim2.new(1, 0, 0, 12),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = holder,
		})
		local track_frame = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 4),
			BackgroundColor3 = colors.background,
			BorderSizePixel = 0,
			Parent = bar,
		}, { corner(1) })
		local bar_stroke = stroke(track_frame)
		local fill = new("Frame", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = track_frame,
		}, { corner(1) })
		-- fill fades from a deeper accent to a bright icy tip
		local fill_grad = new("UIGradient", { Parent = fill })
		-- knob is a small diamond, matching the section diamonds
		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(8, 8),
			Rotation = 45,
			BackgroundColor3 = Color3.fromRGB(232, 242, 255),
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = bar,
		}, { corner(1) })
		local knob_stroke = stroke(knob, colors.accent)
		accent(knob_stroke, "Color")
		local knob_glow = new("Frame", { -- faint diamond halo behind the knob (a sibling, so it sits underneath)
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(15, 15),
			Rotation = 45,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = bar,
		}, { corner(2) })
		accent(knob_glow, "BackgroundColor3")

		local hit = hit_area(bar)
		hover(hit, bar_stroke)
		hit.MouseEnter:Connect(function() tween(knob_glow, { BackgroundTransparency = 0.78 }) end)
		hit.MouseLeave:Connect(function() tween(knob_glow, { BackgroundTransparency = 0.88 }) end)

		-- smooth fill: the bar glides toward its target every frame instead of restarting
		-- a tween on every mouse move (that restart is what made it stutter)
		local fill_now, fill_target = 0, 0
		local last_accent
		local function show_fill(v)
			fill.Size = UDim2.new(v, 0, 1, 0)
			knob.Position = UDim2.fromScale(v, 0.5)
			knob_glow.Position = knob.Position
		end
		track(RunService.RenderStepped:Connect(function(dt)
			if last_accent ~= colors.accent then -- keep the fill colours in step with the accent
				last_accent = colors.accent
				fill_grad.Color = ColorSequence.new(last_accent:Lerp(Color3.new(0, 0, 0), 0.35), last_accent:Lerp(Color3.new(1, 1, 1), 0.35))
			end
			local diff = fill_target - fill_now
			if math.abs(diff) < 0.0005 then
				if fill_now ~= fill_target then
					fill_now = fill_target
					show_fill(fill_now)
				end
				return
			end
			fill_now += diff * (1 - math.exp(-dt * 22))
			show_fill(fill_now)
		end))

		-- visual_alpha: exact mouse position while dragging (so the bar isn't stuck to whole-number steps)
		function el:set_slider(value, visual_alpha)
			value = math.clamp(round(tonumber(value) or min, decimals), min, max)
			flags[p.flag] = value
			fill_target = visual_alpha or (value - min) / (max - min)
			if value == min and p.min_text then
				value_text.Text = p.min_text
			elseif value == max and p.max_text then
				value_text.Text = p.max_text
			else
				value_text.Text = (p.prefix or "") .. value .. (p.suffix or "")
			end
			el.on_slider_change:Fire(value)
		end

		local dragging_slider = false
		on_drag(hit, function(position)
			dragging_slider = true
			local alpha = math.clamp((position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
			fill_target = alpha -- bar follows the mouse exactly, every frame
			if flags[p.flag] ~= round(min + (max - min) * alpha, decimals) then
				el:set_slider(min + (max - min) * alpha, alpha)
			end
		end)
		-- on release, settle the bar onto the real (rounded) value
		track(UserInputService.InputEnded:Connect(function(input)
			if dragging_slider and is_click(input) then
				dragging_slider = false
				fill_target = ((flags[p.flag] or min) - min) / (max - min)
			end
		end))

		el:set_slider(p.default or min)
		fill_now = fill_target
		show_fill(fill_now)
	end

	-- dropdown
	if opts.dropdown then
		local p = opts.dropdown
		el.dropdown_flag = p.flag
		el.options = p.options or {}
		el.on_dropdown_change = signal.new()

		local box = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundColor3 = colors.background,
			BorderSizePixel = 0,
			LayoutOrder = 3,
			Parent = holder,
		}, { corner(2) })
		local box_stroke = stroke(box)
		hover(box, box_stroke)

		local shown = text_label({
			Text = "none",
			TextColor3 = colors.dark_text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Parent = box,
		})
		-- chevron drawn from two thin bars; it flips when the list opens
		local arrow = new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(9, 9),
			BackgroundTransparency = 1,
			Parent = box,
		})
		for _, s in ipairs({ -1, 1 }) do
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, s * 2, 0.5, 0),
				Size = UDim2.fromOffset(6, 1),
				Rotation = s * -45,
				BackgroundColor3 = colors.dark_text,
				BorderSizePixel = 0,
				Parent = arrow,
			})
		end

		local list = new("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = colors.background,
			BorderSizePixel = 0,
			Visible = false,
			LayoutOrder = 4,
			Parent = holder,
		}, {
			corner(2),
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
			new("UIPadding", {
				PaddingTop = UDim.new(0, 3),
				PaddingBottom = UDim.new(0, 3),
				PaddingLeft = UDim.new(0, 5),
				PaddingRight = UDim.new(0, 5),
			}),
		})
		stroke(list)

		local selected = {}
		local option_buttons = {}

		local function set_open(open)
			list.Visible = open
			tween(arrow, { Rotation = open and 180 or 0 }, 0.18)
			tween(box_stroke, { Color = open and colors.highlighted or colors.border })
		end

		local function refresh()
			for option, button in pairs(option_buttons) do
				button.TextColor3 = table.find(selected, option) and colors.accent or colors.inactive_text
			end
		end

		local function rebuild()
			for _, button in pairs(option_buttons) do
				button:Destroy()
			end
			option_buttons = {}

			for index, option in ipairs(el.options) do
				local button = new("TextButton", {
					Text = option,
					Font = FONT,
					TextSize = TEXT_SIZE,
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					Size = UDim2.new(1, 0, 0, 15),
					LayoutOrder = index,
					Parent = list,
				})
				option_buttons[option] = button

				button.MouseEnter:Connect(function()
					if not table.find(selected, option) then
						button.TextColor3 = colors.highlighted
					end
				end)
				button.MouseLeave:Connect(refresh)

				button.MouseButton1Click:Connect(function()
					local new_selection = table.clone(selected)
					local found = table.find(new_selection, option)

					if p.multi then
						if found then
							if not (p.requires_one and #new_selection == 1) then
								table.remove(new_selection, found)
							end
						else
							table.insert(new_selection, option)
						end
					else
						if found then
							if not p.requires_one then
								new_selection = {}
							end
						else
							new_selection = { option }
						end
						set_open(false)
					end

					el:set_dropdown(new_selection)
				end)
			end
			refresh()
		end

		function el:set_dropdown(value)
			if type(value) ~= "table" then
				value = value ~= nil and { value } or {}
			end
			local clean = {}
			for _, option in ipairs(value) do
				if table.find(el.options, option) then
					clean[#clean + 1] = option
				end
			end
			selected = clean
			flags[p.flag] = clean
			shown.Text = #clean > 0 and table.concat(clean, ", ") or "none"
			refresh()
			el.on_dropdown_change:Fire(clean)
		end

		function el:set_options(options)
			el.options = options
			rebuild()
			el:set_dropdown(selected)
		end

		box.MouseButton1Click:Connect(function()
			set_open(not list.Visible)
		end)

		rebuild()
		el:set_dropdown(p.default)
	end

	-- textbox
	if opts.textbox then
		local p = opts.textbox
		el.textbox_flag = p.flag
		el.on_textbox_change = signal.new()

		local textbox = new("TextBox", {
			Text = "",
			PlaceholderText = "...",
			PlaceholderColor3 = colors.dark_text,
			TextColor3 = colors.active_text,
			Font = FONT,
			TextSize = TEXT_SIZE,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			BackgroundColor3 = colors.background,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 3,
			Parent = holder,
		}, { corner(2), new("UIPadding", { PaddingLeft = UDim.new(0, 8) }) })
		local textbox_stroke = stroke(textbox)

		function el:set_textbox(value)
			flags[p.flag] = value
			textbox.Text = value or ""
			el.on_textbox_change:Fire(value)
		end

		textbox.Focused:Connect(function()
			tween(textbox_stroke, { Color = colors.highlighted })
		end)
		textbox.FocusLost:Connect(function()
			tween(textbox_stroke, { Color = colors.border })
			el:set_textbox(textbox.Text)
		end)

		el:set_textbox(p.default)
	end

	-- button
	if opts.button then
		local p = opts.button
		el.on_clicked = signal.new()

		local button = new("TextButton", {
			Text = info.name,
			Font = FONT,
			TextSize = TEXT_SIZE,
			TextColor3 = colors.dark_text,
			BackgroundColor3 = colors.background,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = 2,
			Parent = holder,
		}, { corner(2) })
		local button_stroke = stroke(button)
		hover(button, button_stroke)
		-- hover: an icy tint washes in and the text brightens
		button.MouseEnter:Connect(function()
			tween(button, { BackgroundColor3 = colors.background:Lerp(colors.accent, 0.1), TextColor3 = colors.active_text })
		end)
		button.MouseLeave:Connect(function()
			tween(button, { BackgroundColor3 = colors.background, TextColor3 = colors.dark_text })
		end)

		local confirming = false
		button.MouseButton1Click:Connect(function()
			if p.confirmation and not confirming then
				confirming = true
				button.Text = "are you sure?"
				button.TextColor3 = colors.accent
				task.delay(3, function()
					if confirming then
						confirming = false
						button.Text = info.name
						button.TextColor3 = colors.dark_text
					end
				end)
				return
			end

			confirming = false
			button.Text = info.name
			button.TextColor3 = colors.dark_text
			button.BackgroundColor3 = colors.background:Lerp(colors.accent, 0.35) -- icy flash on click
			tween(button, { BackgroundColor3 = colors.background:Lerp(colors.accent, 0.1) }, 0.3)
			el.on_clicked:Fire()
		end)
	end

	function el:set_visible(visible)
		holder.Visible = visible
	end

	section.elements[#section.elements + 1] = el
	return el
end

-- > ( groups / tabs / sections )

local group = {}
group.__index = group

local group_count = 0
local PAGE_PAD = 12
local function hover_text() -- tabs brighten (not darken) on hover
	return colors.inactive_text:Lerp(colors.active_text, 0.45)
end

function menu.select_tab(tab)
	local old = menu.active_tab
	if old == tab then
		return
	end

	if old then
		tween(old.button, { TextColor3 = colors.inactive_text })
		old.page.Visible = false
	end

	tween(tab.button, { TextColor3 = Color3.new(1, 1, 1):Lerp(colors.accent, 0.3) }) -- bright icy white, not grey
	-- the page slides in from slightly to the side
	tab.page.Visible = true
	tab.page.Position = UDim2.fromOffset(PAGE_PAD + 10, PAGE_PAD)
	tween(tab.page, { Position = UDim2.fromOffset(PAGE_PAD, PAGE_PAD) }, 0.22)

	menu.active_tab = tab
end

function menu.create_group(name)
	group_count += 1
	local base = group_count * 1000

	local new_group = setmetatable({ name = name, tabs = {}, base = base, tab_count = 0 }, group)

	if group_count > 1 then
		-- groups are only separated by a faint vertical divider (no group name shown)
		new("Frame", {
			Size = UDim2.fromOffset(1, 14),
			BackgroundColor3 = colors.border,
			BorderSizePixel = 0,
			LayoutOrder = base,
			Parent = tabs_list,
		}, {
			new("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
	end

	menu.groups[name] = new_group
	return new_group
end

function group:create_tab(name)
	self.tab_count += 1

	local tab = { name = name, group = self, sections = {}, order = 0 }

	local button = new("TextButton", {
		Text = name:sub(1, 14),
		Font = FONT,
		TextSize = TEXT_SIZE,
		TextColor3 = colors.inactive_text,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = self.base + 2 + self.tab_count,
		ZIndex = 2,
		Parent = tabs_list,
	}, {
		new("UIPadding", { PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11) }),
	})

	local page = new("Frame", {
		Position = UDim2.fromOffset(PAGE_PAD, PAGE_PAD),
		Size = UDim2.new(1, -PAGE_PAD * 2, 1, -PAGE_PAD * 2),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = content,
	})

	local function column(side)
		local scroller = new("ScrollingFrame", {
			Position = side == 1 and UDim2.new() or UDim2.new(0.5, 6, 0, 0),
			Size = UDim2.new(0.5, -6, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 2,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Parent = page,
		}, {
			new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
			new("UIPadding", {
				PaddingTop = UDim.new(0, 2),
				PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 1),
				PaddingRight = UDim.new(0, 5),
			}),
		})
		accent(scroller, "ScrollBarImageColor3")
		return scroller
	end

	tab.button = button
	tab.page = page
	tab.columns = { column(1), column(2) }

	button.MouseEnter:Connect(function()
		if menu.active_tab ~= tab then
			tween(button, { TextColor3 = hover_text() })
		end
	end)
	button.MouseLeave:Connect(function()
		if menu.active_tab ~= tab then
			tween(button, { TextColor3 = colors.inactive_text })
		end
	end)
	button.MouseButton1Click:Connect(function()
		menu.select_tab(tab)
	end)

	self.tabs[name] = tab

	if not menu.active_tab then
		menu.select_tab(tab)
	end

	return tab
end

-- section card: frosted panel, accent diamond + title, a fading accent rule, then the controls
function group:create_section(tab_name, name, side)
	local tab = self.tabs[tab_name]
	if not tab then
		return nil
	end

	tab.order += 1

	local frame = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.card,
		BorderSizePixel = 0,
		LayoutOrder = tab.order,
		Parent = tab.columns[side == 2 and 2 or 1],
	}, {
		corner(3),
		new("UIPadding", { PaddingBottom = UDim.new(0, 12) }),
		-- frosted depth: a touch lighter at the top than the bottom
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 202, 214)),
		}),
	})
	stroke(frame)

	local diamond = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(16, 15),
		Size = UDim2.fromOffset(5, 5),
		Rotation = 45,
		BorderSizePixel = 0,
		Parent = frame,
	})
	accent(diamond, "BackgroundColor3")

	text_label({
		Text = name,
		TextColor3 = colors.active_text,
		TextSize = 13,
		Position = UDim2.fromOffset(26, 7),
		Size = UDim2.new(1, -38, 0, 16),
		Parent = frame,
	})

	local rule = new("Frame", {
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -24, 0, 1),
		BorderSizePixel = 0,
		Parent = frame,
	}, {
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.6, 0.85), NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	accent(rule, "BackgroundColor3")

	local list = new("Frame", {
		Position = UDim2.fromOffset(12, 38),
		Size = UDim2.new(1, -24, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = frame,
	}, {
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local section = { name = name, tab = tab, frame = frame, list = list, elements = {}, order = 0 }

	function section:create_element(info, opts)
		return create_element(self, info, opts or {})
	end

	tab.sections[name] = section
	return section
end

-- > ( menu controls )

function menu.set_accent_color(color)
	colors.accent = color
	for _, entry in ipairs(accent_objects) do
		if entry[1].Parent then
			entry[1][entry[2]] = color
		end
	end
end

-- > ( book open / close )
-- A cover hinged on the menu's left edge (the spine). Closing: it swings shut across the
-- menu, accelerating like it's falling, then the closed book drops back and fades.
-- Opening: the closed book fades in, then the cover swings open from the spine.

local BOOK_W, BOOK_H = 575, 450
local BOOK_CLOSE_TIME = 0.7   -- cover swinging shut
local BOOK_OPEN_TIME = 0.65   -- cover swinging open
local BOOK_FADE_TIME = 0.35   -- closed book fading away / appearing

local book = new("Frame", {
	Name = "book_cover",
	AnchorPoint = Vector2.new(0, 0.5),
	Size = UDim2.fromOffset(0, BOOK_H),
	BackgroundColor3 = colors.section,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Visible = false,
	ZIndex = 10,
	Parent = screen,
}, { corner(3) })
local book_stroke = stroke(book, colors.accent)
accent(book_stroke, "Color")
local book_scale = new("UIScale", { Parent = book })

-- the cover's artwork stays full-size (it's revealed / hidden by the clipping, never squashed)
local book_art = new("Frame", {
	Size = UDim2.fromOffset(BOOK_W, BOOK_H),
	BackgroundTransparency = 1,
	ZIndex = 10,
	Parent = book,
})
local book_inset = new("Frame", {
	Position = UDim2.fromOffset(14, 14),
	Size = UDim2.new(1, -28, 1, -28),
	BackgroundTransparency = 1,
	ZIndex = 10,
	Parent = book_art,
}, { corner(2) })
local book_inset_stroke = stroke(book_inset, colors.accent)
accent(book_inset_stroke, "Color")
local book_title = text_label({
	Text = "cover",
	Font = TITLE_FONT,
	TextSize = 26,
	TextColor3 = Color3.new(1, 1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 80), -- nudged down a touch now there's no "beta" under it, keeps it centred
	Size = UDim2.fromOffset(240, 32),
	ZIndex = 11,
	Parent = book_art,
})
prism_gradients[#prism_gradients + 1] = new("UIGradient", { Rotation = 12, Parent = book_title })

-- the cover emblem, centred on the book. ONE crisp image only: the old glow was ~40 copies
-- nudged a few pixels around it, which smeared the thin chrome lines and made it look blurry.
-- A sheen sweeps across it in step with the cover swinging (drawn on the image itself, so no blur).
local EMBLEM_ID   = "rbxassetid://84183560823707"
local EMBLEM_SIZE = 200 -- px
local book_emblem = new("ImageLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, -40),
	Size = UDim2.fromOffset(EMBLEM_SIZE, EMBLEM_SIZE),
	BackgroundTransparency = 1,
	Image = EMBLEM_ID,
	ImageTransparency = 1,
	ScaleType = Enum.ScaleType.Fit,
	ZIndex = 11,
	Parent = book_art,
})
local book_emblem_scale = new("UIScale", { Parent = book_emblem })
local emblem_dim = Color3.fromRGB(218, 224, 234) -- barely dimmed, so the white sheen band reads
local emblem_sheen = new("UIGradient", {
	Rotation = 25,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, emblem_dim), ColorSequenceKeypoint.new(0.42, emblem_dim),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.58, emblem_dim), ColorSequenceKeypoint.new(1, emblem_dim),
	}),
	Parent = book_emblem,
})
local function apply_emblem(a, scale) -- a: 0 = solid, 1 = invisible
	book_emblem.ImageTransparency = a
	book_emblem_scale.Scale = scale
end

-- fold shading: darkest at the swinging edge while the cover is mid-air
local book_shade = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 12,
	Parent = book,
}, { new("UIGradient", { Transparency = NumberSequence.new(1, 0) }) })

-- whole cover's fade (0 = solid, 1 = invisible)
local function apply_book_fade(a)
	book.BackgroundTransparency = a
	book_stroke.Transparency = 0.45 + 0.55 * a
	book_inset_stroke.Transparency = 0.75 + 0.25 * a
	book_title.TextTransparency = a
end

-- The whole animation is ONE number, book_p, that only ever moves toward a target:
--   0 = menu open   ->   1 = cover shut over the menu   ->   2 = closed book faded away
-- Pressing K just flips the target, so spamming it reverses smoothly from wherever it
-- is - no restarts, no pops, no half-finished tweens fighting each other.
local book_p, book_target = 0, 0
menu.open = true

local function render_book(p)
	if p <= 0 then
		book.Visible = false
		main.Visible = true
		return
	end
	if p >= 2 then
		book.Visible = false
		main.Visible = false
		return
	end
	book.Visible = true
	book.Position = main.Position + UDim2.fromOffset(0, BOOK_H / 2) -- follows the menu
	if p <= 1 then
		-- swing: the cover turns from edge-on (0) to lying flat over the menu (1).
		-- width = W * sin(angle) is how a turning cover actually looks, and it moves fast
		-- through the thin "edge-on" stage instead of lingering as a black bar.
		local s = math.sin(p * math.pi / 2)
		local w = BOOK_W * s
		book.Size = UDim2.fromOffset(w, BOOK_H)
		book_stroke.Enabled = w > 4             -- no stray outline when it's paper-thin
		book_shade.BackgroundTransparency = 0.15 + 0.75 * s
		book_scale.Scale = 1
		apply_book_fade(0)
		-- light slides across the emblem as the cover swings; emblem settles into place as it lands
		emblem_sheen.Offset = Vector2.new(-0.9 + 1.8 * p, 0)
		apply_emblem(0, 0.92 + 0.08 * s)
		main.Visible = p < 1                    -- menu only hidden once fully covered
	else
		-- closed book drops back and fades
		local q = p - 1
		local e = q * q * (3 - 2 * q)           -- smooth in both directions
		book.Size = UDim2.fromOffset(BOOK_W, BOOK_H)
		book_stroke.Enabled = true
		book_shade.BackgroundTransparency = 0.9
		book_scale.Scale = 1 - 0.08 * e
		apply_book_fade(e)
		-- the emblem lingers a moment longer than the cover and drifts slightly larger,
		-- so it's the last thing to dissolve into the cold air
		emblem_sheen.Offset = Vector2.new(0.9, 0)
		apply_emblem(q ^ 2.2, 1 + 0.1 * e)
		main.Visible = false
	end
end

track(RunService.RenderStepped:Connect(function(dt)
	if book_p == book_target then return end
	local dir = book_target > book_p and 1 or -1
	-- swing (0..1) and fade (1..2) each run at their own speed, in either direction
	local in_swing = book_p < 1 or (book_p == 1 and dir < 0)
	local speed = in_swing and (1 / (dir > 0 and BOOK_CLOSE_TIME or BOOK_OPEN_TIME)) or (1 / BOOK_FADE_TIME)
	local np = book_p + dir * speed * dt
	if (book_p < 1 and np > 1) or (book_p > 1 and np < 1) then np = 1 end -- stop at the boundary, switch speed
	book_p = dir > 0 and math.min(np, book_target) or math.max(np, book_target)
	render_book(book_p)
end))

-- > ( roblox's own ui )
-- Roblox always draws its own UI (hotbar / inventory, chat, player list, top bar) above anything a
-- script makes, so the menu can't be layered over it. Instead it's hidden while the loader or menu
-- is up, and put back exactly as it was once the menu has finished closing.
local StarterGui = game:GetService("StarterGui")
local CORE_TYPES = {
	Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.EmotesMenu, Enum.CoreGuiType.Health,
}
local core_saved = nil -- what was enabled before we hid it (nil = currently not hidden)

function menu.hide_roblox_ui(hide)
	if hide then
		if core_saved then return end
		core_saved = {}
		for _, t in ipairs(CORE_TYPES) do
			local ok, was = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, t)
			core_saved[t] = ok and was or false
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, false)
		end
		pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", false)
	else
		if not core_saved then return end
		for _, t in ipairs(CORE_TYPES) do
			if core_saved[t] then pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, true) end
		end
		pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", true)
		core_saved = nil
	end
end

local core_restore_id = 0

function menu.toggle(visible)
	if visible == nil then
		visible = not menu.open
	end
	if visible == menu.open then
		return
	end
	menu.open = visible
	fx.set_open(visible) -- snow / frost / blur follow the menu
	book_target = visible and 0 or 2

	core_restore_id += 1
	if visible then
		menu.hide_roblox_ui(true)
	else
		-- bring Roblox's UI back once the book has finished closing (unless it's reopened first)
		local id = core_restore_id
		task.delay(BOOK_CLOSE_TIME + BOOK_FADE_TIME, function()
			if id == core_restore_id and not menu.open then menu.hide_roblox_ui(false) end
		end)
	end
end

function menu.is_menu_open()
	return menu.open
end

-- anything that changes the game (sky, materials...) registers an undo here; unload runs them all
menu.cleanup = {}

function menu.unload()
	for _, undo in ipairs(menu.cleanup) do
		pcall(undo)
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	screen:Destroy()
	fx.destroy()
	menu.hide_roblox_ui(false) -- give the hotbar / chat / etc. back
	local loader_blur = Lighting:FindFirstChild("LoaderBlur") -- in case it's unloaded mid-loader
	if loader_blur then loader_blur:Destroy() end
	_G.__cover_unload = nil
end

_G.__cover_unload = menu.unload

track(UserInputService.InputBegan:Connect(function(input, game_processed)
	if game_processed or menu.binding or menu.loading then -- toggle key is locked while the loader plays
		return
	end

	if input.KeyCode == menu.menu_key then
		menu.toggle()
	end

	for _, el in ipairs(key_listeners) do
		if el.key and input.KeyCode == el.key then
			el.on_key_press:Fire()
		end
	end
end))

local library = {
	menu = menu,
	signal = signal,
	flags = flags,
	create_connection = create_connection,
}

-- =====================================================================
-- > ( demo ui )  -  edit / replace everything below with your own stuff
-- =====================================================================

local main_group = menu.create_group("main")
main_group:create_tab("general")

local left = main_group:create_section("general", "options", 1)
local right = main_group:create_section("general", "visuals", 2)

local example_toggle = left:create_element({ name = "example toggle" }, {
	toggle = { flag = "example_toggle", default = false },
})

local example_slider = left:create_element({ name = "example slider" }, {
	slider = { flag = "example_slider", min = 0, max = 100, default = 50, suffix = "%", decimals = 0 },
})

local example_dropdown = left:create_element({ name = "example dropdown" }, {
	dropdown = { flag = "example_dropdown", options = { "one", "two", "three" }, default = { "one" }, requires_one = true },
})

local example_multi = left:create_element({ name = "multi dropdown" }, {
	dropdown = { flag = "example_multi", options = { "red", "green", "blue" }, multi = true },
})

local example_textbox = left:create_element({ name = "example textbox" }, {
	textbox = { flag = "example_textbox" },
})

local example_color = right:create_element({ name = "example color" }, {
	toggle = { flag = "example_color_enabled", default = true },
	colorpicker = {
		color_flag = "example_color",
		transparency_flag = "example_color_transparency",
		default_color = Color3.fromRGB(176, 214, 248),
	},
})

local example_key = right:create_element({ name = "example keybind" }, {
	keybind = { flag = "example_key", default = Enum.KeyCode.F },
})

local example_button = right:create_element({ name = "say hello" }, {
	button = {},
})

create_connection(example_toggle.on_toggle_change, function(value)
	print("toggle:", value)
end)
create_connection(example_slider.on_slider_change, function(value)
	print("slider:", value)
end)
create_connection(example_dropdown.on_dropdown_change, function(value)
	print("dropdown:", table.concat(value, ", "))
end)
create_connection(example_multi.on_dropdown_change, function(value)
	print("multi:", table.concat(value, ", "))
end)
create_connection(example_textbox.on_textbox_change, function(value)
	print("textbox:", value)
end)
create_connection(example_color.on_color_change, function(color)
	print("color:", color)
end)
create_connection(example_key.on_key_press, function()
	menu.new_notification("you pressed the example keybind", 1)
end)
create_connection(example_button.on_clicked, function()
	menu.new_notification("hello from the menu!", 1)
end)

-- =====================================================================
-- > ( world + player tabs )  -  client-side only: changes what YOU see, nothing else.
-- Weather presets, time of day, sky, clouds, fog, atmosphere, lighting, colour correction,
-- bloom / sun rays / motion blur and ground colours. Every change glides in smoothly, and
-- "reset everything" / unload hand the game its own look back exactly as it was.
-- =====================================================================
main_group:create_tab("player")
local world_group = menu.create_group("world")
world_group:create_tab("weather")
world_group:create_tab("sky")
world_group:create_tab("light")

local weather_section = world_group:create_section("weather", "weather", 1)
local time_section = world_group:create_section("weather", "environment", 1)
local config_section = world_group:create_section("weather", "configs", 1)
local particle_section = world_group:create_section("weather", "particles", 2)
local options_section = world_group:create_section("weather", "options", 2)
local sky_section = world_group:create_section("sky", "sky", 1)
local cloud_section = world_group:create_section("sky", "clouds", 1)
local fog_section = world_group:create_section("sky", "fog", 2)
local atmo_section = world_group:create_section("sky", "atmosphere", 2)
local light_section = world_group:create_section("light", "lighting", 1)
local ground_section = world_group:create_section("light", "ground", 1)
local grade_section = world_group:create_section("light", "colour correction", 2)
local effects_section = world_group:create_section("light", "visual effects", 2)
local trail_section = main_group:create_section("player", "trail", 1)
local flex_section = main_group:create_section("player", "flex", 2)

do
	local HttpService = game:GetService("HttpService")
	local Debris = game:GetService("Debris")
	local ICE = Color3.fromRGB(176, 214, 248)
	local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
	local running = true -- false after unload, so nothing delayed (thunder etc.) comes back
	local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
	local function camera_now() return workspace.CurrentCamera end

	-- =================================================================
	-- > helpers
	-- =================================================================
	local function lerp(a, b, t) return a + (b - a) * t end
	local function mix(a, b, t)
		if typeof(a) == "Color3" then return a:Lerp(b, t) end
		return a + (b - a) * t
	end
	local function smooth(t) return t * t * (3 - 2 * t) end
	local function rnd(range) return range[1] + math.random() * (range[2] - range[1]) end
	-- lerp the short way round a circle (clock hours, compass degrees)
	local function wrap_lerp(a, b, t, period)
		local d = (b - a) % period
		if d > period / 2 then d -= period end
		return (a + d * t) % period
	end
	local function same(a, b)
		if typeof(a) == "Color3" then
			return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.002
		elseif type(a) == "number" then
			return math.abs(a - b) < 1e-4
		end
		return a == b
	end
	-- only writes when the value really differs: cheap enough to run every frame, which also
	-- quietly wins against game scripts that keep pushing their own lighting
	local function put(inst, prop, value)
		local cur = inst[prop]
		if typeof(value) == "Color3" then
			if math.abs(cur.R - value.R) + math.abs(cur.G - value.G) + math.abs(cur.B - value.B) < 0.002 then return end
		elseif type(value) == "number" then
			if math.abs(cur - value) < 0.0005 then return end
		elseif cur == value then
			return
		end
		inst[prop] = value
	end
	local function try_set(inst, prop, value)
		pcall(function() inst[prop] = value end)
	end
	local function live(inst)
		return inst ~= nil and inst:IsDescendantOf(workspace)
	end
	-- the menu's own effects and everything we add are never treated as "the game's"
	local function reserved(name)
		return name == "MenuBlur" or name == "MenuCold" or name == "LoaderBlur" or name:sub(1, 5) == "Cover"
	end
	local function game_effect(class)
		for _, c in ipairs(Lighting:GetChildren()) do
			if c.ClassName == class and c.Enabled and not reserved(c.Name) then return c end
		end
		return nil
	end
	local function from(inst, prop, fallback)
		if inst then return inst[prop] end
		return fallback
	end
	local warned = {}
	local function guard(fn, ...) -- one broken piece never stops the rest (and only complains once)
		local ok, err = pcall(fn, ...)
		if not ok and not warned[err] then
			warned[err] = true
			warn("[cover] " .. tostring(err))
		end
	end
	local function daylight() -- 0 at night, 1 in the middle of the day
		return math.clamp(math.sin((Lighting.ClockTime - 6) / 12 * math.pi) * 1.6 + 0.2, 0, 1)
	end

	-- =================================================================
	-- > state
	-- S = what the controls say. A = what's on screen right now; it glides toward S.
	-- The starting values are read from the game, so every slider opens on what you see.
	-- =================================================================
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local g_atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	local g_clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	local g_cc, g_bloom, g_rays = game_effect("ColorCorrectionEffect"), game_effect("BloomEffect"), game_effect("SunRaysEffect")

	local D = {
		-- weather
		transition = 3, wind_on = false, wind = 8, wind_dir = 45, gusts = true,
		particles = true, splashes = true, lightning = false, sounds = true, volume = 60,
		rain = 0, rain_color = rgb(205, 220, 240),
		snow = 0, snow_color = rgb(246, 250, 255), drift = 0,
		petals = 0, petal_color = rgb(255, 190, 212),
		leaves = 0, mist = 0, butterflies = 0,
		fireflies = 0, firefly_color = rgb(214, 255, 120),
		-- options
		quality = "high", distance = 90, hide_indoors = true, clear_view = false,
		-- environment
		time_on = false, clock = Lighting.ClockTime, cycle = false, cycle_len = 12, latitude = Lighting.GeographicLatitude,
		-- sky + clouds
		sky_on = false, sky_name = "clear skies", sky_custom = "", auto_sky = true, sky_spin = false, spin_speed = 6,
		hide_sun = false, hide_moon = false, hide_stars = false,
		clouds_on = false, cloud_cover = from(g_clouds, "Cover", 0.5), cloud_density = from(g_clouds, "Density", 0.7),
		cloud_color = from(g_clouds, "Color", WHITE),
		-- fog
		fog_on = false, fog_style = "soft", fog_color = Lighting.FogColor, fog_density = 0.55, fog_haze = 2.5,
		fog_start = 0, fog_end = 350,
		-- atmosphere
		atmo_on = false, atmo_density = from(g_atmo, "Density", 0.3), atmo_offset = from(g_atmo, "Offset", 0.25),
		atmo_haze = from(g_atmo, "Haze", 1), atmo_glare = from(g_atmo, "Glare", 0),
		atmo_color = from(g_atmo, "Color", rgb(199, 199, 199)), atmo_decay = from(g_atmo, "Decay", rgb(106, 112, 125)),
		-- lighting
		light_on = false, brightness = Lighting.Brightness, exposure = Lighting.ExposureCompensation,
		shadows = Lighting.GlobalShadows, shadow_soft = Lighting.ShadowSoftness,
		ambient = Lighting.Ambient, outdoor = Lighting.OutdoorAmbient,
		shift_top = Lighting.ColorShift_Top, shift_bottom = Lighting.ColorShift_Bottom,
		diffuse = Lighting.EnvironmentDiffuseScale, specular = Lighting.EnvironmentSpecularScale,
		-- colour correction + effects
		cc_on = false, cc_brightness = from(g_cc, "Brightness", 0), cc_contrast = from(g_cc, "Contrast", 0),
		cc_saturation = from(g_cc, "Saturation", 0), cc_tint = from(g_cc, "TintColor", WHITE),
		bloom_on = false, bloom_intensity = from(g_bloom, "Intensity", 0.4), bloom_threshold = from(g_bloom, "Threshold", 1.6),
		bloom_size = from(g_bloom, "Size", 28),
		rays_on = false, rays_intensity = from(g_rays, "Intensity", 0.1), rays_spread = from(g_rays, "Spread", 0.7),
		mblur_on = false, mblur_strength = 50, mblur_max = 10,
		-- ground
		ground_on = false, ground_color = rgb(240, 246, 255), ground_amount = 60,
		grass_on = false, grass_color = rgb(110, 160, 76),
		mat_on = false, material = "smooth plastic", recolor_on = false, recolor = ICE,
	}
	-- view / performance settings that presets, configs and reset leave alone
	local KEEP = {
		transition = true, particles = true, splashes = true, sounds = true, volume = true, quality = true,
		distance = true, hide_indoors = true, clear_view = true, auto_sky = true, cycle_len = true,
	}

	-- switches fade (0..1) instead of snapping; these numbers + colours glide
	local MIXES = { "wind_on", "time_on", "clouds_on", "fog_on", "atmo_on", "light_on", "cc_on", "bloom_on", "rays_on", "mblur_on", "ground_on", "grass_on" }
	local IS_MIX = {}
	for _, k in ipairs(MIXES) do IS_MIX[k] = true end
	local WRAPS = { clock = 24, wind_dir = 360 }
	local BLENDED = table.clone(MIXES)
	for _, k in ipairs({
		"clock", "wind_dir", "wind", "latitude", "cloud_cover", "cloud_density", "cloud_color",
		"fog_color", "fog_density", "fog_haze", "fog_start", "fog_end",
		"atmo_density", "atmo_offset", "atmo_haze", "atmo_glare", "atmo_color", "atmo_decay",
		"brightness", "exposure", "shadow_soft", "ambient", "outdoor", "shift_top", "shift_bottom", "diffuse", "specular",
		"cc_brightness", "cc_contrast", "cc_saturation", "cc_tint", "bloom_intensity", "bloom_threshold", "bloom_size",
		"rays_intensity", "rays_spread", "mblur_strength", "mblur_max", "ground_color", "ground_amount", "grass_color",
		"rain", "rain_color", "snow", "snow_color", "drift", "petals", "petal_color", "leaves", "mist", "butterflies",
		"fireflies", "firefly_color", "volume",
	}) do
		BLENDED[#BLENDED + 1] = k
	end

	local S, A = {}, {}
	for k, v in pairs(D) do S[k] = v end
	local function target(k)
		if IS_MIX[k] then return S[k] and 1 or 0 end
		return S[k]
	end
	for _, k in ipairs(BLENDED) do A[k] = target(k) end

	local function close(k, a, b)
		local p = WRAPS[k]
		if p then
			local d = math.abs(a - b) % p
			return math.min(d, p - d) < 1e-3
		end
		return same(a, b)
	end

	-- presets / configs / reset: everything moves together over `transition` seconds.
	-- Touching a control mid-way just changes where that value is heading.
	local blend = nil
	local function start_blend(seconds)
		local from_values = {}
		for _, k in ipairs(BLENDED) do from_values[k] = A[k] end
		blend = { t = 0, dur = math.max(seconds or 0, 0.05), from = from_values }
	end

	local function step_values(dt)
		if blend then
			blend.t = math.min(blend.t + dt / blend.dur, 1)
			local e = smooth(blend.t)
			for _, k in ipairs(BLENDED) do
				local p = WRAPS[k]
				if p then
					A[k] = wrap_lerp(blend.from[k], target(k), e, p)
				else
					A[k] = mix(blend.from[k], target(k), e)
				end
			end
			if blend.t >= 1 then blend = nil end
			return
		end
		-- no preset running: single changes (dragging a slider) glide in quickly
		local f = 1 - math.exp(-dt * 9)
		for _, k in ipairs(BLENDED) do
			local goal, cur = target(k), A[k]
			if cur ~= goal then
				if close(k, cur, goal) then
					A[k] = goal
				else
					local p = WRAPS[k]
					A[k] = p and wrap_lerp(cur, goal, f, p) or mix(cur, goal, f)
				end
			end
		end
	end

	-- =================================================================
	-- > controls <-> state
	-- =================================================================
	local ui = {}     -- key -> { el, kind }
	local OWNER = {}  -- key -> the section switch that turns on when you change it
	local hooks = {}  -- key -> function(by_user) run after it changes
	local syncing = false

	local function sync(key)
		local b = ui[key]
		if not b then return end
		local v = S[key]
		syncing = true
		pcall(function()
			if b.kind == "toggle" then
				b.el:set_toggle(v)
			elseif b.kind == "slider" then
				b.el:set_slider(v)
			elseif b.kind == "color" then
				b.el:set_colorpicker(v)
			elseif b.kind == "dropdown" then
				b.el:set_dropdown(v ~= "" and { v } or {})
			elseif b.kind == "text" then
				b.el:set_textbox(v)
			end
		end)
		syncing = false
	end
	local function sync_all()
		for key in pairs(ui) do sync(key) end
	end
	local function changed(key, by_user)
		local h = hooks[key]
		if h then h(by_user) end
	end
	local function user_set(key, value)
		if syncing then return end
		S[key] = value
		local owner = OWNER[key]
		if owner and value ~= false and not S[owner] then
			S[owner] = true -- moving a slider in a switched-off section switches it on
			sync(owner)
			changed(owner, true)
		end
		changed(key, true)
	end
	local function set_many(values)
		local touched = {}
		for k, v in pairs(values) do
			if S[k] ~= v then
				S[k] = v
				touched[#touched + 1] = k
			end
		end
		sync_all()
		for _, k in ipairs(touched) do changed(k, false) end
	end

	local function bind(el, kind, key, owner)
		ui[key] = { el = el, kind = kind }
		OWNER[key] = owner
		local sig = (kind == "toggle" and el.on_toggle_change) or (kind == "slider" and el.on_slider_change)
			or (kind == "color" and el.on_color_change) or (kind == "dropdown" and el.on_dropdown_change)
			or el.on_textbox_change
		create_connection(sig, function(v)
			if kind == "dropdown" then v = v[1] or "" end
			if kind == "text" then v = v or "" end
			user_set(key, v)
		end)
		sync(key)
		return el
	end
	local function toggle(section, name, key, owner)
		return bind(section:create_element({ name = name }, {
			toggle = { flag = "env_" .. key, default = S[key] },
		}), "toggle", key, owner)
	end
	local function slider(section, name, key, min, max, decimals, suffix, owner)
		return bind(section:create_element({ name = name }, {
			slider = { flag = "env_" .. key, min = min, max = max, default = S[key], decimals = decimals, suffix = suffix },
		}), "slider", key, owner)
	end
	local function color(section, name, key, owner)
		return bind(section:create_element({ name = name }, {
			colorpicker = { color_flag = "env_" .. key, transparency_flag = "env_" .. key .. "_t", default_color = S[key] },
		}), "color", key, owner)
	end
	local function toggle_color(section, name, key, color_key) -- switch + colour on one row
		local el = section:create_element({ name = name }, {
			toggle = { flag = "env_" .. key, default = S[key] },
			colorpicker = { color_flag = "env_" .. color_key, transparency_flag = "env_" .. color_key .. "_t", default_color = S[color_key] },
		})
		bind(el, "toggle", key)
		bind(el, "color", color_key, key)
		return el
	end
	local function slider_color(section, name, key, color_key, suffix) -- 0-100 amount + colour on one row
		local el = section:create_element({ name = name }, {
			colorpicker = { color_flag = "env_" .. color_key, transparency_flag = "env_" .. color_key .. "_t", default_color = S[color_key] },
			slider = { flag = "env_" .. key, min = 0, max = 100, default = S[key], decimals = 0, suffix = suffix },
		})
		bind(el, "slider", key)
		bind(el, "color", color_key)
		return el
	end
	local function dropdown(section, name, key, options, owner)
		return bind(section:create_element({ name = name }, {
			dropdown = { flag = "env_" .. key, options = options, default = { S[key] }, requires_one = true },
		}), "dropdown", key, owner)
	end
	local function textbox(section, name, key)
		return bind(section:create_element({ name = name }, {
			textbox = { flag = "env_" .. key, default = S[key] },
		}), "text", key)
	end

	-- =================================================================
	-- > time of day + lighting
	-- =================================================================
	local LIGHT_KEYS = {
		Brightness = "brightness", ExposureCompensation = "exposure", ShadowSoftness = "shadow_soft",
		Ambient = "ambient", OutdoorAmbient = "outdoor", ColorShift_Top = "shift_top", ColorShift_Bottom = "shift_bottom",
		EnvironmentDiffuseScale = "diffuse", EnvironmentSpecularScale = "specular",
	}
	local light_base, time_base = nil, nil

	local function apply_time()
		local m = A.time_on
		if m <= 0 then
			if time_base then
				put(Lighting, "ClockTime", time_base.clock)
				put(Lighting, "GeographicLatitude", time_base.lat)
				time_base = nil
			end
			return
		end
		time_base = time_base or { clock = Lighting.ClockTime, lat = Lighting.GeographicLatitude }
		put(Lighting, "ClockTime", wrap_lerp(time_base.clock, A.clock, m, 24))
		put(Lighting, "GeographicLatitude", lerp(time_base.lat, A.latitude, m))
	end

	local function apply_lighting()
		local m = A.light_on
		if m <= 0 then
			if light_base then
				for prop, value in pairs(light_base) do put(Lighting, prop, value) end
				light_base = nil
			end
			return
		end
		if not light_base then
			light_base = { GlobalShadows = Lighting.GlobalShadows }
			for prop in pairs(LIGHT_KEYS) do light_base[prop] = Lighting[prop] end
		end
		for prop, key in pairs(LIGHT_KEYS) do put(Lighting, prop, mix(light_base[prop], A[key], m)) end
		put(Lighting, "GlobalShadows", if m >= 0.5 then S.shadows else light_base.GlobalShadows)
	end

	-- =================================================================
	-- > fog + atmosphere
	-- Soft fog is drawn by the Atmosphere (it takes over density, haze and colour).
	-- Distance fog (start / end) only shows in Roblox when there is NO Atmosphere, so while
	-- it's on, any atmosphere is set aside and put back afterwards.
	-- =================================================================
	local ATMO_PROPS = { "Density", "Offset", "Haze", "Glare", "Color", "Decay" }
	local atmo, atmo_ours, atmo_base = nil, false, nil
	local fog_parked, fog_base = nil, nil

	local function release_atmosphere()
		if atmo then
			if atmo_ours then
				atmo:Destroy()
			elseif atmo_base and atmo.Parent then
				for _, p in ipairs(ATMO_PROPS) do put(atmo, p, atmo_base[p]) end
			end
		end
		atmo, atmo_ours, atmo_base = nil, false, nil
	end

	local function apply_fog_and_atmosphere()
		local dist = (S.fog_style == "distance") and A.fog_on or 0
		if dist > 0.001 then
			if not fog_parked then
				fog_parked = {}
				for _, c in ipairs(Lighting:GetChildren()) do
					if c:IsA("Atmosphere") then
						fog_parked[#fog_parked + 1] = c
						c.Parent = nil
					end
				end
			end
			fog_base = fog_base or { start = Lighting.FogStart, finish = Lighting.FogEnd, color = Lighting.FogColor }
			local a, b = math.max(fog_base.finish, 1), math.max(A.fog_end, A.fog_start + 1, 1)
			put(Lighting, "FogStart", lerp(fog_base.start, A.fog_start, dist))
			put(Lighting, "FogEnd", math.exp(lerp(math.log(a), math.log(b), dist))) -- eases in from "no fog" naturally
			put(Lighting, "FogColor", fog_base.color:Lerp(A.fog_color, dist))
			return
		end
		if fog_base then
			Lighting.FogStart, Lighting.FogEnd, Lighting.FogColor = fog_base.start, fog_base.finish, fog_base.color
			fog_base = nil
		end
		if fog_parked then
			for _, c in ipairs(fog_parked) do pcall(function() c.Parent = Lighting end) end
			fog_parked = nil
		end

		local m = A.atmo_on
		local f = (S.fog_style == "soft") and A.fog_on or 0
		if math.max(m, f) <= 0.0005 then
			release_atmosphere()
			return
		end
		if not atmo or not atmo.Parent then
			release_atmosphere()
			local g = Lighting:FindFirstChildOfClass("Atmosphere")
			if g then -- drive the game's own atmosphere rather than stacking a second one
				atmo, atmo_ours, atmo_base = g, false, {}
				for _, p in ipairs(ATMO_PROPS) do atmo_base[p] = g[p] end
			else
				atmo_base = { Density = 0, Offset = A.atmo_offset, Haze = 0, Glare = 0, Color = A.atmo_color, Decay = A.atmo_decay }
				atmo = Instance.new("Atmosphere")
				atmo.Name = "CoverAtmosphere"
				for p, v in pairs(atmo_base) do atmo[p] = v end
				atmo.Parent = Lighting
				atmo_ours = true
			end
		end
		local b = atmo_base
		local density = lerp(lerp(b.Density, A.atmo_density, m), A.fog_density, f)
		local haze = lerp(lerp(b.Haze, A.atmo_haze, m), A.fog_haze, f)
		local tint = b.Color:Lerp(A.atmo_color, m):Lerp(A.fog_color, f)
		put(atmo, "Density", density)
		put(atmo, "Haze", haze)
		put(atmo, "Color", tint)
		put(atmo, "Offset", lerp(b.Offset, A.atmo_offset, m))
		put(atmo, "Glare", lerp(b.Glare, A.atmo_glare, m))
		put(atmo, "Decay", b.Decay:Lerp(A.atmo_decay, m))
	end

	-- =================================================================
	-- > colour correction, bloom, sun rays
	-- If the game has its own effect, ours starts from its values and the game's one is
	-- switched off while ours shows (no double bloom); both come back on reset.
	-- =================================================================
	local function effect_driver(class, our_name, props, neutral)
		local d = { inst = nil, base = nil, off = {} }
		function d.release()
			if d.inst then d.inst:Destroy() end
			d.inst = nil
			for _, c in ipairs(d.off) do
				if c.Parent then c.Enabled = true end
			end
			table.clear(d.off)
			d.base = nil
		end
		function d.apply(m, goal)
			if m <= 0.0005 then
				if d.inst then d.release() end
				return
			end
			if not d.inst or not d.inst.Parent then
				d.release()
				for _, c in ipairs(Lighting:GetChildren()) do
					if c.ClassName == class and c.Enabled and not reserved(c.Name) then
						if not d.base then
							d.base = {}
							for _, p in ipairs(props) do d.base[p] = c[p] end
						end
						c.Enabled = false
						d.off[#d.off + 1] = c
					end
				end
				d.base = d.base or neutral
				d.inst = Instance.new(class)
				d.inst.Name = our_name
				for _, p in ipairs(props) do d.inst[p] = d.base[p] end
				d.inst.Parent = Lighting
			end
			for _, p in ipairs(props) do put(d.inst, p, mix(d.base[p], goal[p], m)) end
		end
		return d
	end
	local grade_fx = effect_driver("ColorCorrectionEffect", "CoverGrade", { "Brightness", "Contrast", "Saturation", "TintColor" },
		{ Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE })
	local bloom_fx = effect_driver("BloomEffect", "CoverBloom", { "Intensity", "Size", "Threshold" },
		{ Intensity = 0, Size = 24, Threshold = 2 })
	local rays_fx = effect_driver("SunRaysEffect", "CoverRays", { "Intensity", "Spread" }, { Intensity = 0, Spread = 1 })
	local cc_goal, bloom_goal, rays_goal = {}, {}, {}

	local function apply_effects()
		cc_goal.Brightness, cc_goal.Contrast, cc_goal.Saturation, cc_goal.TintColor = A.cc_brightness, A.cc_contrast, A.cc_saturation, A.cc_tint
		grade_fx.apply(A.cc_on, cc_goal)
		bloom_goal.Intensity, bloom_goal.Size, bloom_goal.Threshold = A.bloom_intensity, A.bloom_size, A.bloom_threshold
		bloom_fx.apply(A.bloom_on, bloom_goal)
		rays_goal.Intensity, rays_goal.Spread = A.rays_intensity, A.rays_spread
		rays_fx.apply(A.rays_on, rays_goal)
	end

	-- motion blur: the world blurs while the view turns quickly, and clears when it's still.
	-- (It only looks at how fast the view turns; it never moves or changes the camera.)
	local mblur, last_look, blur_now = nil, nil, 0
	local function apply_motion_blur(dt)
		local m = A.mblur_on
		if m <= 0.0005 then
			if mblur then mblur:Destroy() end
			mblur, last_look, blur_now = nil, nil, 0
			return
		end
		local cam = camera_now()
		if not cam then return end
		if not mblur or not mblur.Parent then
			mblur = Instance.new("BlurEffect")
			mblur.Name = "CoverMotionBlur"
			mblur.Size = 0
			mblur.Parent = Lighting
		end
		local look = cam.CFrame.LookVector
		local speed = 0
		if last_look and dt > 0 then
			speed = math.deg(math.acos(math.clamp(last_look:Dot(look), -1, 1))) / dt -- degrees turned per second
		end
		last_look = look
		local goal = math.clamp((speed - 20) * A.mblur_strength / 100 * 0.06, 0, A.mblur_max)
		blur_now += (goal - blur_now) * (1 - math.exp(-dt * (goal > blur_now and 20 or 8)))
		put(mblur, "Size", blur_now * m)
	end

	-- =================================================================
	-- > clouds (Roblox's moving 3D clouds) + wind
	-- =================================================================
	local clouds, clouds_ours, clouds_base = nil, false, nil
	local function release_clouds()
		if clouds then
			if clouds_ours then
				clouds:Destroy()
			elseif clouds_base and clouds.Parent then
				clouds.Cover, clouds.Density, clouds.Color, clouds.Enabled = clouds_base.Cover, clouds_base.Density, clouds_base.Color, clouds_base.Enabled
			end
		end
		clouds, clouds_ours, clouds_base = nil, false, nil
	end
	local function apply_clouds()
		local m = A.clouds_on
		local t = workspace:FindFirstChildOfClass("Terrain")
		if m <= 0.0005 or not t then
			release_clouds()
			return
		end
		if not clouds or not clouds.Parent then
			release_clouds()
			local g = t:FindFirstChildOfClass("Clouds")
			if g then
				clouds, clouds_ours = g, false
				clouds_base = { Cover = g.Cover, Density = g.Density, Color = g.Color, Enabled = g.Enabled }
				g.Enabled = true
			else
				local ok, c = pcall(Instance.new, "Clouds")
				if not ok then return end
				c.Name = "CoverClouds"
				c.Cover = 0
				c.Density = A.cloud_density
				c.Color = A.cloud_color
				c.Parent = t
				clouds, clouds_ours = c, true
				clouds_base = { Cover = 0, Density = A.cloud_density, Color = A.cloud_color, Enabled = true }
			end
		end
		local start_cover = clouds_base.Enabled and clouds_base.Cover or 0
		put(clouds, "Cover", lerp(start_cover, A.cloud_cover, m))
		put(clouds, "Density", lerp(clouds_base.Density, A.cloud_density, m))
		put(clouds, "Color", clouds_base.Color:Lerp(A.cloud_color, m))
	end

	-- wind sways the grass and clouds (Workspace.GlobalWind) and pushes all weather particles
	local has_global_wind = pcall(function() return workspace.GlobalWind end)
	local wind_base = nil
	local wind_flat = Vector3.zero -- wind right now, gusts included (studs / second)
	local function apply_wind(now)
		local m = A.wind_on
		local dir = math.rad(A.wind_dir) + math.noise(now * 0.11, 8.1) * 0.35
		local gust = 1
		if S.gusts then gust = 1 + 0.85 * math.clamp(math.noise(now * 0.23, 3.7) * 2.2, 0, 1) end
		local v = Vector3.new(math.cos(dir), 0, math.sin(dir)) * (A.wind * gust)
		wind_flat = v * m
		if not has_global_wind then return end
		if m <= 0.0005 then
			if wind_base then
				workspace.GlobalWind = wind_base
				wind_base = nil
			end
			return
		end
		wind_base = wind_base or workspace.GlobalWind
		workspace.GlobalWind = wind_base:Lerp(v, m)
	end

	-- =================================================================
	-- > ground: terrain colours, grass, and grass / dirt / rock parts (snow cover, autumn, ...)
	-- plus the material override + part recolour
	-- =================================================================
	local MATERIALS, BY_NAME = {}, {}
	for _, m in ipairs(Enum.Material:GetEnumItems()) do
		if m ~= Enum.Material.Air and m ~= Enum.Material.Water then
			local name = (m.Name:gsub("(%l)(%u)", "%1 %2")):lower()
			MATERIALS[#MATERIALS + 1] = name
			BY_NAME[name] = m
		end
	end
	table.sort(MATERIALS)
	local function material_set(names)
		local t = {}
		for _, n in ipairs(names) do
			local ok, m = pcall(function() return Enum.Material[n] end)
			if ok and m then t[m] = true end
		end
		return t
	end
	local GRASSY = material_set({ "Grass", "LeafyGrass" })
	local NATURAL = material_set({ "Grass", "LeafyGrass", "Ground", "Mud", "Sand", "Sandstone", "Rock", "Slate", "Basalt", "Limestone", "Pebble" })
	local TERRAIN_MATS = {}
	for m in pairs(material_set({
		"Grass", "LeafyGrass", "Ground", "Mud", "Sand", "Sandstone", "Rock", "Slate", "Basalt", "Limestone", "Glacier",
		"Snow", "Ice", "Salt", "Pavement", "Asphalt", "Concrete", "Cobblestone", "Brick", "WoodPlanks", "CrackedLava",
	})) do
		TERRAIN_MATS[#TERRAIN_MATS + 1] = m
	end

	local terrain_base, terrain_last = nil, {}
	local function apply_terrain()
		local t = workspace:FindFirstChildOfClass("Terrain")
		if not t then return end
		if A.ground_on <= 0.0005 and A.grass_on <= 0.0005 then
			if terrain_base then
				for m, c in pairs(terrain_base) do pcall(t.SetMaterialColor, t, m, c) end
				terrain_base = nil
				table.clear(terrain_last)
			end
			return
		end
		if not terrain_base then
			terrain_base = {}
			for _, m in ipairs(TERRAIN_MATS) do
				local ok, c = pcall(t.GetMaterialColor, t, m)
				if ok then terrain_base[m] = c end
			end
		end
		local cover = A.ground_on * A.ground_amount / 100
		for m, c in pairs(terrain_base) do
			if GRASSY[m] then c = c:Lerp(A.grass_color, A.grass_on) end
			c = c:Lerp(A.ground_color, cover)
			local last = terrain_last[m]
			if not last or not same(last, c) then
				terrain_last[m] = c
				pcall(t.SetMaterialColor, t, m, c)
			end
		end
	end

	local originals = setmetatable({}, { __mode = "k" }) -- part -> { material, colour } as the game had it
	local want_scan = false
	local function in_character(p)
		local m = p:FindFirstAncestorOfClass("Model")
		while m do
			if m:FindFirstChildOfClass("Humanoid") then return true end
			m = m:FindFirstAncestorOfClass("Model")
		end
		return false
	end
	local function eligible(p) -- our own effects and characters are never restyled
		return not p:IsA("Terrain") and p.Name:sub(1, 5) ~= "Cover" and not in_character(p)
	end
	local function ground_live()
		return S.ground_on or S.grass_on or A.ground_on > 0.0005 or A.grass_on > 0.0005
	end
	local function style(p)
		local o = originals[p]
		local mat0 = o and o[1] or p.Material
		local touched = S.mat_on or S.recolor_on or (NATURAL[mat0] and ground_live())
		if not o then
			if not touched then return end
			o = { p.Material, p.Color }
			originals[p] = o
		end
		local c = o[2]
		if NATURAL[o[1]] then
			if GRASSY[o[1]] then c = c:Lerp(A.grass_color, A.grass_on) end
			c = c:Lerp(A.ground_color, A.ground_on * A.ground_amount / 100)
		end
		if S.recolor_on then c = S.recolor end
		put(p, "Material", (S.mat_on and BY_NAME[S.material]) or o[1])
		put(p, "Color", c)
		if not touched then originals[p] = nil end
	end
	local function refresh_parts(full)
		if full then
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("BasePart") and eligible(d) then style(d) end
			end
		else
			for p in pairs(originals) do
				if p.Parent then style(p) else originals[p] = nil end
			end
		end
	end
	track(workspace.DescendantAdded:Connect(function(d)
		if not running or not d:IsA("BasePart") or d.Name:sub(1, 5) == "Cover" then return end
		if S.mat_on or S.recolor_on or ground_live() then
			task.defer(function()
				if d.Parent and eligible(d) then style(d) end
			end)
		end
	end))

	-- =================================================================
	-- > sky
	-- =================================================================
	local FACES = { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }
	local function ids(list)
		local t = {}
		for i, f in ipairs(FACES) do t[f] = "rbxassetid://" .. list[i] end
		return t
	end
	-- skyboxes (faces in Bk, Dn, Ft, Lf, Rt, Up order); "pink sky" is the one from assets/pinksky.rbxm
	local SKIES = {
		["pink sky"] = { faces = ids({ "271042516", "271077243", "271042556", "271042310", "271042467", "271077958" }), celestial = true, stars = 3000 },
		["aurora galaxy"] = { faces = ids({ "116533337330584", "80054106187171", "94459139270943", "116368999680791", "125758104196312", "107060226443967" }), celestial = false, stars = 0 },
		["spiral galaxy"] = { faces = ids({ "93576969602662", "93417581920199", "95464508714623", "99158734858405", "84970344864364", "73682095754881" }), celestial = false, stars = 0 },
		["purple nebula"] = { faces = ids({ "99468191699832", "121098906941255", "106290292308760", "102557334804626", "97361097874537", "138727520721658" }), celestial = true, stars = 5000, sun = 0 },
		["red nebula"] = { faces = ids({ "136149603528111", "74002901302689", "135270030298862", "77841693246314", "126049982712804", "76131365430373" }), celestial = true, stars = 5000, sun = 0 },
		["deep space"] = { faces = ids({ "155441936", "155441802", "155441818", "155441777", "155441874", "155441905" }), celestial = false, stars = 0 },
		["aesthetic night"] = { faces = ids({ "1045964490", "1045964368", "1045964655", "1045964655", "1045964655", "1045962969" }), celestial = false, stars = 0 },
		["epic night"] = { faces = ids({ "12064107", "12064152", "12064121", "12063984", "12064115", "12064131" }), celestial = false, stars = 0 },
		["night fog"] = { faces = ids({ "1370717244", "1370717336", "1370717438", "1370717567", "1370717698", "1370717782" }), celestial = false, stars = 0 },
		["fog on water"] = { faces = ids({ "15876597103", "15876592775", "15876640231", "15876638420", "15876595486", "15876639348" }), celestial = false, stars = 3000 },
		["snowy"] = { faces = ids({ "155657655", "155674246", "155657609", "155657671", "155657619", "155674931" }), celestial = false, stars = 3000 },
		["golden sunset"] = { faces = ids({ "541743453", "541743443", "541743446", "541743436", "541743435", "541743441" }), celestial = true, stars = 3000 },
		["cloudy sunrise"] = { faces = ids({ "326525401", "326524980", "326525556", "326524781", "326539957", "326542795" }), celestial = true, stars = 3000 },
		["clear skies"] = { faces = ids({ "91458024", "91457980", "91458024", "91458024", "91458024", "91458002" }), celestial = true, stars = 1500 },
		["stylized mountains"] = { faces = ids({ "122076196453002", "129469057577973", "139156344241065", "122849389458893", "92579064446840", "96364407339806" }), celestial = true, stars = 3000, sun = 11 },
		["vaporwave"] = { faces = ids({ "643264941", "643264941", "643264941", "643264941", "643264941", "643264941" }), celestial = true, stars = 3000 },
	}
	local SKY_ORDER = {
		"clear skies", "pink sky", "golden sunset", "cloudy sunrise", "snowy", "fog on water", "night fog", "epic night",
		"aesthetic night", "stylized mountains", "aurora galaxy", "spiral galaxy", "purple nebula", "red nebula",
		"deep space", "vaporwave", "classic", "game sky", "custom id",
	}
	local CLASSIC = {}
	for _, f in ipairs(FACES) do CLASSIC[f] = "rbxasset://textures/sky/sky512_" .. f:lower() .. ".tex" end

	local parked = nil   -- the game's own Sky objects, set aside while ours shows
	local ours = nil     -- our Sky
	local cel_made = nil -- a plain Sky we add only to hide sun / moon / stars when the game has none
	local spun = nil     -- { sky, original orientation }
	local spin_angle = 0
	local sky_dirty = false
	local base_of = setmetatable({}, { __mode = "k" }) -- sky -> its own sun size / moon size / star count

	local function base(s)
		local b = base_of[s]
		if not b then
			b = { sun = s.SunAngularSize, moon = s.MoonAngularSize, stars = s.StarCount }
			base_of[s] = b
		end
		return b
	end

	local function stop_spin()
		if spun and spun[1].Parent then
			pcall(function() spun[1].SkyboxOrientation = spun[2] end)
		end
		spun = nil
	end

	local function apply_celestial()
		local any = S.hide_sun or S.hide_moon or S.hide_stars
		local t = ours or Lighting:FindFirstChildOfClass("Sky")
		if any and not t then
			cel_made = Instance.new("Sky")
			cel_made.Name = "CoverCelestial"
			cel_made.Parent = Lighting
			t = cel_made
		end
		if not any and cel_made and t == cel_made then
			cel_made:Destroy()
			cel_made = nil
			return
		end
		if not t then return end
		local b = base(t)
		t.SunAngularSize = S.hide_sun and 0 or b.sun
		t.MoonAngularSize = S.hide_moon and 0 or b.moon
		t.StarCount = S.hide_stars and 0 or b.stars
	end

	local function custom_faces() -- one id = all six sides, six ids = Bk Dn Ft Lf Rt Up
		local list = {}
		for id in tostring(S.sky_custom):gmatch("%d%d%d%d+") do list[#list + 1] = id end
		if #list == 0 then return nil end
		local t = {}
		for i, f in ipairs(FACES) do t[f] = "rbxassetid://" .. (#list >= 6 and list[i] or list[1]) end
		return t
	end

	local function apply_faces()
		if not ours then return end
		local game_sky = parked and parked[1]
		local preset = SKIES[S.sky_name]
		local custom = S.sky_name == "custom id" and custom_faces()
		if custom then
			for _, f in ipairs(FACES) do ours["Skybox" .. f] = custom[f] end
			ours.CelestialBodiesShown = true
			base_of[ours] = { sun = 21, moon = 11, stars = 3000 }
		elseif preset then
			for _, f in ipairs(FACES) do ours["Skybox" .. f] = preset.faces[f] end
			ours.CelestialBodiesShown = preset.celestial
			base_of[ours] = { sun = preset.sun or 21, moon = 11, stars = preset.stars }
		elseif S.sky_name == "game sky" and game_sky then
			for _, f in ipairs(FACES) do ours["Skybox" .. f] = game_sky["Skybox" .. f] end
			ours.SunTextureId, ours.MoonTextureId = game_sky.SunTextureId, game_sky.MoonTextureId
			ours.CelestialBodiesShown = game_sky.CelestialBodiesShown
			local gb = base(game_sky)
			base_of[ours] = { sun = gb.sun, moon = gb.moon, stars = gb.stars }
		else
			for _, f in ipairs(FACES) do ours["Skybox" .. f] = CLASSIC[f] end
			ours.CelestialBodiesShown = true
			base_of[ours] = { sun = 21, moon = 11, stars = 3000 }
		end
		apply_celestial()
	end

	local function apply_sky()
		if S.sky_on then
			if cel_made then
				cel_made:Destroy()
				cel_made = nil
			end
			if not parked then
				stop_spin()
				parked = {}
				for _, c in ipairs(Lighting:GetChildren()) do
					if c:IsA("Sky") then
						parked[#parked + 1] = c
						c.Parent = nil
					end
				end
			end
			if not ours then
				ours = Instance.new("Sky")
				ours.Name = "CoverSky"
				ours.Parent = Lighting
			end
			apply_faces()
		else
			if ours then
				ours:Destroy()
				ours = nil
			end
			if parked then
				for _, s in ipairs(parked) do pcall(function() s.Parent = Lighting end) end
				parked = nil
			end
			apply_celestial()
		end
	end

	local function spin_step(dt)
		if not S.sky_spin then return end
		local t = ours or Lighting:FindFirstChildOfClass("Sky")
		if not t then return end
		if not spun or spun[1] ~= t then
			stop_spin()
			local ok, o = pcall(function() return t.SkyboxOrientation end)
			if not ok then return end -- this Roblox version can't rotate skyboxes
			spun = { t, o }
			spin_angle = o.Y
		end
		spin_angle = (spin_angle + S.spin_speed * dt) % 360
		local o = spun[2]
		pcall(function() t.SkyboxOrientation = Vector3.new(o.X, spin_angle, o.Z) end)
	end

	-- =================================================================
	-- > weather particles
	-- rain / snow / drift / mist / fireflies: particle emitters that follow the camera.
	-- petals / leaves / butterflies: small 3D parts, pooled, all moved in one batch per frame.
	-- =================================================================
	local RAIN_TEX = "rbxassetid://3806148993"
	local SPLASH_TEX = "rbxassetid://270368855"
	local DROP_TEX = "rbxasset://textures/particles/sparkles_main.dds"
	local SOFT_TEX = "rbxasset://textures/particles/smoke_main.dds"
	local RAIN_SOUND = "rbxassetid://9064263922"
	local WIND_SOUND = "rbxasset://sounds/action_falling.mp3"
	local THUNDER_SOUND = "rbxasset://sounds/impact_water.mp3" -- slowed right down + echo = distant rumble

	-- rate = particle multiplier, splash = splash multiplier, bits = max petals / leaves, flies = max butterflies
	local QUALITY = {
		low = { rate = 0.35, splash = 0.3, bits = 60, flies = 4 },
		medium = { rate = 0.65, splash = 0.6, bits = 110, flies = 7 },
		high = { rate = 1, splash = 1, bits = 170, flies = 10 },
		ultra = { rate = 1.5, splash = 1.4, bits = 260, flies = 14 },
	}
	local function quality() return QUALITY[S.quality] or QUALITY.high end

	local wx_folder = nil
	local function folder()
		if not (wx_folder and wx_folder:IsDescendantOf(workspace)) then
			if wx_folder then wx_folder:Destroy() end
			wx_folder = Instance.new("Folder")
			wx_folder.Name = "CoverWeather"
			wx_folder.Parent = camera_now() or workspace
		end
		return wx_folder
	end

	-- what's under you (ground height) and above you (a roof = indoors), checked 4x a second
	local ray_params = RaycastParams.new()
	ray_params.FilterType = Enum.RaycastFilterType.Exclude
	local probe = { t = 0, ground = 0, outdoor = 1, goal = 1 }
	local function update_probes(dt, cam_pos)
		probe.t -= dt
		if probe.t <= 0 then
			probe.t = 0.25
			local list = {}
			local cam = camera_now()
			local char = local_player and local_player.Character
			if cam then list[#list + 1] = cam end
			if char then list[#list + 1] = char end
			ray_params.FilterDescendantsInstances = list
			local down = workspace:Raycast(cam_pos + Vector3.new(0, 2, 0), Vector3.new(0, -600, 0), ray_params)
			probe.ground = down and down.Position.Y or cam_pos.Y - 30
			local up = S.hide_indoors and workspace:Raycast(cam_pos, Vector3.new(0, 150, 0), ray_params)
			probe.goal = up and 0 or 1
		end
		probe.outdoor += (probe.goal - probe.outdoor) * (1 - math.exp(-dt * 3))
	end
	local function ground_at(x, z, top)
		local hit = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -500, 0), ray_params)
		return hit and hit.Position.Y or nil
	end

	local function seq(...) -- seq(v) or seq(t0, v0, t1, v1, ...)
		local a = { ... }
		if #a == 1 then return NumberSequence.new(a[1]) end
		local keys = {}
		for i = 1, #a, 2 do keys[#keys + 1] = NumberSequenceKeypoint.new(a[i], a[i + 1]) end
		return NumberSequence.new(keys)
	end
	local function spread(v, env) -- a size that varies a little per particle
		return NumberSequence.new({ NumberSequenceKeypoint.new(0, v, env), NumberSequenceKeypoint.new(1, v, env) })
	end
	local function emitter_part(name)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Transparency = 1
		p.Size = Vector3.new(4, 1, 4)
		p.Parent = folder()
		return p
	end
	local function emitter(parent, props)
		local e = Instance.new("ParticleEmitter")
		e.Rate = 0
		pcall(function() e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume end) -- fill the whole box
		for k, v in pairs(props) do try_set(e, k, v) end
		e.Parent = parent
		return e
	end

	local BUILD = {}
	function BUILD.rain()
		local part = emitter_part("CoverRain")
		local at = Instance.new("Attachment") -- one movable point: each landing drop moves it there and bursts
		at.Name = "CoverSplash"
		local s = { part = part, at = at, owned = { part, at } }
		s.e = emitter(part, {
			Texture = RAIN_TEX, EmissionDirection = Enum.NormalId.Bottom, Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
			Speed = NumberRange.new(150, 175), Lifetime = NumberRange.new(0.55, 0.65), Size = seq(2.6),
			Transparency = seq(0, 1, 0.1, 0.45, 0.9, 0.45, 1, 1), LightEmission = 0.1, LightInfluence = 0.9,
		})
		s.puff = emitter(at, {
			Texture = SPLASH_TEX, Speed = NumberRange.new(0), Lifetime = NumberRange.new(0.18, 0.26),
			Size = seq(0, 0.25, 1, 0.9), Transparency = seq(0, 0.3, 1, 1), LightInfluence = 0.9,
		})
		s.bits = emitter(at, { -- tiny droplets bouncing back up
			Texture = DROP_TEX, EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(40, 40),
			Speed = NumberRange.new(5, 9), Acceleration = Vector3.new(0, -55, 0), Lifetime = NumberRange.new(0.22, 0.38),
			Size = seq(0, 0.09, 1, 0.04), Transparency = seq(0, 0.15, 1, 1),
			Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = seq(1.4), LightInfluence = 0.9,
		})
		at.Parent = workspace:FindFirstChildOfClass("Terrain") or part
		s.tinted = { s.e, s.puff, s.bits }
		return s
	end
	function BUILD.snow()
		local part = emitter_part("CoverSnow")
		local s = { part = part, owned = { part } }
		s.e = emitter(part, {
			Texture = SOFT_TEX, EmissionDirection = Enum.NormalId.Bottom, Speed = NumberRange.new(2, 4),
			Drag = 0.55, Lifetime = NumberRange.new(13, 17), Size = spread(0.26, 0.1),
			Transparency = seq(0, 1, 0.06, 0.08, 0.88, 0.08, 1, 1),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-80, 80),
			LightEmission = 0.35, LightInfluence = 0.75,
		})
		s.tinted = { s.e }
		return s
	end
	function BUILD.drift() -- blizzard: snow streaking sideways along the ground
		local part = emitter_part("CoverDrift")
		local s = { part = part, owned = { part } }
		s.e = emitter(part, {
			Texture = SOFT_TEX, Speed = NumberRange.new(0, 1), SpreadAngle = Vector2.new(180, 180), Drag = 3,
			Lifetime = NumberRange.new(1.2, 2.4), Orientation = Enum.ParticleOrientation.VelocityParallel,
			Size = spread(0.5, 0.2), Squash = seq(1.6), Transparency = seq(0, 1, 0.2, 0.55, 0.8, 0.6, 1, 1),
			LightEmission = 0.3, LightInfluence = 0.8,
		})
		s.tinted = { s.e }
		return s
	end
	function BUILD.mist() -- low, slow, very faint clouds hugging the ground
		local part = emitter_part("CoverMist")
		local s = { part = part, owned = { part } }
		s.e = emitter(part, {
			Texture = SOFT_TEX, EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(180, 180), Drag = 0.4, Lifetime = NumberRange.new(9, 13),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 12, 4), NumberSequenceKeypoint.new(1, 18, 5) }),
			Transparency = seq(0, 1, 0.25, 0.88, 0.75, 0.9, 1, 1),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-8, 8),
			LightEmission = 0, LightInfluence = 1,
		})
		s.tinted = { s.e }
		return s
	end
	function BUILD.fireflies() -- small glowing specks that drift and blink near the ground
		local part = emitter_part("CoverFireflies")
		local s = { part = part, owned = { part } }
		s.e = emitter(part, {
			Texture = DROP_TEX, Speed = NumberRange.new(0.2, 0.8), SpreadAngle = Vector2.new(180, 180), Drag = 0.6,
			Acceleration = Vector3.new(0, 0.1, 0), Lifetime = NumberRange.new(4, 7),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.15, 0.2, 0.06),
				NumberSequenceKeypoint.new(0.85, 0.2, 0.06), NumberSequenceKeypoint.new(1, 0),
			}),
			Transparency = seq(0, 1, 0.12, 0.05, 0.26, 0.75, 0.4, 0.05, 0.55, 0.6, 0.7, 0.05, 0.86, 0.7, 1, 1),
			Rotation = NumberRange.new(0, 360), LightEmission = 1, LightInfluence = 0, Brightness = 3,
		})
		s.tinted = { s.e }
		return s
	end

	local systems = {}
	local function drop_system(name)
		local s = systems[name]
		if not s then return end
		for _, inst in ipairs(s.owned) do inst:Destroy() end
		systems[name] = nil
	end
	local function system(name)
		local s = systems[name]
		if s and live(s.part) and (not s.at or live(s.at)) then return s end
		drop_system(name)
		s = BUILD[name]()
		systems[name] = s
		return s
	end
	local function tint_system(s, c)
		if s.color and same(s.color, c) then return end
		s.color = c
		local cs = ColorSequence.new(c)
		for _, e in ipairs(s.tinted) do e.Color = cs end
	end

	-- petals + leaves: flat ovals that flutter, tumble, drift with the wind, land, lie there a
	-- moment and fade, then start again near you
	local FALLERS = {
		petals = { name = "CoverPetal", size = Vector3.new(0.34, 0.05, 0.27), fall = { 1.6, 2.8 }, sway = { 0.8, 2 },
			spin = { 1.5, 4 }, wind = 0.9, rest = { 2, 4.5 }, alpha = 0.04 },
		leaves = { name = "CoverLeaf", size = Vector3.new(0.56, 0.05, 0.36), fall = { 2.4, 4.4 }, sway = { 1, 2.6 },
			spin = { 2, 6 }, wind = 0.75, rest = { 3, 6 }, alpha = 0 },
	}
	local LEAF_COLORS = {
		rgb(214, 120, 38), rgb(196, 74, 34), rgb(232, 176, 52), rgb(160, 92, 40), rgb(178, 52, 36), rgb(226, 148, 44), rgb(204, 160, 70),
	}
	local FLY_COLORS = { rgb(255, 255, 255), rgb(255, 214, 120), rgb(170, 210, 255), rgb(255, 170, 205), rgb(255, 150, 70), rgb(200, 170, 255) }
	local pools = {}
	local flies = nil
	local move_parts, move_cfs, move_n = {}, {}, 0
	local function queue_move(p, cf)
		move_n += 1
		move_parts[move_n] = p
		move_cfs[move_n] = cf
	end
	local function new_bit(name, size, c)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.SmoothPlastic
		p.Size = size
		p.Color = c
		p.Transparency = 1
		local mesh = Instance.new("SpecialMesh") -- a squashed sphere: soft oval petal / leaf / wing
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 0.5, 1)
		mesh.Parent = p
		return p
	end
	local function bit_color(kind, i)
		if kind == "leaves" then return LEAF_COLORS[i % #LEAF_COLORS + 1] end
		return A.petal_color:Lerp(WHITE, (i % 7) / 7 * 0.45)
	end

	local function spawn_bit(cfg, b, cam_cf, R, anywhere)
		local cam_pos = cam_cf.Position
		local ang
		if math.random() < 0.7 then -- most of them in front of you, where they're actually seen
			local look = cam_cf.LookVector
			ang = math.atan2(look.Z, look.X) + (math.random() - 0.5) * math.rad(140)
		else
			ang = math.random() * math.pi * 2
		end
		local d = math.sqrt(math.random()) * R
		local x = cam_pos.X + math.cos(ang) * d - wind_flat.X * cfg.wind * 3 -- start upwind so they drift across you
		local z = cam_pos.Z + math.sin(ang) * d - wind_flat.Z * cfg.wind * 3
		local g = ground_at(x, z, cam_pos.Y + 80) or probe.ground
		local top = math.max(math.min(g + 45, cam_pos.Y + 40), g + 8)
		b.ground = g
		b.pos = Vector3.new(x, anywhere and lerp(g + 1, top, math.random()) or top - math.random() * 8, z)
		local axis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		b.axis = axis.Magnitude > 0.05 and axis.Unit or Vector3.yAxis
		b.angle = math.random() * math.pi * 2
		b.spin = rnd(cfg.spin) * (math.random() < 0.5 and -1 or 1)
		b.fall, b.sway = rnd(cfg.fall), rnd(cfg.sway)
		b.freq, b.phase = 1.2 + math.random() * 1.8, math.random() * math.pi * 2
		b.rest, b.alpha, b.dead = 0, 0, false
	end

	local function step_pool(kind, amount, dt, now, cam_cf, R)
		local cfg = FALLERS[kind]
		local pool = pools[kind]
		local want = math.floor(quality().bits * amount + 0.5)
		if want <= 0 and not pool then return end
		if pool and not live(pool.folder) then
			pool = nil
			pools[kind] = nil
		end
		if not pool then
			local f = Instance.new("Folder")
			f.Name = "Cover" .. kind
			f.Parent = folder()
			pool = { folder = f, parts = {}, bits = {}, color = nil }
			pools[kind] = pool
		end
		local parts, bits = pool.parts, pool.bits
		while #parts < want do
			local i = #parts + 1
			local p = new_bit(cfg.name, cfg.size, bit_color(kind, i))
			p.Parent = pool.folder
			parts[i] = p
			bits[i] = {}
			spawn_bit(cfg, bits[i], cam_cf, R, true)
		end
		if kind == "petals" and not (pool.color and same(pool.color, A.petal_color)) then
			pool.color = A.petal_color
			for i, p in ipairs(parts) do p.Color = bit_color(kind, i) end
		end

		local cam_pos = cam_cf.Position
		local far = (R * 1.3) ^ 2
		local alive = 0
		for i, p in ipairs(parts) do
			local b = bits[i]
			if b.dead then
				if i > want then continue end
				spawn_bit(cfg, b, cam_cf, R, false)
				p.Transparency = 1
			end
			alive += 1
			if b.rest > 0 then
				-- lying on the ground: wait, fade out, then start again (or retire if fewer are wanted)
				b.rest -= dt
				if b.rest < 1 then p.Transparency = lerp(cfg.alpha, 1, 1 - math.max(b.rest, 0)) end
				if b.rest <= 0 then
					if i <= want then spawn_bit(cfg, b, cam_cf, R, false) else b.dead = true end
					p.Transparency = 1
				end
			else
				local sway = math.sin(now * b.freq + b.phase)
				local drift = sway * b.sway
				local pos = b.pos + Vector3.new(
					wind_flat.X * cfg.wind + math.cos(b.phase) * drift,
					-b.fall * (0.55 + 0.45 * math.abs(sway)), -- glides when flat, drops when edge-on
					wind_flat.Z * cfg.wind + math.sin(b.phase) * drift
				) * dt
				b.pos = pos
				b.angle += b.spin * dt
				if b.alpha < 1 then
					b.alpha = math.min(b.alpha + dt * 1.5, 1)
					p.Transparency = lerp(1, cfg.alpha, b.alpha)
				end
				local dx, dz = pos.X - cam_pos.X, pos.Z - cam_pos.Z
				if dx * dx + dz * dz > far then -- blown too far / you moved away: start again near you
					if i <= want then spawn_bit(cfg, b, cam_cf, R, false) else b.dead = true end
					p.Transparency = 1
				elseif pos.Y <= b.ground + 0.03 then -- landed: lie flat for a moment
					b.rest = rnd(cfg.rest)
					queue_move(p, CFrame.new(pos.X, b.ground + 0.03, pos.Z)
						* CFrame.Angles((math.random() - 0.5) * 0.25, b.angle, (math.random() - 0.5) * 0.25))
				else
					queue_move(p, CFrame.new(pos) * CFrame.fromAxisAngle(b.axis, b.angle) * CFrame.Angles(sway * 0.8, 0, 0))
				end
			end
		end
		if want == 0 and alive == 0 then -- all landed and none wanted: free the parts
			pool.folder:Destroy()
			pools[kind] = nil
		end
	end

	-- butterflies: lazy wandering flight near you during the day, wings flapping
	local function place_fly(f, cam_pos)
		local a, d = math.random() * math.pi * 2, 6 + math.random() * 14
		local x, z = cam_pos.X + math.cos(a) * d, cam_pos.Z + math.sin(a) * d
		f.ground = ground_at(x, z, cam_pos.Y + 30) or probe.ground
		f.pos = Vector3.new(x, f.ground + 1.5 + math.random() * 3, z)
		f.target, f.height, f.retarget = f.pos, 2, 0
	end
	local function step_flies(amount, dt, now, cam_pos)
		local light = math.clamp((daylight() - 0.15) / 0.3, 0, 1)
		local want = math.floor(quality().flies * amount * light + 0.5)
		if want <= 0 and not flies then return end
		if flies and not live(flies.folder) then flies = nil end
		if not flies then
			local f = Instance.new("Folder")
			f.Name = "CoverButterflies"
			f.Parent = folder()
			flies = { folder = f, list = {} }
		end
		local list = flies.list
		while #list < want do
			local i = #list + 1
			local c = FLY_COLORS[i % #FLY_COLORS + 1]
			local f = {
				body = new_bit("CoverButterfly", Vector3.new(0.07, 0.07, 0.3), rgb(40, 34, 30)),
				l = new_bit("CoverButterfly", Vector3.new(0.34, 0.05, 0.3), c),
				r = new_bit("CoverButterfly", Vector3.new(0.34, 0.05, 0.3), c),
				head = Vector3.xAxis, speed = 3 + math.random() * 2, phase = math.random() * math.pi * 2, gt = math.random(),
			}
			for _, p in ipairs({ f.body, f.l, f.r }) do
				p.Transparency = 0
				p.Parent = flies.folder
			end
			place_fly(f, cam_pos)
			list[i] = f
		end
		while #list > want do
			local f = table.remove(list)
			f.body:Destroy()
			f.l:Destroy()
			f.r:Destroy()
		end
		if #list == 0 then
			flies.folder:Destroy()
			flies = nil
			return
		end
		for _, f in ipairs(list) do
			f.retarget -= dt
			if f.retarget <= 0 then
				f.retarget = 1.5 + math.random() * 2.5
				local a, d = math.random() * math.pi * 2, 5 + math.random() * 16
				f.target = Vector3.new(cam_pos.X + math.cos(a) * d, 0, cam_pos.Z + math.sin(a) * d)
				f.height = 1.2 + math.random() * 4
			end
			f.gt -= dt
			if f.gt <= 0 then
				f.gt = 0.8 + math.random() * 0.6
				f.ground = ground_at(f.pos.X, f.pos.Z, f.pos.Y + 6) or f.ground
			end
			local to = Vector3.new(f.target.X, f.ground + f.height, f.target.Z) - f.pos
			if to.Magnitude > 0.05 then f.head = f.head:Lerp(to.Unit, 1 - math.exp(-dt * 2.2)) end
			if f.head.Magnitude < 0.05 then f.head = Vector3.xAxis end
			local bob = math.sin(now * 3 + f.phase) * 0.9
			f.pos += f.head.Unit * f.speed * dt + Vector3.new(0, bob * dt, 0) + wind_flat * 0.15 * dt
			if (f.pos - cam_pos).Magnitude > 45 then place_fly(f, cam_pos) end
			local flat = Vector3.new(f.head.X, 0, f.head.Z)
			if flat.Magnitude < 0.05 then flat = Vector3.xAxis end
			local body = CFrame.lookAt(f.pos, f.pos + flat) * CFrame.Angles(math.rad(-15), 0, 0)
			local flap = math.rad(-20 + 90 * (0.5 + 0.5 * math.sin(now * 22 + f.phase)))
			queue_move(f.body, body)
			queue_move(f.l, body * CFrame.Angles(0, 0, -flap) * CFrame.new(-0.18, 0, 0))
			queue_move(f.r, body * CFrame.Angles(0, 0, flap) * CFrame.new(0.18, 0, 0))
		end
	end

	-- lightning: a jagged bolt far off, a double flash over everything, thunder a moment later
	local flash, flash_t, thunder_wait = nil, 10, 4
	local function flash_level(t)
		if t < 0.06 then return 0.5 elseif t < 0.12 then return 0.06 elseif t < 0.18 then return 0.38 end
		return 0.38 * math.exp(-(t - 0.18) * 7)
	end
	local function strike(cam_pos)
		if not (flash and flash.Parent) then
			flash = Instance.new("ColorCorrectionEffect")
			flash.Name = "CoverFlash"
			flash.Brightness = 0
			flash.Parent = Lighting
		end
		flash_t = 0
		local a = math.random() * math.pi * 2
		local dist = 250 + math.random() * 350
		local bx, bz = cam_pos.X + math.cos(a) * dist, cam_pos.Z + math.sin(a) * dist
		local top = Vector3.new(bx, cam_pos.Y + 260, bz)
		local bottom = Vector3.new(bx, ground_at(bx, bz, cam_pos.Y + 300) or (cam_pos.Y - 20), bz)
		local bolt, last = {}, top
		for i = 1, 10 do
			local p = top:Lerp(bottom, i / 10)
			if i < 10 then p += Vector3.new((math.random() - 0.5) * 34, 0, (math.random() - 0.5) * 34) end
			local seg = Instance.new("Part")
			seg.Name = "CoverBolt"
			seg.Anchored, seg.CanCollide, seg.CanQuery, seg.CanTouch, seg.CastShadow = true, false, false, false, false
			seg.Material = Enum.Material.Neon
			seg.Color = rgb(225, 235, 255)
			seg.Size = Vector3.new(1.3, 1.3, (p - last).Magnitude + 1)
			seg.CFrame = CFrame.lookAt((last + p) / 2, p)
			seg.Parent = folder()
			bolt[#bolt + 1] = seg
			last = p
		end
		task.delay(0.08, function() for _, seg in ipairs(bolt) do seg.Transparency = 0.7 end end)
		task.delay(0.14, function() for _, seg in ipairs(bolt) do seg.Transparency = 0 end end)
		task.delay(0.24, function() for _, seg in ipairs(bolt) do seg:Destroy() end end)
		if S.sounds then
			task.delay(dist / 320, function() -- sound lags behind the light, like the real thing
				if not running or not S.sounds then return end
				local s = Instance.new("Sound")
				s.Name = "CoverThunder"
				s.SoundId = THUNDER_SOUND
				s.PlaybackSpeed = 0.15 + math.random() * 0.06
				s.Volume = S.volume / 100 * 2.4 * (1.2 - dist / 800)
				local eq = Instance.new("EqualizerSoundEffect")
				eq.HighGain, eq.MidGain, eq.LowGain = -40, -10, 8
				eq.Parent = s
				local verb = Instance.new("ReverbSoundEffect")
				verb.DecayTime, verb.Density, verb.Diffusion = 5, 1, 1
				verb.Parent = s
				s.Parent = folder()
				s:Play()
				Debris:AddItem(s, 12)
			end)
		end
	end

	local loops = {}
	local function loop_sound(name, id, volume, speed)
		local s = loops[name]
		if volume <= 0.002 then
			if s then s:Destroy() end
			loops[name] = nil
			return
		end
		if not live(s) then
			s = Instance.new("Sound")
			s.Name = name
			s.SoundId = id
			s.Looped = true
			s.Volume = 0
			s.Parent = folder()
			s:Play()
			loops[name] = s
		end
		put(s, "Volume", volume)
		if speed then put(s, "PlaybackSpeed", speed) end
	end

	local splash_budget = 0
	local function weather_step(dt, now)
		local cam = camera_now()
		if not cam then return end
		local on = S.particles and 1 or 0
		local rain_a = A.rain / 100 * on
		local snow_a = A.snow / 100 * on
		local wind_speed = wind_flat.Magnitude
		local drift_a = A.drift / 100 * on * math.clamp(wind_speed / 20, 0, 1)
		local mist_a = A.mist / 100 * on
		local petal_a = A.petals / 100 * on
		local leaf_a = A.leaves / 100 * on
		local fly_a = A.butterflies / 100 * on
		local ff_a = A.fireflies / 100 * on * (0.15 + 0.85 * (1 - daylight()))
		local vol = (S.sounds and running) and S.volume / 100 or 0
		local wind_vol = vol * A.wind_on * math.clamp((wind_speed - 4) / 30, 0, 1) * 0.5
		local busy = rain_a + snow_a + drift_a + mist_a + petal_a + leaf_a + fly_a + ff_a + wind_vol > 0.0005
		if not busy and not next(systems) and not next(pools) and not flies and not flash and not next(loops) then
			return -- nothing running: no rays, no work
		end

		local cam_cf = cam.CFrame
		local cam_pos = cam_cf.Position
		update_probes(dt, cam_pos)
		local out = probe.outdoor
		local R = S.distance
		local q = quality()
		move_n = 0
		table.clear(move_parts)
		table.clear(move_cfs)

		-- rain: a sheet of falling streaks above you, tilted by the wind, plus splashes where drops land
		if rain_a > 0.001 then
			local s = system("rain")
			local r = math.min(R, 85)
			local up = -Vector3.new(wind_flat.X, -160, wind_flat.Z).Unit
			s.part.Size = Vector3.new(r * 2, 1, r * 2)
			s.part.CFrame = CFrame.fromMatrix(cam_pos + Vector3.new(0, 55, 0) - wind_flat * 0.3, up:Cross(Vector3.zAxis).Unit, up)
			put(s.e, "Rate", math.min(0.18 * (2 * r) ^ 2 * rain_a * q.rate * out, 6000))
			tint_system(s, A.rain_color)
			if S.splashes then
				splash_budget += dt * rain_a * 900 * q.splash * out
				local n = math.min(math.floor(splash_budget), 40)
				splash_budget -= n
				local sr = math.min(r, 55)
				for _ = 1, n do
					local a, d = math.random() * math.pi * 2, math.sqrt(math.random()) * sr
					local hit = workspace:Raycast(cam_pos + Vector3.new(math.cos(a) * d, 60, math.sin(a) * d), Vector3.new(0, -400, 0), ray_params)
					if hit then
						s.at.WorldPosition = hit.Position + hit.Normal * 0.05
						s.puff:Emit(1)
						s.bits:Emit(math.random(2, 4))
					end
				end
			else
				splash_budget = 0
			end
		else
			drop_system("rain")
		end

		-- snow: soft flakes drifting down; the wind carries them (drag pulls them up to wind speed)
		if snow_a > 0.001 then
			local s = system("snow")
			local r = math.min(R, 140)
			s.part.Size = Vector3.new(r * 2, 1, r * 2)
			s.part.CFrame = CFrame.new(cam_pos + Vector3.new(0, 42, 0) - wind_flat * 4)
			put(s.e, "Rate", math.min(0.0075 * (2 * r) ^ 2 * snow_a * q.rate * out, 2500))
			put(s.e, "Acceleration", Vector3.new(wind_flat.X * 0.38, -1.4, wind_flat.Z * 0.38))
			tint_system(s, A.snow_color)
		else
			drop_system("snow")
		end

		if drift_a > 0.001 then
			local s = system("drift")
			local r = math.min(R, 70)
			s.part.Size = Vector3.new(r * 2, 8, r * 2)
			s.part.CFrame = CFrame.new(Vector3.new(cam_pos.X, probe.ground + 4, cam_pos.Z) - wind_flat * 1.2)
			put(s.e, "Rate", math.min(0.02 * (2 * r) ^ 2 * drift_a * q.rate * out, 900))
			put(s.e, "Acceleration", Vector3.new(wind_flat.X * 2.08, -0.4, wind_flat.Z * 2.08))
			tint_system(s, A.snow_color)
		else
			drop_system("drift")
		end

		if mist_a > 0.001 then
			local s = system("mist")
			local r = math.min(R, 120)
			s.part.Size = Vector3.new(r * 2, 4, r * 2)
			s.part.CFrame = CFrame.new(cam_pos.X, probe.ground + 2.5, cam_pos.Z)
			put(s.e, "Rate", math.min(0.00028 * (2 * r) ^ 2 * mist_a * q.rate, 60))
			put(s.e, "Acceleration", Vector3.new(wind_flat.X * 0.17, 0, wind_flat.Z * 0.17))
			local soft_fog = S.fog_on and S.fog_style == "soft"
			tint_system(s, (soft_fog and A.fog_color or A.atmo_color):Lerp(WHITE, 0.25))
		else
			drop_system("mist")
		end

		if ff_a > 0.001 then
			local s = system("fireflies")
			local r = math.min(R, 45)
			s.part.Size = Vector3.new(r * 2, 7, r * 2)
			s.part.CFrame = CFrame.new(cam_pos.X, probe.ground + 4, cam_pos.Z)
			put(s.e, "Rate", math.min(0.002 * (2 * r) ^ 2 * ff_a * q.rate, 40))
			tint_system(s, A.firefly_color)
		else
			drop_system("fireflies")
		end

		step_pool("petals", petal_a, dt, now, cam_cf, R)
		step_pool("leaves", leaf_a, dt, now, cam_cf, R)
		step_flies(fly_a, dt, now, cam_pos)
		if move_n > 0 then
			workspace:BulkMoveTo(move_parts, move_cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end

		-- storms: strikes come more often the heavier the rain
		local storm = S.lightning and math.clamp(rain_a, 0, 1) or 0
		if storm > 0.2 then
			thunder_wait -= dt
			if thunder_wait <= 0 then
				thunder_wait = (5 + math.random() * 12) / (0.4 + storm)
				strike(cam_pos)
			end
		end
		if flash then
			flash_t += dt
			flash.Brightness = flash_level(flash_t) * (0.6 + 0.4 * out)
			if flash_t > 2 and storm <= 0.2 then
				flash:Destroy()
				flash = nil
			end
		end

		loop_sound("CoverRainSound", RAIN_SOUND, rain_a * vol * (0.35 + 0.65 * out))
		loop_sound("CoverWindSound", WIND_SOUND, wind_vol * (0.4 + 0.6 * out), 0.55 + math.clamp(wind_speed / 80, 0, 0.5))
	end

	local function weather_release()
		for name in pairs(systems) do drop_system(name) end
		for kind, pool in pairs(pools) do
			pool.folder:Destroy()
			pools[kind] = nil
		end
		if flies then
			flies.folder:Destroy()
			flies = nil
		end
		for name, s in pairs(loops) do
			s:Destroy()
			loops[name] = nil
		end
		if flash then
			flash:Destroy()
			flash = nil
		end
		if wx_folder then
			wx_folder:Destroy()
			wx_folder = nil
		end
	end

	-- =================================================================
	-- > presets: each one moves every system at once.
	-- PRESET_BASE is the shared starting point; each preset only lists what makes it different.
	-- =================================================================
	local PRESET_BASE = {
		wind_on = true, wind = 6, gusts = true,
		rain = 0, snow = 0, drift = 0, petals = 0, leaves = 0, mist = 0, butterflies = 0, fireflies = 0, lightning = false,
		time_on = true,
		clouds_on = true, cloud_cover = 0.45, cloud_density = 0.6, cloud_color = WHITE,
		fog_on = false,
		atmo_on = true, atmo_offset = 0.25, atmo_glare = 0,
		light_on = true, exposure = 0, shadows = true, shadow_soft = 0.25, shift_top = BLACK, shift_bottom = BLACK,
		diffuse = 1, specular = 0.6,
		cc_on = true, cc_brightness = 0, cc_contrast = 0, cc_saturation = 0, cc_tint = WHITE,
		bloom_on = true, bloom_intensity = 0.4, bloom_threshold = 1.6, bloom_size = 28,
		rays_on = true, rays_intensity = 0.06, rays_spread = 0.6,
		ground_on = false, ground_amount = 60, grass_on = false,
	}
	local PRESETS = {
		clear = {
			sky = "clear skies", clock = 13, wind = 4,
			brightness = 2.6, ambient = rgb(92, 96, 106), outdoor = rgb(140, 146, 156),
			atmo_density = 0.24, atmo_offset = 0.3, atmo_haze = 0.4, atmo_color = rgb(199, 220, 245), atmo_decay = rgb(106, 142, 184),
			cloud_cover = 0.35, cloud_density = 0.55,
			cc_saturation = 0.08, cc_contrast = 0.04,
			bloom_intensity = 0.3, bloom_threshold = 1.8, rays_intensity = 0.05,
		},
		sakura = {
			sky = "pink sky", clock = 15.4, wind = 5,
			brightness = 2.4, ambient = rgb(112, 92, 102), outdoor = rgb(166, 140, 152), shift_top = rgb(60, 28, 40),
			atmo_density = 0.33, atmo_offset = 0.2, atmo_haze = 2.2, atmo_glare = 0.6, atmo_color = rgb(255, 206, 224), atmo_decay = rgb(226, 150, 182),
			cloud_cover = 0.4, cloud_color = rgb(255, 234, 242),
			cc_tint = rgb(255, 242, 247), cc_saturation = 0.12, cc_brightness = 0.02,
			bloom_intensity = 0.55, bloom_threshold = 1.4, bloom_size = 30, rays_intensity = 0.12, rays_spread = 0.7,
			petals = 70, butterflies = 70, fireflies = 35,
			grass_on = true, grass_color = rgb(112, 172, 82),
		},
		snow = {
			sky = "snowy", clock = 11.5, wind = 6,
			brightness = 2.2, exposure = 0.15, ambient = rgb(122, 130, 142), outdoor = rgb(172, 180, 194), specular = 0.5,
			atmo_density = 0.38, atmo_offset = 0.15, atmo_haze = 1.4, atmo_color = rgb(225, 234, 246), atmo_decay = rgb(150, 165, 190),
			cloud_cover = 0.75, cloud_density = 0.7, cloud_color = rgb(235, 240, 248),
			cc_tint = rgb(236, 243, 255), cc_saturation = -0.15, cc_contrast = 0.02, cc_brightness = 0.02,
			bloom_intensity = 0.35, rays_intensity = 0.04,
			snow = 55,
			ground_on = true, ground_color = rgb(240, 246, 255), ground_amount = 72, grass_on = true, grass_color = rgb(226, 236, 242),
		},
		blizzard = {
			sky = "snowy", clock = 13, wind = 34,
			brightness = 1.6, exposure = 0.1, ambient = rgb(132, 140, 152), outdoor = rgb(172, 182, 196), shadow_soft = 0.6, specular = 0.4,
			atmo_density = 0.6, atmo_offset = 0, atmo_haze = 3, atmo_color = rgb(225, 232, 242), atmo_decay = rgb(180, 190, 205),
			cloud_cover = 1, cloud_density = 0.9, cloud_color = rgb(200, 208, 220),
			cc_tint = rgb(230, 238, 255), cc_saturation = -0.35, cc_contrast = -0.04, cc_brightness = 0.03,
			bloom_intensity = 0.25, rays_intensity = 0,
			snow = 100, drift = 80,
			ground_on = true, ground_color = rgb(242, 247, 255), ground_amount = 90, grass_on = true, grass_color = rgb(232, 240, 246),
		},
		rain = {
			sky = "fog on water", clock = 14, wind = 8,
			brightness = 1.5, exposure = -0.1, ambient = rgb(88, 94, 104), outdoor = rgb(118, 126, 140), shadow_soft = 0.5,
			specular = 1, diffuse = 0.8, -- wet, shinier surfaces
			atmo_density = 0.42, atmo_offset = 0.12, atmo_haze = 1.6, atmo_color = rgb(170, 180, 192), atmo_decay = rgb(92, 100, 115),
			cloud_cover = 0.88, cloud_density = 0.75, cloud_color = rgb(150, 156, 166),
			cc_tint = rgb(226, 232, 240), cc_saturation = -0.2, cc_contrast = 0.05,
			bloom_intensity = 0.3, bloom_threshold = 1.8, rays_intensity = 0,
			rain = 50, mist = 35,
		},
		["heavy rain"] = {
			sky = "night fog", clock = 15, wind = 20,
			brightness = 0.9, exposure = -0.25, ambient = rgb(60, 66, 78), outdoor = rgb(88, 96, 112), shadow_soft = 0.7,
			specular = 1, diffuse = 0.7,
			atmo_density = 0.55, atmo_offset = 0.05, atmo_haze = 2.6, atmo_color = rgb(128, 138, 152), atmo_decay = rgb(60, 66, 80),
			cloud_cover = 1, cloud_density = 0.9, cloud_color = rgb(96, 102, 112),
			cc_tint = rgb(214, 222, 236), cc_saturation = -0.32, cc_contrast = 0.1, cc_brightness = -0.02,
			bloom_intensity = 0.2, rays_intensity = 0,
			rain = 100, mist = 70, lightning = true,
		},
		autumn = {
			sky = "golden sunset", clock = 16.6, wind = 9,
			brightness = 2.2, ambient = rgb(112, 92, 74), outdoor = rgb(162, 132, 104), shift_top = rgb(70, 40, 10),
			atmo_density = 0.3, atmo_offset = 0.22, atmo_haze = 1.9, atmo_glare = 0.8, atmo_color = rgb(255, 214, 170), atmo_decay = rgb(196, 122, 72),
			cloud_cover = 0.45, cloud_color = rgb(255, 226, 196),
			cc_tint = rgb(255, 238, 214), cc_saturation = 0.16, cc_contrast = 0.05,
			bloom_intensity = 0.5, bloom_threshold = 1.5, rays_intensity = 0.16, rays_spread = 0.75,
			leaves = 75,
			grass_on = true, grass_color = rgb(188, 140, 66), ground_on = true, ground_color = rgb(168, 108, 48), ground_amount = 18,
		},
		sunset = {
			sky = "golden sunset", clock = 18.05, wind = 4,
			brightness = 2, ambient = rgb(122, 88, 82), outdoor = rgb(172, 122, 112), shift_top = rgb(90, 40, 20),
			atmo_density = 0.32, atmo_offset = 0.18, atmo_haze = 2.4, atmo_glare = 2.4, atmo_color = rgb(255, 176, 140), atmo_decay = rgb(180, 86, 90),
			cloud_cover = 0.5, cloud_color = rgb(255, 196, 168),
			cc_tint = rgb(255, 230, 210), cc_saturation = 0.14, cc_contrast = 0.06,
			bloom_intensity = 0.6, bloom_threshold = 1.3, rays_intensity = 0.3, rays_spread = 0.85,
		},
		night = {
			sky = "epic night", clock = 0.3, wind = 3,
			brightness = 1.2, exposure = 0.15, ambient = rgb(36, 44, 66), outdoor = rgb(64, 78, 112),
			atmo_density = 0.34, atmo_offset = 0.3, atmo_haze = 0.8, atmo_color = rgb(92, 108, 148), atmo_decay = rgb(30, 38, 66),
			cloud_cover = 0.35, cloud_density = 0.5, cloud_color = rgb(90, 100, 130),
			cc_tint = rgb(210, 220, 255), cc_saturation = -0.08, cc_contrast = 0.06,
			bloom_intensity = 0.55, bloom_threshold = 1.2, rays_intensity = 0,
			fireflies = 50,
		},
		["foggy morning"] = {
			sky = "cloudy sunrise", clock = 7.1, wind = 2, gusts = false,
			brightness = 1.8, ambient = rgb(118, 118, 116), outdoor = rgb(168, 166, 160), shadow_soft = 0.7,
			atmo_density = 0.62, atmo_offset = 0, atmo_haze = 2.8, atmo_glare = 0.4, atmo_color = rgb(214, 212, 206), atmo_decay = rgb(170, 170, 168),
			cloud_cover = 0.55, cloud_color = rgb(240, 238, 232),
			cc_tint = rgb(250, 248, 242), cc_saturation = -0.14, cc_contrast = -0.04, cc_brightness = 0.02,
			bloom_intensity = 0.35, bloom_threshold = 1.5, rays_intensity = 0.22, rays_spread = 0.9,
			mist = 90,
		},
	}
	local PRESET_ORDER = { "clear", "sakura", "snow", "blizzard", "rain", "heavy rain", "autumn", "sunset", "night", "foggy morning" }
	local TIMES = { sunrise = 6.2, morning = 8.5, noon = 12, ["golden hour"] = 16.8, sunset = 18.1, evening = 19.6, midnight = 0 }
	local TIME_ORDER = { "sunrise", "morning", "noon", "golden hour", "sunset", "evening", "midnight" }

	-- =================================================================
	-- > the controls
	-- =================================================================
	-- weather
	local preset_pick = weather_section:create_element({ name = "weather preset" }, {
		dropdown = { flag = "env_preset", options = PRESET_ORDER, default = {} },
	})
	slider(weather_section, "transition", "transition", 0, 10, 1, "s")
	slider(weather_section, "wind", "wind", 0, 60, 0, "", "wind_on")
	slider(weather_section, "wind direction", "wind_dir", 0, 359, 0, " deg", "wind_on")
	toggle(weather_section, "gusts", "gusts")
	local reset_button = weather_section:create_element({ name = "reset everything" }, { button = {} })

	-- environment (time of day)
	toggle(time_section, "set time", "time_on")
	local time_pick = time_section:create_element({ name = "time of day" }, {
		dropdown = { flag = "env_time_pick", options = TIME_ORDER, default = {} },
	})
	slider(time_section, "clock", "clock", 0, 24, 1, "h", "time_on")
	toggle(time_section, "day cycle", "cycle", "time_on")
	slider(time_section, "day length", "cycle_len", 1, 60, 0, " min")
	slider(time_section, "sun tilt", "latitude", 0, 90, 0, " deg", "time_on")

	-- configs
	local config_name = config_section:create_element({ name = "config name" }, { textbox = { flag = "env_config_name" } })
	local config_list = config_section:create_element({ name = "saved configs" }, {
		dropdown = { flag = "env_config_pick", options = {}, default = {} },
	})
	local save_button = config_section:create_element({ name = "save config" }, { button = {} })
	local load_button = config_section:create_element({ name = "load config" }, { button = {} })
	local delete_button = config_section:create_element({ name = "delete config" }, { button = { confirmation = true } })

	-- particles
	toggle(particle_section, "weather particles", "particles")
	slider_color(particle_section, "rain", "rain", "rain_color", "%")
	slider_color(particle_section, "snow", "snow", "snow_color", "%")
	slider(particle_section, "snow drift", "drift", 0, 100, 0, "%")
	slider_color(particle_section, "petals", "petals", "petal_color", "%")
	slider(particle_section, "leaves", "leaves", 0, 100, 0, "%")
	slider(particle_section, "ground mist", "mist", 0, 100, 0, "%")
	slider(particle_section, "butterflies", "butterflies", 0, 100, 0, "%")
	slider_color(particle_section, "fireflies", "fireflies", "firefly_color", "%")
	toggle(particle_section, "rain splashes", "splashes")
	toggle(particle_section, "lightning", "lightning")
	toggle(particle_section, "weather sounds", "sounds")
	slider(particle_section, "volume", "volume", 0, 100, 0, "%")

	-- options
	dropdown(options_section, "quality", "quality", { "low", "medium", "high", "ultra" })
	slider(options_section, "render distance", "distance", 40, 250, 0, " studs")
	toggle(options_section, "hide indoors", "hide_indoors")
	toggle(options_section, "clear view in menu", "clear_view")

	-- sky
	toggle(sky_section, "custom sky", "sky_on")
	dropdown(sky_section, "skybox", "sky_name", SKY_ORDER, "sky_on")
	textbox(sky_section, "sky id (1 or 6 ids)", "sky_custom")
	toggle(sky_section, "match weather", "auto_sky")
	toggle(sky_section, "spin sky", "sky_spin")
	slider(sky_section, "spin speed", "spin_speed", 1, 60, 0, " /s")
	toggle(sky_section, "hide sun", "hide_sun")
	toggle(sky_section, "hide moon", "hide_moon")
	toggle(sky_section, "hide stars", "hide_stars")

	-- clouds
	toggle_color(cloud_section, "clouds", "clouds_on", "cloud_color")
	slider(cloud_section, "cover", "cloud_cover", 0, 1, 2, "", "clouds_on")
	slider(cloud_section, "thickness", "cloud_density", 0, 1, 2, "", "clouds_on")

	-- fog
	toggle_color(fog_section, "fog", "fog_on", "fog_color")
	dropdown(fog_section, "fog style", "fog_style", { "soft", "distance" }, "fog_on")
	local fog_density_el = slider(fog_section, "density", "fog_density", 0, 1, 2, "", "fog_on")
	local fog_haze_el = slider(fog_section, "haze", "fog_haze", 0, 10, 1, "", "fog_on")
	local fog_start_el = slider(fog_section, "start", "fog_start", 0, 1000, 0, " studs", "fog_on")
	local fog_end_el = slider(fog_section, "end", "fog_end", 10, 3000, 0, " studs", "fog_on")

	-- atmosphere
	toggle(atmo_section, "atmosphere", "atmo_on")
	slider(atmo_section, "density", "atmo_density", 0, 1, 2, "", "atmo_on")
	slider(atmo_section, "offset", "atmo_offset", 0, 1, 2, "", "atmo_on")
	slider(atmo_section, "haze", "atmo_haze", 0, 10, 1, "", "atmo_on")
	slider(atmo_section, "glare", "atmo_glare", 0, 10, 1, "", "atmo_on")
	color(atmo_section, "colour", "atmo_color", "atmo_on")
	color(atmo_section, "decay colour", "atmo_decay", "atmo_on")

	-- lighting
	toggle(light_section, "custom lighting", "light_on")
	slider(light_section, "brightness", "brightness", 0, 10, 2, "", "light_on")
	slider(light_section, "exposure", "exposure", -3, 3, 2, "", "light_on")
	toggle(light_section, "shadows", "shadows", "light_on")
	slider(light_section, "shadow softness", "shadow_soft", 0, 1, 2, "", "light_on")
	color(light_section, "ambient", "ambient", "light_on")
	color(light_section, "outdoor ambient", "outdoor", "light_on")
	color(light_section, "sun colour shift", "shift_top", "light_on")
	color(light_section, "shade colour shift", "shift_bottom", "light_on")
	slider(light_section, "sky light", "diffuse", 0, 1, 2, "", "light_on")
	slider(light_section, "reflections", "specular", 0, 1, 2, "", "light_on")

	-- ground
	toggle_color(ground_section, "ground cover", "ground_on", "ground_color")
	slider(ground_section, "cover amount", "ground_amount", 0, 100, 0, "%", "ground_on")
	toggle_color(ground_section, "grass colour", "grass_on", "grass_color")
	toggle(ground_section, "override material", "mat_on")
	dropdown(ground_section, "material", "material", MATERIALS, "mat_on")
	toggle_color(ground_section, "recolor parts", "recolor_on", "recolor")

	-- colour correction
	toggle(grade_section, "colour correction", "cc_on")
	slider(grade_section, "brightness", "cc_brightness", -1, 1, 2, "", "cc_on")
	slider(grade_section, "contrast", "cc_contrast", -1, 1, 2, "", "cc_on")
	slider(grade_section, "saturation", "cc_saturation", -1, 1, 2, "", "cc_on")
	color(grade_section, "tint", "cc_tint", "cc_on")

	-- visual effects
	toggle(effects_section, "bloom", "bloom_on")
	slider(effects_section, "bloom intensity", "bloom_intensity", 0, 1, 2, "", "bloom_on")
	slider(effects_section, "bloom threshold", "bloom_threshold", 0, 4, 2, "", "bloom_on")
	slider(effects_section, "bloom size", "bloom_size", 0, 56, 0, "", "bloom_on")
	toggle(effects_section, "sun rays", "rays_on")
	slider(effects_section, "ray intensity", "rays_intensity", 0, 1, 2, "", "rays_on")
	slider(effects_section, "ray spread", "rays_spread", 0, 1, 2, "", "rays_on")
	toggle(effects_section, "motion blur", "mblur_on")
	slider(effects_section, "blur strength", "mblur_strength", 0, 100, 0, "%", "mblur_on")
	slider(effects_section, "max blur", "mblur_max", 1, 24, 0, "", "mblur_on")

	-- only the sliders that matter for the chosen fog style are shown
	local function fog_rows()
		local soft = S.fog_style ~= "distance"
		fog_density_el:set_visible(soft)
		fog_haze_el:set_visible(soft)
		fog_start_el:set_visible(not soft)
		fog_end_el:set_visible(not soft)
	end
	fog_rows()

	local function clear_pick(el)
		syncing = true
		el:set_dropdown({})
		syncing = false
	end

	-- what has to happen right away when certain settings change
	hooks.sky_on = function() sky_dirty = true end
	hooks.sky_name = hooks.sky_on
	hooks.sky_custom = function()
		if custom_faces() then
			if S.sky_name ~= "custom id" then
				S.sky_name = "custom id"
				sync("sky_name")
			end
			if not S.sky_on then
				S.sky_on = true
				sync("sky_on")
			end
		end
		sky_dirty = true
	end
	hooks.hide_sun = apply_celestial
	hooks.hide_moon = apply_celestial
	hooks.hide_stars = apply_celestial
	hooks.sky_spin = function() if not S.sky_spin then stop_spin() end end
	hooks.mat_on = function() if S.mat_on then want_scan = true else refresh_parts(false) end end
	hooks.recolor_on = function() if S.recolor_on then want_scan = true else refresh_parts(false) end end
	hooks.material = function() if S.mat_on then refresh_parts(false) end end
	hooks.recolor = function() if S.recolor_on then refresh_parts(false) end end
	hooks.ground_on = function() if S.ground_on then want_scan = true end end
	hooks.grass_on = function() if S.grass_on then want_scan = true end end
	hooks.clear_view = function() fx.set_clear(S.clear_view) end
	hooks.fog_style = fog_rows
	hooks.clock = function(by_user) if by_user then clear_pick(time_pick) end end

	-- =================================================================
	-- > presets, time of day, reset
	-- =================================================================
	local function apply_preset(name)
		local p = PRESETS[name]
		if not p then return end
		local values = {}
		for k, v in pairs(PRESET_BASE) do values[k] = v end
		for k, v in pairs(p) do values[k] = v end
		local sky = values.sky
		values.sky = nil
		if S.auto_sky and sky then
			values.sky_on = true
			values.sky_name = sky
		end
		set_many(values)
		clear_pick(time_pick)
		start_blend(S.transition)
		menu.new_notification("weather: " .. name, 1)
	end
	create_connection(preset_pick.on_dropdown_change, function(v)
		if syncing or not v[1] then return end
		apply_preset(v[1])
	end)

	create_connection(time_pick.on_dropdown_change, function(v)
		if syncing or not v[1] or not TIMES[v[1]] then return end
		set_many({ time_on = true, clock = TIMES[v[1]] })
		start_blend(S.transition)
	end)

	local function reset_environment()
		local values = {}
		for k, v in pairs(D) do
			if not KEEP[k] then values[k] = v end
		end
		set_many(values)
		clear_pick(preset_pick)
		clear_pick(time_pick)
		start_blend(math.max(S.transition, 0.6))
		sky_dirty = true
	end
	create_connection(reset_button.on_clicked, function()
		reset_environment()
		menu.new_notification("environment reset", 1)
	end)

	-- =================================================================
	-- > configs: saved to cover_environment.json where the executor can write files,
	-- otherwise kept for this session
	-- =================================================================
	local CONFIG_FILE = "cover_environment.json"
	local fs_read, fs_write, fs_exists = readfile, writefile, isfile
	local can_save = type(fs_read) == "function" and type(fs_write) == "function" and type(fs_exists) == "function"
	_G.__cover_configs = _G.__cover_configs or {}

	local function read_store()
		if can_save then
			local ok, data = pcall(function()
				if not fs_exists(CONFIG_FILE) then return {} end
				return HttpService:JSONDecode(fs_read(CONFIG_FILE))
			end)
			if ok and type(data) == "table" then return data end
			return {}
		end
		return _G.__cover_configs
	end
	local function write_store(store)
		if can_save then
			return (pcall(function() fs_write(CONFIG_FILE, HttpService:JSONEncode(store)) end))
		end
		_G.__cover_configs = store
		return true
	end
	local function encode()
		local out = {}
		for k, v in pairs(S) do
			if k ~= "clear_view" then
				if typeof(v) == "Color3" then
					out[k] = { c = { math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5) } }
				elseif type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
					out[k] = v
				end
			end
		end
		return out
	end
	local function decode(t)
		local out = {}
		for k, v in pairs(t) do
			local d = D[k]
			if d ~= nil and k ~= "clear_view" then
				if typeof(d) == "Color3" then
					if type(v) == "table" and type(v.c) == "table" then
						out[k] = Color3.fromRGB(tonumber(v.c[1]) or 0, tonumber(v.c[2]) or 0, tonumber(v.c[3]) or 0)
					end
				elseif type(v) == type(d) then
					out[k] = v
				end
			end
		end
		return out
	end
	local function refresh_configs(select)
		local names = {}
		for name in pairs(read_store()) do names[#names + 1] = tostring(name) end
		table.sort(names)
		config_list:set_options(names)
		if select then config_list:set_dropdown({ select }) end
	end
	refresh_configs()

	create_connection(config_list.on_dropdown_change, function(v)
		if v[1] then config_name:set_textbox(v[1]) end
	end)
	create_connection(save_button.on_clicked, function()
		local name = string.match(flags.env_config_name or "", "^%s*(.-)%s*$")
		if name == "" then name = "default" end
		local store = read_store()
		store[name] = encode()
		if write_store(store) then
			refresh_configs(name)
			menu.new_notification(can_save and ("saved config " .. name) or ("saved " .. name .. " for this session"), 1)
		else
			menu.new_notification("couldn't save the config", 3)
		end
	end)
	create_connection(load_button.on_clicked, function()
		local pick = flags.env_config_pick
		local name = pick and pick[1]
		local data = name and read_store()[name]
		if type(data) ~= "table" then
			menu.new_notification("pick a saved config first", 2)
			return
		end
		set_many(decode(data))
		clear_pick(preset_pick)
		clear_pick(time_pick)
		start_blend(S.transition)
		sky_dirty = true
		menu.new_notification("loaded config " .. name, 1)
	end)
	create_connection(delete_button.on_clicked, function()
		local pick = flags.env_config_pick
		local name = pick and pick[1]
		local store = read_store()
		if not name or store[name] == nil then
			menu.new_notification("pick a saved config first", 2)
			return
		end
		store[name] = nil
		write_store(store)
		refresh_configs()
		menu.new_notification("deleted config " .. name, 1)
	end)

	-- =================================================================
	-- > every frame
	-- =================================================================
	local terrain_timer, cycle_ui_timer, ground_sig = 0, 0, ""
	track(RunService.RenderStepped:Connect(function(dt)
		if not running then return end
		local now = os.clock()
		if S.cycle and S.time_on then
			S.clock = (S.clock + dt * 24 / (math.max(S.cycle_len, 1) * 60)) % 24
			cycle_ui_timer -= dt
			if cycle_ui_timer <= 0 then
				cycle_ui_timer = 0.5
				sync("clock")
			end
		end
		guard(step_values, dt)
		guard(apply_time)
		guard(apply_lighting)
		guard(apply_fog_and_atmosphere)
		guard(apply_effects)
		guard(apply_motion_blur, dt)
		guard(apply_clouds)
		guard(apply_wind, now)
		if want_scan then
			want_scan = false
			guard(refresh_parts, true)
			ground_sig = ""
		end
		-- ground colours: a few times a second is plenty, and only while they're changing
		terrain_timer -= dt
		if terrain_timer <= 0 then
			terrain_timer = 0.12
			local sig = string.format("%.3f %.3f %.2f %s %s", A.ground_on, A.grass_on, A.ground_amount, tostring(A.ground_color), tostring(A.grass_color))
			if sig ~= ground_sig then
				ground_sig = sig
				guard(apply_terrain)
				guard(refresh_parts, false)
			end
		end
		-- a preset swaps the skybox halfway through, when everything else is mid-change
		if sky_dirty and (not blend or blend.t >= 0.5) then
			sky_dirty = false
			guard(apply_sky)
		end
		guard(spin_step, dt)
		guard(weather_step, dt, now)
	end))

	-- unload: everything goes back to how the game had it, straight away
	local function release_all()
		running = false
		blend = nil
		for k, v in pairs(D) do S[k] = v end
		S.particles = false
		for _, k in ipairs(BLENDED) do A[k] = target(k) end
		wind_flat = Vector3.zero
		weather_release()
		guard(apply_time)
		guard(apply_lighting)
		guard(apply_fog_and_atmosphere)
		guard(apply_effects)
		guard(apply_motion_blur, 0)
		guard(apply_clouds)
		guard(apply_wind, 0)
		guard(apply_terrain)
		guard(refresh_parts, false)
		guard(function()
			stop_spin()
			apply_sky()
			apply_celestial()
			for s, b in pairs(base_of) do -- any sky we ever touched gets its own sun / moon / stars back
				if s.Parent and s ~= ours then
					s.SunAngularSize, s.MoonAngularSize, s.StarCount = b.sun, b.moon, b.stars
				end
			end
		end)
	end
	menu.cleanup[#menu.cleanup + 1] = release_all

	-- =================================================================
	-- > player: trail
	-- =================================================================
	local undo = {} -- player cosmetics register their "switch off" here; unload runs them
	local trail = { on = false, color = ICE, color2 = Color3.new(1, 1, 1), length = 0.6, width = 2, glow = true }
	local trail_parts = {} -- attachments + trail currently on the character

	local function clear_trail()
		for _, obj in ipairs(trail_parts) do obj:Destroy() end
		table.clear(trail_parts)
	end

	local function build_trail()
		clear_trail()
		if not trail.on then return end
		local char = local_player and local_player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local a0 = Instance.new("Attachment")
		a0.Name = "CoverTrailTop"
		a0.Position = Vector3.new(0, trail.width / 2, 0)
		local a1 = Instance.new("Attachment")
		a1.Name = "CoverTrailBottom"
		a1.Position = Vector3.new(0, -trail.width / 2, 0)
		local t = Instance.new("Trail")
		t.Name = "CoverTrail"
		t.Attachment0, t.Attachment1 = a0, a1
		t.Lifetime = trail.length
		t.MinLength = 0.05
		t.FaceCamera = true
		t.LightEmission = trail.glow and 0.8 or 0
		t.LightInfluence = trail.glow and 0 or 1
		t.Color = ColorSequence.new(trail.color, trail.color2)
		t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
		t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.25) })
		a0.Parent, a1.Parent, t.Parent = root, root, root
		trail_parts = { a0, a1, t }
	end

	undo[#undo + 1] = function() trail.on = false; clear_trail() end

	local trail_toggle = trail_section:create_element({ name = "trail" }, {
		toggle = { flag = "ply_trail", default = false },
		colorpicker = { color_flag = "ply_trail_color", transparency_flag = "ply_trail_color_t", default_color = ICE },
	})
	local trail_fade = trail_section:create_element({ name = "fade to" }, {
		colorpicker = { color_flag = "ply_trail_color2", transparency_flag = "ply_trail_color2_t", default_color = Color3.new(1, 1, 1) },
	})
	local trail_len = trail_section:create_element({ name = "length" }, {
		slider = { flag = "ply_trail_len", min = 0.1, max = 3, default = trail.length, suffix = "s", decimals = 1 },
	})
	local trail_width = trail_section:create_element({ name = "width" }, {
		slider = { flag = "ply_trail_width", min = 0.4, max = 5, default = trail.width, decimals = 1 },
	})
	local trail_glow = trail_section:create_element({ name = "glow" }, { toggle = { flag = "ply_trail_glow", default = true } })

	create_connection(trail_toggle.on_toggle_change, function(v) trail.on = v; build_trail() end)
	create_connection(trail_toggle.on_color_change, function(c) trail.color = c; if trail.on then build_trail() end end)
	create_connection(trail_fade.on_color_change, function(c) trail.color2 = c; if trail.on then build_trail() end end)
	create_connection(trail_len.on_slider_change, function(v) trail.length = v; if trail.on then build_trail() end end)
	create_connection(trail_width.on_slider_change, function(v) trail.width = v; if trail.on then build_trail() end end)
	create_connection(trail_glow.on_toggle_change, function(v) trail.glow = v; if trail.on then build_trail() end end)

	-- =================================================================
	-- > player: flex (watch, chain, aura) - built from parts, welded to you
	-- =================================================================
	local STYLES = {
		gold = { color = Color3.fromRGB(214, 172, 62), material = Enum.Material.Metal, reflect = 0.35, sparkle = false },
		silver = { color = Color3.fromRGB(206, 212, 222), material = Enum.Material.Metal, reflect = 0.4, sparkle = false },
		iced = { color = Color3.fromRGB(235, 245, 255), material = Enum.Material.Glass, reflect = 0.5, sparkle = true },
		["rose gold"] = { color = Color3.fromRGB(222, 156, 140), material = Enum.Material.Metal, reflect = 0.35, sparkle = false },
	}
	local flex = { watch = false, chain = false, aura = false, style = "iced", aura_color = ICE }
	local flex_parts = { watch = {}, chain = {}, aura = {} }

	local function clear_flex(kind)
		for _, obj in ipairs(flex_parts[kind]) do obj:Destroy() end
		table.clear(flex_parts[kind])
	end

	-- a small cosmetic part welded to a body part (no collisions, no weight)
	local function bit(kind, body, shape, size, offset, color, material, reflect)
		local p = Instance.new("Part")
		p.Name = "CoverFlex"
		p.Shape = shape
		p.Size = size
		p.Color = color
		p.Material = material
		p.Reflectance = reflect or 0
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.CastShadow = false
		p.CFrame = body.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = body, p
		w.Parent = p
		p.Parent = body
		table.insert(flex_parts[kind], p)
		return p
	end

	local function sparkle(kind, part, color)
		local e = Instance.new("ParticleEmitter")
		e.Name = "CoverSparkle"
		e.Texture = DROP_TEX
		e.Rate = 6
		e.Lifetime = NumberRange.new(0.3, 0.6)
		e.Speed = NumberRange.new(0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.18), NumberSequenceKeypoint.new(1, 0) })
		e.LightEmission = 1
		e.Color = ColorSequence.new(color)
		e.Parent = part
		table.insert(flex_parts[kind], e)
	end

	local function body_part(char, r15, r6)
		return char:FindFirstChild(r15) or char:FindFirstChild(r6)
	end

	local function build_watch(char)
		clear_flex("watch")
		if not flex.watch then return end
		local arm = body_part(char, "LeftLowerArm", "Left Arm")
		if not arm then return end
		local s = STYLES[flex.style]
		local thick = math.max(arm.Size.X, arm.Size.Z)
		local y = -arm.Size.Y / 2 + 0.28 -- just above the wrist
		-- band: a ring around the wrist (cylinder turned upright)
		bit("watch", arm, Enum.PartType.Cylinder, Vector3.new(0.22, thick * 1.1, thick * 1.1),
			CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), s.color, s.material, s.reflect)
		-- bezel + face on the outside of the wrist
		local out_x = -(arm.Size.X / 2 + 0.06)
		local bezel = bit("watch", arm, Enum.PartType.Cylinder, Vector3.new(0.1, 0.46, 0.46),
			CFrame.new(out_x, y, 0), s.color, s.material, s.reflect)
		bit("watch", arm, Enum.PartType.Cylinder, Vector3.new(0.11, 0.36, 0.36),
			CFrame.new(out_x - 0.01, y, 0), Color3.fromRGB(14, 18, 26), Enum.Material.Glass, 0.2)
		if s.sparkle then sparkle("watch", bezel, Color3.new(1, 1, 1)) end
	end

	local function build_chain(char)
		clear_flex("chain")
		if not flex.chain then return end
		local torso = body_part(char, "UpperTorso", "Torso")
		if not torso then return end
		local s = STYLES[flex.style]
		local w, h, d = torso.Size.X, torso.Size.Y, torso.Size.Z
		local LINKS = 15
		for i = 0, LINKS - 1 do -- links hang in a U across the chest
			local t = i / (LINKS - 1)
			local x = (t - 0.5) * w * 0.62
			local y = h / 2 - 0.12 - math.sin(t * math.pi) * h * 0.32
			bit("chain", torso, Enum.PartType.Ball, Vector3.new(0.17, 0.17, 0.17),
				CFrame.new(x, y, -(d / 2 + 0.06)), s.color, s.material, s.reflect)
		end
		-- pendant: a diamond-cut charm at the bottom of the chain
		local pendant = bit("chain", torso, Enum.PartType.Block, Vector3.new(0.34, 0.34, 0.12),
			CFrame.new(0, h / 2 - 0.12 - h * 0.32 - 0.24, -(d / 2 + 0.08)) * CFrame.Angles(0, 0, math.rad(45)),
			s.sparkle and Color3.fromRGB(235, 245, 255) or s.color, s.sparkle and Enum.Material.Glass or s.material, 0.5)
		sparkle("chain", pendant, Color3.new(1, 1, 1))
	end

	local function build_aura(char)
		clear_flex("aura")
		if not flex.aura then return end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local e = Instance.new("ParticleEmitter")
		e.Name = "CoverAura"
		e.Texture = DROP_TEX
		e.Rate = 26
		e.Lifetime = NumberRange.new(1, 1.6)
		e.Speed = NumberRange.new(1.5, 3)
		e.EmissionDirection = Enum.NormalId.Top
		e.SpreadAngle = Vector2.new(25, 25)
		e.Acceleration = Vector3.new(0, 1.5, 0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.32), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		e.LightEmission = 1
		e.Color = ColorSequence.new(flex.aura_color, Color3.new(1, 1, 1))
		e.Parent = root
		table.insert(flex_parts.aura, e)
		local glow = Instance.new("PointLight")
		glow.Name = "CoverAuraLight"
		glow.Color = flex.aura_color
		glow.Brightness = 1.2
		glow.Range = 9
		glow.Parent = root
		table.insert(flex_parts.aura, glow)
	end

	local function build_flex()
		local char = local_player and local_player.Character
		if not char then return end
		build_watch(char)
		build_chain(char)
		build_aura(char)
	end

	undo[#undo + 1] = function()
		flex.watch, flex.chain, flex.aura = false, false, false
		clear_flex("watch"); clear_flex("chain"); clear_flex("aura")
	end

	local watch_toggle = flex_section:create_element({ name = "iced watch" }, { toggle = { flag = "ply_watch", default = false } })
	local chain_toggle = flex_section:create_element({ name = "chain" }, { toggle = { flag = "ply_chain", default = false } })
	local flex_style = flex_section:create_element({ name = "style" }, {
		dropdown = { flag = "ply_flex_style", options = { "iced", "gold", "silver", "rose gold" }, default = { "iced" }, requires_one = true },
	})
	local aura_toggle = flex_section:create_element({ name = "aura" }, {
		toggle = { flag = "ply_aura", default = false },
		colorpicker = { color_flag = "ply_aura_color", transparency_flag = "ply_aura_color_t", default_color = ICE },
	})

	local function rebuild(kind)
		local char = local_player and local_player.Character
		if not char then return end
		if kind == "watch" then build_watch(char) elseif kind == "chain" then build_chain(char) else build_aura(char) end
	end
	create_connection(watch_toggle.on_toggle_change, function(v) flex.watch = v; rebuild("watch") end)
	create_connection(chain_toggle.on_toggle_change, function(v) flex.chain = v; rebuild("chain") end)
	create_connection(flex_style.on_dropdown_change, function(v)
		flex.style = v[1] or "iced"
		rebuild("watch"); rebuild("chain")
	end)
	create_connection(aura_toggle.on_toggle_change, function(v) flex.aura = v; rebuild("aura") end)
	create_connection(aura_toggle.on_color_change, function(c) flex.aura_color = c; if flex.aura then rebuild("aura") end end)

	-- respawning: put the trail + flex back on the new character once it's loaded
	if local_player then
		track(local_player.CharacterAdded:Connect(function(char)
			char:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.2) -- let the body parts settle
			table.clear(flex_parts.watch); table.clear(flex_parts.chain); table.clear(flex_parts.aura)
			table.clear(trail_parts)
			build_trail()
			build_flex()
		end))
	end

	local function restore_player()
		for _, f in ipairs(undo) do pcall(f) end
	end
	menu.cleanup[#menu.cleanup + 1] = restore_player
end

-- settings tab
local settings_group = menu.create_group("settings")
settings_group:create_tab("menu")
local menu_section = settings_group:create_section("menu", "menu", 1)

local menu_key = menu_section:create_element({ name = "toggle bind" }, {
	keybind = { default = Enum.KeyCode.Insert },
})
create_connection(menu_key.on_key_change, function(key)
	menu.menu_key = key
end)


local unload_button = menu_section:create_element({ name = "unload" }, {
	button = { confirmation = true },
})
create_connection(unload_button.on_clicked, function()
	menu.unload()
end)

-- =====================================================================
-- > ( loader )  -  plays once before the menu opens (~2.4 s)
-- A dark band slides across the middle, an icy rail draws itself outward, the emblem
-- drops onto it, and the progress is light leaking out from behind the emblem both ways.
-- =====================================================================
do
	local LOAD_TIME = 0.5 -- seconds the progress itself takes
	local STEPS = { -- status shown from each progress point on (few, so each is readable)
		{ 0, "connecting" }, { 0.35, "loading assets" }, { 0.72, "building interface" },
	}
	-- uneven pacing (fraction of LOAD_TIME -> progress), little stalls make it feel real
	local SCHEDULE = { { 0, 0 }, { 0.22, 0.2 }, { 0.38, 0.26 }, { 0.62, 0.6 }, { 0.74, 0.66 }, { 1, 1 } }
	local MAX_W = 0.5 -- how much of the screen width the progress line reaches at 100%
	local ICE_TEXT = Color3.fromRGB(196, 214, 236)
	local NAME, LETTER_GAP = "cover", 21

	-- keep the menu shut (and the toggle key locked) until the loader is done
	menu.loading = true
	menu.open = false
	book_p, book_target = 2, 2
	render_book(2)
	menu.hide_roblox_ui(true) -- nothing of Roblox's (hotbar, chat, top bar...) on top of the loader

	local function play(object, props, time, style, direction)
		local t = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quart,
			direction or Enum.EasingDirection.Out), props)
		t:Play()
		return t
	end

	local LOADER_DIM = 0.3   -- darkness over the whole screen: 0 = black, 1 = none
	local LOADER_BLUR = 14   -- blur on the game behind the loader

	local root = new("Frame", {
		Name = "loader",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = screen,
	})

	-- dark layer over the WHOLE screen. The menu's screen starts below Roblox's top bar, so this
	-- reaches up by the top-bar height to cover that strip too (otherwise the top stays bright).
	local top_inset = game:GetService("GuiService"):GetGuiInset()
	local dim = new("Frame", {
		Name = "dim",
		Position = UDim2.fromOffset(0, -top_inset.Y - 2),
		Size = UDim2.new(1, 0, 1, top_inset.Y + 4),
		BackgroundColor3 = Color3.fromRGB(1, 2, 5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 49,
		Parent = root,
	})

	-- the loader has its own blur (no snow / frost / mist yet - those come in with the menu)
	do
		local old_blur = Lighting:FindFirstChild("LoaderBlur")
		if old_blur then old_blur:Destroy() end
	end
	local loader_blur = Instance.new("BlurEffect")
	loader_blur.Name = "LoaderBlur"
	loader_blur.Size = 0
	loader_blur.Parent = Lighting

	-- dark band across the middle: contrast for the text over any background, letterbox feel
	local band = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 400), -- tall enough to sit behind the key prompt too
		BackgroundColor3 = Color3.fromRGB(2, 4, 9),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 50,
		Parent = root,
	}, {
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.3),
				NumberSequenceKeypoint.new(0.5, 0.06), NumberSequenceKeypoint.new(0.8, 0.3), NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	-- the rail: a faint icy line drawn outward across the screen
	local SOFT_ENDS = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0),
		NumberSequenceKeypoint.new(0.75, 0), NumberSequenceKeypoint.new(1, 1),
	})
	local rail = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 0, 0, 1),
		BackgroundColor3 = colors.accent,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = 51,
		Parent = root,
	}, { new("UIGradient", { Transparency = SOFT_ENDS }) })

	-- progress: a bright line growing out from behind the emblem, a diamond riding each tip
	local prog = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 0, 0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 52,
		Parent = root,
	}, {
		new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, colors.accent), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, colors.accent),
			}),
			-- ends fade softly into the tip diamonds instead of stopping dead
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.16, 0.15),
				NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.84, 0.15), NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	local tips = {}
	for _, side in ipairs({ -1, 1 }) do
		local glow = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(13, 13),
			Rotation = 45,
			BackgroundColor3 = colors.accent,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 52,
			Parent = root,
		}, { corner(2) })
		local tip = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(5, 5),
			Rotation = 45,
			BackgroundColor3 = Color3.fromRGB(235, 245, 255),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 53,
			Parent = root,
		}, { corner(1) })
		tips[#tips + 1] = { side = side, tip = tip, glow = glow }
	end

	-- emblem sits on the line and drops into place
	local emblem = new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -40), -- just above the line, so the centre diamond never covers it
		Size = UDim2.fromOffset(92, 92),
		BackgroundTransparency = 1,
		Image = EMBLEM_ID,
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 54,
		Parent = root,
	})
	local emblem_scale = new("UIScale", { Scale = 1.3, Parent = emblem })
	local sheen_tone = Color3.fromRGB(214, 221, 232) -- (not "dim": that name is the dark layer)
	local sheen = new("UIGradient", {
		Rotation = 25,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, sheen_tone), ColorSequenceKeypoint.new(0.42, sheen_tone),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.58, sheen_tone), ColorSequenceKeypoint.new(1, sheen_tone),
		}),
		Parent = emblem,
	})

	-- the name: letters drop in one at a time under the line
	local letters = {}
	for i = 1, #NAME do
		local x = (i - (#NAME + 1) / 2) * LETTER_GAP
		letters[i] = {
			x = x,
			label = text_label({
				Text = NAME:sub(i, i),
				Font = TITLE_FONT,
				TextSize = 20,
				TextColor3 = Color3.fromRGB(232, 240, 252),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, x, 0.5, 56),
				Size = UDim2.fromOffset(24, 28),
				ZIndex = 54,
				Parent = root,
			}),
		}
	end

	-- status line: small, light text on the dark band so it's actually readable
	local status = text_label({
		Text = "key required",
		TextSize = 12,
		TextColor3 = ICE_TEXT,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 142), -- under the key box; moves up once unlocked
		Size = UDim2.fromOffset(320, 16),
		ZIndex = 54,
		Parent = root,
	})

	-- intro ---------------------------------------------------------------
	play(dim, { BackgroundTransparency = LOADER_DIM }, 0.3) -- darken everything behind the loader
	play(loader_blur, { Size = LOADER_BLUR }, 0.35)
	play(band, { BackgroundTransparency = 0 }, 0.3)
	play(rail, { Size = UDim2.new(0.82, 0, 0, 1) }, 0.55)
	task.delay(0.1, function()
		play(emblem, { ImageTransparency = 0 }, 0.25)
		play(emblem_scale, { Scale = 1 }, 0.42, Enum.EasingStyle.Back) -- slight overshoot = it lands
	end)
	for i, L in ipairs(letters) do
		task.delay(0.22 + (i - 1) * 0.05, function()
			play(L.label, { TextTransparency = 0, Position = UDim2.new(0.5, L.x, 0.5, 66) }, 0.32)
		end)
	end
	task.delay(0.32, function() play(status, { TextTransparency = 0 }, 0.2) end)
	-- the diamonds wait at the centre of the line (the logo sits above it now)
	for _, tp in ipairs(tips) do
		play(tp.tip, { BackgroundTransparency = 0 }, 0.3)
		play(tp.glow, { BackgroundTransparency = 0.8 }, 0.3)
	end

	local function progress_at(u)
		for i = 1, #SCHEDULE - 1 do
			local a, b = SCHEDULE[i], SCHEDULE[i + 1]
			if u < b[1] then
				local k = (u - a[1]) / (b[1] - a[1])
				k = k * k * (3 - 2 * k)
				return a[2] + (b[2] - a[2]) * k
			end
		end
		return 1
	end

	local t0 = nil -- progress waits until a valid key is entered
	local done = false
	local conn

	-- key system ------------------------------------------------------------
	local VALID_KEYS = { "test" } -- placeholder; swap for real keys / a key check later
	local KEY_Y = 104
	local key_unlocked = false

	-- frees the mouse while the key prompt is up (first-person / shift-lock games)
	local mouse_unlock = new("TextButton", {
		Modal = true,
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		Parent = root,
	})

	local key_box = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, KEY_Y + 10),
		Size = UDim2.fromOffset(260, 28),
		BackgroundColor3 = colors.card,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 55,
		Parent = root,
	}, { corner(3) })
	local key_stroke = stroke(key_box, colors.border)
	key_stroke.Transparency = 1
	local key_input = new("TextBox", {
		Text = "",
		PlaceholderText = "enter key",
		PlaceholderColor3 = colors.dark_text,
		TextColor3 = colors.active_text,
		Font = FONT,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		BackgroundTransparency = 1,
		TextTransparency = 1,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -84, 1, 0),
		ZIndex = 56,
		Parent = key_box,
	}, { new("UIPadding", { PaddingBottom = UDim.new(0, 2) }) })
	local key_sep = new("Frame", {
		Position = UDim2.new(1, -70, 0, 6),
		Size = UDim2.new(0, 1, 1, -12),
		BackgroundColor3 = colors.border,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 56,
		Parent = key_box,
	})
	local key_button = new("TextButton", {
		Text = "unlock",
		Font = FONT,
		TextSize = 13,
		TextColor3 = colors.accent,
		TextTransparency = 1,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Position = UDim2.new(1, -69, 0, 0),
		Size = UDim2.new(0, 69, 1, 0),
		ZIndex = 56,
		Parent = key_box,
	}, { new("UIPadding", { PaddingBottom = UDim.new(0, 2) }) })
	key_button.MouseEnter:Connect(function() tween(key_button, { TextColor3 = Color3.new(1, 1, 1) }) end)
	key_button.MouseLeave:Connect(function() tween(key_button, { TextColor3 = colors.accent }) end)
	key_input.Focused:Connect(function()
		if not key_unlocked then tween(key_stroke, { Color = colors.highlighted }) end
	end)

	-- prompt slides up into place after the name has dropped in, and takes focus
	task.delay(0.36, function()
		if not root.Parent then return end
		play(key_box, { BackgroundTransparency = 0.05, Position = UDim2.new(0.5, 0, 0.5, KEY_Y) }, 0.35)
		play(key_stroke, { Transparency = 0 }, 0.35)
		play(key_input, { TextTransparency = 0 }, 0.35)
		play(key_sep, { BackgroundTransparency = 0 }, 0.35)
		play(key_button, { TextTransparency = 0 }, 0.35)
		task.delay(0.2, function() if not key_unlocked then key_input:CaptureFocus() end end)
	end)

	local function try_key()
		if key_unlocked or not root.Parent then return end
		local entered = (key_input.Text:gsub("^%s+", ""):gsub("%s+$", ""))
		if table.find(VALID_KEYS, entered) then
			-- accepted: icy flash, prompt fades away, status moves up, loading begins
			key_unlocked = true
			key_input:ReleaseFocus()
			play(key_stroke, { Color = colors.accent }, 0.15)
			status.Text = "key accepted"
			status.TextColor3 = ICE_TEXT -- back from red if there was a wrong try before
			task.delay(0.1, function()
				if not root.Parent then return end
				play(key_box, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, KEY_Y - 6) }, 0.22)
				play(key_stroke, { Transparency = 1 }, 0.22)
				play(key_input, { TextTransparency = 1 }, 0.22)
				play(key_sep, { BackgroundTransparency = 1 }, 0.22)
				play(key_button, { TextTransparency = 1 }, 0.22)
				play(status, { Position = UDim2.new(0.5, 0, 0.5, 100) }, 0.25)
				task.delay(0.2, function()
					key_box.Visible = false
					mouse_unlock.Modal = false
					t0 = os.clock()
				end)
			end)
		else
			-- wrong: just the status text turns red (it stays red until you try again)
			status.Text = entered == "" and "enter a key" or "invalid key"
			status.TextColor3 = colors.error:Lerp(Color3.new(1, 1, 1), 0.25)
			key_input.Text = ""
			task.defer(function() key_input:CaptureFocus() end)
		end
	end
	track(key_input.FocusLost:Connect(function(enter_pressed)
		if enter_pressed then try_key() end
	end))
	track(key_button.MouseButton1Click:Connect(try_key))

	-- outro: tips race to the screen edges, everything dissolves, the menu opens
	local function finish()
		status.Text = "ready"
		for _, tp in ipairs(tips) do
			local edge = UDim2.fromScale(0.5 + tp.side * 0.5, 0.5)
			play(tp.tip, { Position = edge }, 0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
			play(tp.glow, { Position = edge, BackgroundTransparency = 0.45 }, 0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		end
		play(prog, { Size = UDim2.new(1, 0, 0, 1) }, 0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		task.wait(0.22)
		if not root.Parent then return end -- unloaded while loading

		local fade = 0.28
		for _, obj in ipairs({ dim, band, rail, prog }) do play(obj, { BackgroundTransparency = 1 }, fade) end
		play(loader_blur, { Size = 0 }, fade + 0.2) -- the menu's own blur takes over as this one fades
		for _, tp in ipairs(tips) do
			play(tp.tip, { BackgroundTransparency = 1 }, fade)
			play(tp.glow, { BackgroundTransparency = 1 }, fade)
		end
		play(emblem, { ImageTransparency = 1 }, fade)
		play(emblem_scale, { Scale = 1.12 }, fade)
		for _, L in ipairs(letters) do
			play(L.label, { TextTransparency = 1, Position = UDim2.new(0.5, L.x, 0.5, 60) }, fade)
		end
		play(status, { TextTransparency = 1 }, fade)
		task.wait(fade)
		if conn then conn:Disconnect() end
		if not root.Parent then return end
		root:Destroy()
		task.delay(0.25, function() loader_blur:Destroy() end)

		-- now the menu: the closed book fades in and swings open
		menu.loading = false
		menu.toggle(true)
		menu.new_notification("cover loaded - menu key insert", 1)
	end

	conn = track(RunService.RenderStepped:Connect(function()
		local now = os.clock()
		-- a light sweeps across the emblem every 1.6 s
		local s = (now % 1.6) / 1.0
		sheen.Offset = Vector2.new(s < 1 and (-0.8 + 1.6 * s) or 0.8, 0)
		if done or not t0 then return end -- nothing loads until the key is accepted

		local p = progress_at(math.max(0, now - t0) / LOAD_TIME)
		local w = MAX_W * p
		prog.Size = UDim2.new(w, 0, 0, 1)
		for _, tp in ipairs(tips) do
			-- diamonds ride exactly on the line's ends
			local pos = UDim2.fromScale(0.5 + tp.side * w / 2, 0.5)
			tp.tip.Position, tp.glow.Position = pos, pos
		end

		local label = STEPS[1][2]
		for _, st in ipairs(STEPS) do
			if p >= st[1] then label = st[2] end
		end
		status.Text = label .. "   " .. math.floor(p * 100) .. "%"

		if p >= 1 then
			done = true
			task.spawn(finish)
		end
	end))
end

return library
