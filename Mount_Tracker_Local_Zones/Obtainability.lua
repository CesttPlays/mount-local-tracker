local _, addon = ...
local L = addon.L

-- Works out *how obtainable* an uncollected mount is right now: can you buy it
-- today, are you short on reputation, is the weekly farm already done, or is it
-- just an open-world drop. Pure functions -- no frames, no events. The inputs
-- come from MountData / Overrides (curated) plus a handful of live player APIs.

local Obtainability = {}
addon.Obtainability = Obtainability

local SafeApiCall = addon.SafeApiCall
local SafeApiCallMulti = addon.SafeApiCallMulti

-- Curated-input lookup: Overrides wins over the generated MountData. See Core.lua.
local pick = addon.Curated

-- state -> { sortRank, colour } . Lower sortRank floats to the top of a group.
local STATE = {
	available         = { rank = 1, color = { 0.40, 0.85, 0.40 } },
	farmable          = { rank = 2, color = { 1.00, 0.82, 0.00 } },
	drop              = { rank = 3, color = { 0.87, 0.86, 0.81 } },
	quest_gated       = { rank = 4, color = { 0.85, 0.55, 0.45 }, dim = true },
	rep_gated         = { rank = 5, color = { 0.85, 0.55, 0.45 }, dim = true },
	achievement_gated = { rank = 6, color = { 0.85, 0.55, 0.45 }, dim = true },
	reset_locked      = { rank = 7, color = { 0.60, 0.60, 0.62 }, dim = true },
	collected         = { rank = 8, color = { 0.50, 0.50, 0.50 } },
}

Obtainability.STATE = STATE

function Obtainability.Color(state)
	local entry = STATE[state] or STATE.drop
	return entry.color[1], entry.color[2], entry.color[3]
end

-- True for states drawn dimmed ("you can't get this here right now").
function Obtainability.IsDimmed(state)
	local e = STATE[state]
	return e and e.dim or false
end

-- ============================================================================
-- Live player checks (each degrades to "unknown" if the API is missing)
-- ============================================================================

-- Current standing value + whether `threshold` is met, for a plain faction or a
-- major faction (renown). Returns current, needed, met, label.
local function ReputationProgress(factionID, threshold)
	threshold = tonumber(threshold) or 0

	if C_MajorFactions and type(C_MajorFactions.GetMajorFactionData) == "function" then
		local data = SafeApiCall(C_MajorFactions.GetMajorFactionData, factionID)
		if type(data) == "table" and data.renownLevel then
			local level = data.renownLevel
			return level, threshold, level >= threshold, L["Renown %d"]:format(level)
		end
	end

	if C_Reputation and type(C_Reputation.GetFactionDataByID) == "function" then
		local data = SafeApiCall(C_Reputation.GetFactionDataByID, factionID)
		if type(data) == "table" and data.currentStanding then
			local standing = data.currentStanding
			return standing, threshold, standing >= threshold, nil
		end
	end

	return nil, threshold, nil, nil
end

local function PlayerMoney()
	return SafeApiCall(GetMoney) or 0
end

local function CurrencyOwned(currencyID)
	if not (C_CurrencyInfo and type(C_CurrencyInfo.GetCurrencyInfo) == "function") then
		return nil
	end
	local info = SafeApiCall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
	return type(info) == "table" and info.quantity or nil
end

local function QuestDoneThisReset(questID)
	if not (C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted) == "function") then
		return nil
	end
	return SafeApiCall(C_QuestLog.IsQuestFlaggedCompleted, questID) and true or false
end

local function AchievementEarned(achievementID)
	local _, _, _, completed = SafeApiCallMulti(GetAchievementInfo, achievementID)
	return completed and true or false
end

-- ============================================================================
-- Money / cost formatting
-- ============================================================================

local function FormatGold(copper)
	local gold = math.floor((tonumber(copper) or 0) / 10000)
	local text = tostring(gold)
	-- thousands separators without depending on locale
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return formatted .. "g"
end

