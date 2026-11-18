--!strict
-- UiKit
-- Shared UI constructors and text-fit helpers for BRAINROT ORBIT. Every
-- panel, label and button in the game is built through here so the styling
-- stays consistent — and so the "text never overflows its box" rule has one
-- enforcement point: fitText shrinks a label's TextSize until the measured
-- text fits the label's width, and truncate caps dynamic strings.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Color3 = any
type Instance = any
type TextLabel = any
type TextButton = any
type Frame = any
type UDim2 = any

local TextService = game:GetService("TextService")

local UiKit = {}

UiKit.PANEL_BG = Color3.fromRGB(14, 22, 38)
UiKit.PANEL_BG_TRANSPARENCY = 0.12
UiKit.ACCENT = Color3.fromRGB(90, 180, 255)
UiKit.GOLD = Color3.fromRGB(255, 200, 60)
UiKit.GREEN = Color3.fromRGB(90, 220, 130)
UiKit.RED = Color3.fromRGB(255, 100, 100)
UiKit.TEXT = Color3.fromRGB(240, 245, 255)
UiKit.MUTED = Color3.fromRGB(170, 188, 212)
UiKit.BUTTON_BG = Color3.fromRGB(36, 58, 92)
UiKit.BUTTON_BG_HOVER = Color3.fromRGB(52, 82, 128)

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
	label.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

function UiKit.makeButton(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	text: string,
	textSize: number,
	background: Color3
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = background
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = UiKit.TEXT
	button.TextSize = textSize
	button.Font = Enum.Font.GothamBold
	button.TextWrapped = true
	button.AutoButtonColor = true
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	return button
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
