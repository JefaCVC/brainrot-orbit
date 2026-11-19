--!strict
-- UiKit
-- Lava Rush-style cartoon UI kit for BRAINROT ORBIT (round 5): LuckiestGuy
-- titles, FredokaOne body text, INK outlines, CREAM panels, candy colors,
-- shade gradients, gloss strips, drop shadows, bouncy buttons and pop
-- scale-ins. The design language follows the reference game
-- on1force/brainrot-game (MIT) — every line here is original code written
-- for this game, not a copy.
--
-- The "text never overflows its box" rule has one enforcement point here:
-- candy titles are TextScaled, fixed-size dynamic labels go through
-- fitText/truncate, and every label carries an ink glyph outline so it
-- reads on any background.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Color3 = any
type Instance = any
type TextLabel = any
type TextButton = any
type Frame = any
type ScrollingFrame = any
type UDim2 = any

local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local UiKit = {}

-- Palette: ink outlines, cream panels, seven candy colors.
UiKit.INK = Color3.fromRGB(58, 32, 30)
UiKit.CREAM = Color3.fromRGB(255, 249, 234)
UiKit.CREAM_DARK = Color3.fromRGB(255, 225, 176)
UiKit.TEXT = Color3.fromRGB(58, 32, 30) -- ink text on cream panels
UiKit.MUTED = Color3.fromRGB(140, 110, 100)
UiKit.WHITE = Color3.fromRGB(255, 255, 255)
UiKit.GOLD = Color3.fromRGB(255, 206, 54)
UiKit.GREEN = Color3.fromRGB(96, 214, 84)
UiKit.RED = Color3.fromRGB(255, 88, 82)
UiKit.ACCENT = Color3.fromRGB(64, 168, 255)
UiKit.COLORS = {
	green = Color3.fromRGB(96, 214, 84),
	blue = Color3.fromRGB(64, 168, 255),
	red = Color3.fromRGB(255, 88, 82),
	purple = Color3.fromRGB(176, 104, 255),
	orange = Color3.fromRGB(255, 156, 44),
	gold = Color3.fromRGB(255, 206, 54),
	lava = Color3.fromRGB(255, 104, 40),
	cyan = Color3.fromRGB(60, 220, 220),
	pink = Color3.fromRGB(255, 120, 190),
} :: { [string]: Color3 }

function UiKit.lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.fromRGB(255, 255, 255), amount)
end

function UiKit.darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.fromRGB(0, 0, 0), amount)
end

-- Vertical shade gradient: lighter at the top, darker at the bottom.
-- Reuses the existing "Shade" gradient so panels/buttons can be recolored.
function UiKit.shade(target: Instance, color: Color3, lightAmount: number, darkAmount: number)
	local gradient = target:FindFirstChild("Shade")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Name = "Shade"
		gradient.Rotation = 90
		gradient.Parent = target
	end
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UiKit.lighten(color, lightAmount)),
		ColorSequenceKeypoint.new(1, UiKit.darken(color, darkAmount)),
	})
end

-- Ink outline (rounded joins) around a frame or button border.
function UiKit.outline(target: Instance, thickness: number, color: Color3?)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color or UiKit.INK
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = target
	return stroke
end

