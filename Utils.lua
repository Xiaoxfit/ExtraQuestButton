local addonName, ns = ...
local itemData = ns.itemData

local HBD = LibStub('HereBeDragons-2.0')
local sqrt = math.sqrt

local function GetDistanceSqToPoint(mapID, x, y)
	local playerX, playerY, playerMapID = HBD:GetPlayerZonePosition()
	return (HBD:GetZoneDistance(playerMapID, playerX, playerY, mapID, x, y))
end

local function GetQuestDistanceWithItem(questID)
	local questLogIndex = C_QuestLog.GetLogIndexForQuestID(questID)
	if not questLogIndex then
		return
	end

	local itemLink, _, _, showWhenComplete = GetQuestLogSpecialItemInfo(questLogIndex)
	if not itemLink then
		local fallbackItemID = itemData.questItems[questID]
		if fallbackItemID then
			if type(fallbackItemID) == 'table' then
				for _, itemID in next, fallbackItemID do
					local link = ns:GenerateItemLinkFromID(itemID)
					if GetItemCount(link) > 0 then
						itemLink = link
						break
					end
				end
			else
				itemLink = ns:GenerateItemLinkFromID(fallbackItemID)
			end
		end
	end

	if not itemLink then
		return
	end

	local itemID = GetItemInfoFromHyperlink(itemLink)
	if C_QuestLog.IsComplete(questID) then
		local completeItemZone = itemData.completeItems[itemID]
		if not showWhenComplete and not completeItemZone then
			return
		end

		if completeItemZone and type(completeItemZone) == 'number' then
			if HBD:GetPlayerZone() ~= completeItemZone then
				return
			end
		end

		local noCompleteItem = itemData.noCompleteItems[itemID]
		if noCompleteItem then
			if type(noCompleteItem) == 'number' then
				itemLink = ns:GenerateItemLinkFromID(noCompleteItem)
				itemID = noCompleteItem
			else
				return
			end
		end
	end

	if GetItemCount(itemLink) == 0 then
		-- no point showing items we don't have
		return
	end

	if itemData.itemBlacklist[itemID] then
		-- don't show items we specifically want to ignore
		return
	end

	local maxDistanceYd = ns.db.profile.distanceYd
	local distanceSq, onContinent = C_QuestLog.GetDistanceSqToQuest(questID)
	 -- the square root of distanceSq is in yards, much easier to work with
	local distanceYd = distanceSq and sqrt(distanceSq)
	if distanceYd and distanceYd <= maxDistanceYd then
		return distanceYd, itemLink
	end

	local accurateQuestAreaData = itemData.accurateQuestAreas[questID]
	if accurateQuestAreaData then
		local distanceSq = GetDistanceSqToPoint(accurateQuestAreaData[1], accurateQuestAreaData[2], accurateQuestAreaData[3])
		if distanceSq then
			return sqrt(distanceSq), itemLink
		end
	end

	local questMapID = itemData.inaccurateQuestAreas[questID]
	if questMapID then
		if type(questMapID) == 'boolean' then
			return maxDistanceYd - 1, itemLink
		elseif type(questMapID) == 'number' then
			if questMapID == HBD:GetPlayerZone() then
				return maxDistanceYd - 2, itemLink
			end
		elseif type(questMapID) == 'table' then
			local playerMapID = HBD:GetPlayerZone()
			for _, mapID in next, questMapID do
				if mapID == playerMapID then
					return maxDistanceYd - 2, itemLink
				end
			end
		end
	end
end

local function IsQuestOnMapCurrentMap(questID)
	local isOnMap = C_QuestLog.IsOnMap(questID)
	if not isOnMap then
		local accurateQuestAreaInfo = itemData.accurateQuestAreas[questID]
		if accurateQuestAreaInfo then
			isOnMap = accurateQuestAreaInfo[1] == HBD:GetPlayerZone()
		end
	end

	if not isOnMap then
		local inaccurateQuestAreaInfo = itemData.inaccurateQuestAreas[questID]
		if inaccurateQuestAreaInfo then
			if type(inaccurateQuestAreaInfo) == 'boolean' then
				isOnMap = true
			elseif type(inaccurateQuestAreaInfo) == 'table' then
				local playerMapID = HBD:GetPlayerZone()
				for _, mapID in next, inaccurateQuestAreaInfo do
					if mapID == playerMapID then
						isOnMap = true
						break
					end
				end
			else
				isOnMap = inaccurateQuestAreaInfo == HBD:GetPlayerZone()
			end
		end
	end

	return isOnMap
end

-- adaptation of QuestSuperTracking_ChooseClosestQuest for quests with items
function ns:GetClosestQuestItem()
	local closestQuestItemLink
	local closestDistance = ns.db.profile.distanceYd -- yards
	local onlyInZone = ns.db.profile.zoneOnly

	for index = 1, C_QuestLog.GetNumWorldQuestWatches() do
		-- this only tracks supertracked worldquests,
		-- e.g. stuff the player has shift-clicked on the map
		local questID = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(index)
		if questID and (not onlyInZone or IsQuestOnMapCurrentMap(questID)) then
			local distance, itemLink = GetQuestDistanceWithItem(questID)
			if distance and distance <= closestDistance then
				closestDistance = distance
				closestQuestItemLink = itemLink
			end
		end
	end

	if not closestQuestItemLink then
		for index = 1, C_QuestLog.GetNumQuestWatches() do
			local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
			if questID and QuestHasPOIInfo(questID) and (not onlyInZone or IsQuestOnMapCurrentMap(questID)) then
				local distance, itemLink = GetQuestDistanceWithItem(questID)
				if distance and distance <= closestDistance then
					closestDistance = distance
					closestQuestItemLink = itemLink
				end
			end
		end
	end

	if not closestQuestItemLink then
		local onlyIfWatched = ns.db.profile.trackingOnly

		for index = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(index)
			if info and not info.isHeader and QuestHasPOIInfo(info.questID) then
				local questID = info.questID
				-- world quests are always considered
				if not (onlyIfWatched or info.isHidden) or C_QuestLog.IsWorldQuest(questID) then
					if not onlyInZone or IsQuestOnMapCurrentMap(questID) then
						local distance, itemLink = GetQuestDistanceWithItem(questID)
						if distance and distance <= closestDistance then
							closestDistance = distance
							closestQuestItemLink = itemLink
						end
					end
				end
			end
		end
	end

	if closestQuestItemLink then
		return closestQuestItemLink
	end
end

local NPC_ID_PATTERN = '%w+%-.-%-.-%-.-%-.-%-(.-)%-'
function ns:GetNPCID(unit)
	if unit then
		local npcGUID = UnitGUID(unit)
		if npcGUID then
			return tonumber(npcGUID:match(NPC_ID_PATTERN))
		end
	end
end

function ns:GenerateItemLinkFromID(itemID)
	return string.format('|Hitem:%d|h', itemID)
end

function ns:Print(...)
	print('|cff33ff99' .. addonName .. '|r', ...)
end
