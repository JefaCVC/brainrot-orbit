--!strict
-- FormatUtil
-- Shared number and time formatting for BRAINROT ORBIT: short money strings
-- ($1.2K, $3.4M), countdown clocks (1:05) and plain integers with separators.
-- Pure functions, no state, safe to require on server and client.

local FormatUtil = {}

-- Shortens a credit amount for HUD labels: 999 -> "$999", 1200 -> "$1.2K",
-- 3_400_000 -> "$3.4M", 50_000 -> "$50K". Never returns more than 8 characters.
function FormatUtil.formatMoney(amount: number): string
	if amount ~= amount or math.abs(amount) == math.huge then
		return "$0"
	end
	local sign = ""
	local value = amount
	if value < 0 then
		sign = "-"
		value = -value
	end
	if value >= 1_000_000_000 then
		return `{sign}${string.format("%.1f", value / 1_000_000_000)}B`
	elseif value >= 1_000_000 then
		return `{sign}${string.format("%.1f", value / 1_000_000)}M`
	elseif value >= 10_000 then
		return `{sign}${string.format("%.0f", value / 1000)}K`
	elseif value >= 1000 then
		return `{sign}${string.format("%.1f", value / 1000)}K`
	else
		return `{sign}${math.floor(value + 0.5)}`
	end
end

-- Plain integer with thousands separators: 1234567 -> "1,234,567".
function FormatUtil.formatInteger(amount: number): string
	local whole = math.floor(math.abs(amount) + 0.5)
	local text = tostring(whole)
	local parts = {}
	while #text > 3 do
		table.insert(parts, 1, string.sub(text, -3))
		text = string.sub(text, 1, -4)
	end
	table.insert(parts, 1, text)
	local joined = table.concat(parts, ",")
	if amount < 0 then
		return "-" .. joined
	end
	return joined
end

-- Countdown clock: 75 -> "1:15", 8 -> "0:08". Clamps negatives to 0:00.
function FormatUtil.formatCountdown(seconds: number): string
	local total = math.max(0, math.floor(seconds + 0.5))
	local minutes = math.floor(total / 60)
	local rest = total % 60
	return `{minutes}:{string.format("%02d", rest)}`
end

-- Credits-per-second label: 8 -> "$8/s", 1250 -> "$1.2K/s".
function FormatUtil.formatRate(ratePerSecond: number): string
	return `{FormatUtil.formatMoney(ratePerSecond)}/s`
end

-- Multiplier label: 1 -> "x1", 1.5 -> "x1.5", 3 -> "x3".
function FormatUtil.formatMultiplier(multiplier: number): string
	if multiplier == math.floor(multiplier) then
		return `x{math.floor(multiplier)}`
	end
	return `x{string.format("%.1f", multiplier)}`
end

return FormatUtil