function UiKit.corner(target: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = target
	return corner
end

-- Drop shadow: a dark copy behind the target, offset +6px, following the
-- target's position/size/visibility. Skip for objects inside a layout
-- (the shadow would be counted as a layout item).
function UiKit.addShadow(target: Instance)
	local parent = target.Parent
	if not parent then
		return nil
	end
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = Color3.fromRGB(20, 16, 16)
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	shadow.AnchorPoint = target.AnchorPoint
	shadow.Position = target.Position + UDim2.new(0, 6, 0, 6)
	shadow.Size = target.Size
	shadow.Visible = target.Visible
	local z = target.ZIndex
	if z <= 1 then
		target.ZIndex = 2
		z = 2
	end
	shadow.ZIndex = z - 1
	local corner = target:FindFirstChildOfClass("UICorner")
	if corner then
		local shadowCorner = Instance.new("UICorner")
		shadowCorner.CornerRadius = corner.CornerRadius
		shadowCorner.Parent = shadow
	end
	shadow.Parent = parent
	target:GetPropertyChangedSignal("Position"):Connect(function()
		shadow.Position = target.Position + UDim2.new(0, 6, 0, 6)
	end)
	target:GetPropertyChangedSignal("Size"):Connect(function()
		shadow.Size = target.Size
	end)
	target:GetPropertyChangedSignal("Visible"):Connect(function()
		shadow.Visible = target.Visible
	end)
	return shadow
end

-- Cream (or colored) cartoon panel: shade gradient + corner 18 + ink
-- outline 4 + drop shadow.
function UiKit.panel(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = color or UiKit.CREAM
	frame.BorderSizePixel = 0
	frame.Parent = parent
	UiKit.shade(frame, color or UiKit.CREAM, 0.18, 0.12)
	UiKit.corner(frame, 18)
	UiKit.outline(frame, 4)
	UiKit.addShadow(frame)
	return frame
end

-- Recolors a panel made by UiKit.panel (gradient + base color).
function UiKit.setPanelColor(panel: Frame, color: Color3)
	panel.BackgroundColor3 = color
	UiKit.shade(panel, color, 0.18, 0.12)
end

-- Cartoon text: TextScaled so it can never overflow its box, ink glyph
-- outline so it reads on any background. font: "title" (LuckiestGuy) or
-- "body" (FredokaOne).
function UiKit.text(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	text: string,
	color: Color3,
	font: string?,
	strokeThickness: number?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.Font = if font == "title" then Enum.Font.LuckiestGuy else Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = strokeThickness or 2.5
	stroke.Color = UiKit.INK
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return label
end

-- Bouncy press feedback: hover 1.06, press 0.9, release 1.06, Back easing.
function UiKit.bouncy(button: TextButton)
	local scale = button:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "BouncyScale"
		scale.Parent = button
	end
	local function tweenTo(target: number, duration: number)
		TweenService:Create(scale, TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	end
	button.MouseEnter:Connect(function()
		tweenTo(1.06, 0.15)
	end)
	button.MouseLeave:Connect(function()
		tweenTo(1, 0.15)
	end)
	button.MouseButton1Down:Connect(function()
		tweenTo(0.9, 0.08)
	end)
	button.MouseButton1Up:Connect(function()
		tweenTo(1.06, 0.15)
	end)
end

-- Pop scale-in for newly shown elements: 0.6 -> 1 with Back easing.
function UiKit.pop(target: Instance)
	local scale = target:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "PopScale"
		scale.Parent = target
	end
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Candy button: shade gradient + corner 16 + ink outline 4 + gloss strip
-- + LuckiestGuy title (+ optional cream sub-line) + shadow + bouncy.
-- The visible text lives in child labels ("Title"/"Sub") so callers change
-- it with setButtonTitle/setButtonSubtitle; the TextButton's own Text
-- stays "" (its UIStroke is the pill border, not a glyph outline).
function UiKit.button(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	color: Color3,
	title: string,
	subtitle: string?
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.Parent = parent
	UiKit.shade(button, color, 0.28, 0.12)
	UiKit.corner(button, 16)
	UiKit.outline(button, 4)
	-- Gloss: white strip over the top 30%, inset so it never pokes past
	-- the rounded corners.
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Position = UDim2.new(0, 4, 0, 4)
	gloss.Size = UDim2.new(1, -8, 0.3, 0)
	gloss.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	gloss.BackgroundTransparency = 0.72
	gloss.BorderSizePixel = 0
	gloss.Parent = button
	UiKit.corner(gloss, 10)
	local titleLabel = UiKit.text(
		button,
		"Title",
		UDim2.new(0, 6, 0, 2),
		UDim2.new(1, -12, if subtitle then 0.6 else 1, -4),
		title,
		UiKit.WHITE,
		"title",
		3
	)
	titleLabel.ZIndex = 2
	if subtitle then
		local subLabel = UiKit.text(
			button,
			"Sub",
			UDim2.new(0, 6, 0.58, 0),
			UDim2.new(1, -12, 0.38, -2),
			subtitle,
			Color3.fromRGB(255, 248, 200),
			"body",
			2
		)
		subLabel.ZIndex = 2
	end
	UiKit.addShadow(button)
	UiKit.bouncy(button)
	return button
end

function UiKit.setButtonColor(button: TextButton, color: Color3)
	button.BackgroundColor3 = color
	UiKit.shade(button, color, 0.28, 0.12)
end

function UiKit.setButtonTitle(button: TextButton, title: string)
	local label = button:FindFirstChild("Title")
	if label then
		label.Text = title
	end
end

function UiKit.setButtonSubtitle(button: TextButton, subtitle: string)
	local label = button:FindFirstChild("Sub")
	if label then
		label.Text = subtitle
	end
end

-- A plain rounded frame (no shadow, no gradient) for rows, containers and
-- other internal pieces that do not need the full panel treatment.
function UiKit.makeFrame(parent: Instance, name: string, position: UDim2, size: UDim2, background: Color3, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = background
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	return frame
end

-- A thin accent strip across the top of a panel, inset from the rounded
-- corners so it never overflows the panel's edge.
function UiKit.makeHeaderStrip(parent: Frame, color: Color3): Frame
	local strip = Instance.new("Frame")
	strip.Name = "HeaderStrip"
	strip.Position = UDim2.new(0, 8, 0, 0)
	strip.Size = UDim2.new(1, -16, 0, 4)
	strip.BackgroundColor3 = color
	strip.BackgroundTransparency = 0
	strip.BorderSizePixel = 0
	strip.Parent = parent
	return strip
end

-- A rounded scrolling frame with a thin scrollbar, for grids that outgrow
-- their panel (the 30-species index). Canvas size is set by the caller.
function UiKit.makeScrollingFrame(parent: Instance, name: string, position: UDim2, size: UDim2, background: Color3, transparency: number): ScrollingFrame
	local frame = Instance.new("ScrollingFrame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = background
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.ScrollBarThickness = 6
	frame.ScrollBarImageColor3 = Color3.fromRGB(120, 90, 80)
	frame.ScrollingDirection = Enum.ScrollingDirection.Y
	frame.ElasticBehavior = Enum.ElasticBehavior.Never
	frame.CanvasSize = UDim2.new(0, 0, 0, 0)
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	return frame
end

-- Fixed-size label (FredokaOne) with an ink glyph outline. Pair with
-- fitText for dynamic strings.
function UiKit.makeLabel(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	text: string,
	textSize: number,
	color: Color3,
	bold: boolean
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextSize = textSize
	label.Font = Enum.Font.FredokaOne
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = UiKit.INK
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return label
end

-- Candy button with the old makeButton signature (no subtitle); the title
-- is TextScaled, so textSize is kept for signature compatibility only.
function UiKit.makeButton(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	text: string,
	textSize: number,
	background: Color3
): TextButton
	return UiKit.button(parent, name, position, size, background, text, nil)
end

-- Responsive HUD scale: the whole HUD scales with viewport height instead
-- of re-laying out.
function UiKit.responsiveScale(viewportY: number): number
	return math.clamp(viewportY / 760, 0.55, 1.4)
end

-- Caps a dynamic string so it can never overflow its label.
function UiKit.truncate(text: string, maxChars: number): string
	local length = utf8.len(text) or #text
	if length <= maxChars then
		return text
	end
	return string.sub(text, 1, maxChars - 1) .. "..."
end

-- Shrinks a label's TextSize until the measured text fits its width.
-- Call after the label is parented (AbsoluteSize must be known).
function UiKit.fitText(label: TextLabel, maxTextSize: number, minTextSize: number)
	local width = label.AbsoluteSize.X
	if width <= 0 then
		return
	end
	local size = maxTextSize
	while size > minTextSize do
		local measured = TextService:GetTextSize(label.Text, size, label.Font, Vector2.new(width, 10000))
		if measured.X <= width - 8 then
			break
		end
		size -= 1
	end
	label.TextSize = size
end

return UiKit