local function VendorDetail(vendor, affordable)
	local cost = vendor.cost
	local currencyID = vendor.currencyID
	local npc = vendor.npc
	local price
	if not cost then
		price = nil
	elseif currencyID then
		price = L["%s |cffffffff(%s)|r"]:format(cost, L["currency"])
	else
		price = FormatGold(cost)
	end
	local parts = {}
	if price then
		parts[#parts + 1] = price
	end
	if npc then
		parts[#parts + 1] = npc
	end
	local detail = table.concat(parts, " \194\183 ")
	if detail == "" then
		detail = affordable and L["available from a vendor"] or L["vendor"]
	end
	return detail
end

-- ============================================================================
-- Evaluate
-- ============================================================================

-- row must carry: isCollected, source. Returns { state, detail, sortRank }.
function Obtainability.Evaluate(mountID, row)
	if row and row.isCollected then
		return { state = "collected", detail = nil, sortRank = STATE.collected.rank }
	end

	local note = pick("note", mountID)
	local dropChance = pick("dropChance", mountID)

	-- 1. Reputation / renown gate.
	local repFaction = pick("repFaction", mountID)
	if type(repFaction) == "table" then
		local factionID = repFaction.factionID
		local threshold = repFaction.standing
		local current, needed, met, label = ReputationProgress(factionID, threshold)
		if met == false then
			local detail = label and L["%s / need %s"]:format(label, tostring(needed))
				or L["%s / %s reputation"]:format(tostring(current or "?"), tostring(needed))
			return { state = "rep_gated", detail = detail, sortRank = STATE.rep_gated.rank }
		end
		-- rep met: fall through, likely a vendor purchase now
	end

	-- 2. Vendor purchase.
	local vendor = pick("vendor", mountID)
	if type(vendor) == "table" then
		local cost = vendor.cost
		local currencyID = vendor.currencyID
		local affordable
		if not cost then
			affordable = true
		elseif currencyID then
			local owned = CurrencyOwned(currencyID)
			affordable = owned == nil or owned >= cost
		else
			affordable = PlayerMoney() >= cost
		end
		return {
			state = affordable and "available" or "rep_gated",
			detail = VendorDetail(vendor, affordable),
			sortRank = affordable and STATE.available.rank or STATE.rep_gated.rank,
		}
	end

	-- 3. Achievement gate.
	local achievementID = pick("achievementID", mountID)
	if achievementID and not AchievementEarned(achievementID) then
		local _, achName = SafeApiCallMulti(GetAchievementInfo, achievementID)
		return {
			state = "achievement_gated",
			detail = type(achName) == "string" and achName ~= "" and achName or L["achievement reward"],
			sortRank = STATE.achievement_gated.rank,
		}
	end

	-- 4. Daily / weekly farm.
	local lockout = pick("lockout", mountID)
	if lockout then
		local questID = pick("lockoutQuest", mountID)
		local done = questID and QuestDoneThisReset(questID)
		if done then
			return {
				state = "reset_locked",
				detail = L["%s \194\183 done this reset"]:format(lockout),
				sortRank = STATE.reset_locked.rank,
			}
		end
		local detail = lockout
		if dropChance then
			detail = ("%s \194\183 %s"):format(lockout, dropChance)
		end
		return { state = "farmable", detail = detail, sortRank = STATE.farmable.rank }
	end

	-- 5. Plain drop / quest / everything else.
	local state = (row and row.source == "quest") and "quest_gated" or "drop"
	if state == "quest_gated" then
		-- We don't resolve mount quest chains yet; treat quest mounts as a plain
		-- objective unless a note says otherwise.
		state = "drop"
	end
	local detail = dropChance or note
	return { state = state, detail = detail, sortRank = STATE[state].rank }
end

-- ============================================================================
-- Tooltip lines (appended to GameTooltip by Core.BindMount)
-- ============================================================================

function Obtainability.AddTooltipLines(tooltip, mountID)
	if type(tooltip) ~= "table" and type(tooltip) ~= "userdata" then
		return
	end
	local info = addon.MountInfo and { addon.MountInfo(mountID) } or {}
	local isCollected = info[11]
	local row = { isCollected = isCollected, source = pick("source", mountID) }
	local result = Obtainability.Evaluate(mountID, row)

	if result.state == "collected" then
		return
	end

	if type(tooltip.AddLine) ~= "function" then
		return
	end
	tooltip:AddLine(" ")
	local r, g, b = Obtainability.Color(result.state)
	local labels = {
		available = L["Available now"],
		farmable = L["Farmable now"],
		rep_gated = L["Reputation needed"],
		achievement_gated = L["Achievement needed"],
		quest_gated = L["Quest needed"],
		reset_locked = L["Locked this reset"],
		drop = L["Not yet collected"],
	}
	tooltip:AddLine(labels[result.state] or L["Not yet collected"], r, g, b)
	if result.detail then
		tooltip:AddLine(result.detail, 0.9, 0.9, 0.9, true)
	end
	local note = pick("note", mountID)
	if note and note ~= result.detail then
		tooltip:AddLine(note, 0.7, 0.7, 0.7, true)
	end

	-- Dim instance-context line derived from the curated sub-category. Only shown
	-- for instance-sourced mounts that have a subcat, and skipped when result.detail
	-- already implies it (e.g. mentions "raid" / "dungeon").
	local subcat = pick("subcat", mountID)
	local SUBCAT_LABEL = { dungeon = L["Dungeon drop"], raid = L["Raid drop"], rare = L["Rare drop"] }
	local subcatLine = row.source == "instance" and subcat and SUBCAT_LABEL[subcat]
	if subcatLine
		and not (result.detail and result.detail:lower():find(subcat:lower(), 1, true)) then
		tooltip:AddLine(subcatLine, 0.5, 0.5, 0.5, true)
	end
end
