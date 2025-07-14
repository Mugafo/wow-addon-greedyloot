-- Greedy Loot: Automates loot roll confirmations and auto-greeding based on item quality and type
-- Supports auto-confirming BoP items, need/greed rolls, and auto-greeding with exclusions

-- Only keep constants that are actually used
-- Create the addon object
GreedyLoot = LibStub("AceAddon-3.0"):NewAddon("Greedy Loot", "AceConsole-3.0", "AceEvent-3.0")

-- ============================================================================
-- CONSTANTS
-- ============================================================================

GreedyLoot.Constants = {
    -- Item Classes (from WoW API)
    ITEM_CLASS = {
        WEAPON = 2,
        ARMOR = 4,
        RECIPE = 9,
        BATTLE_PET = 17,
    },
    
    -- Roll Types
    ROLL_TYPE = {
        PASS = 0,
        NEED = 1,
        GREED = 2,
    },
    
    -- Class-specific data
    CLASS_DATA = {
        ARMOR_PROFICIENCY = {
            DEATHKNIGHT = 4,
            DRUID = 2,
            HUNTER = 3,
            MAGE = 1,
            MONK = 2,
            PALADIN = 4,
            PRIEST = 1,
            ROGUE = 2,
            SHAMAN = 3,
            WARLOCK = 1,
            WARRIOR = 4,
        },
        WEAPON_PROFICIENCY = {
            DEATHKNIGHT = {
                0, 1, 4, 5, 6, 7, 8, 11
            },
            DRUID = {
                4, 5, 6, 10, 13, 15
            },
            HUNTER = {
                0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 18
            },
            MAGE = {
                7, 8, 10, 15, 19
            },
            MONK = {
                0, 4, 6, 7, 10, 13
            },
            PALADIN = {
                0, 1, 4, 5, 6, 7, 8, 11
            },
            PRIEST = {
                4, 10, 15, 19
            },
            ROGUE = {
                0, 2, 3, 4, 7, 13, 15, 16, 18
            },
            SHAMAN = {
                0, 1, 4, 5, 6, 10, 11, 13, 15
            },
            WARLOCK = {
                7, 8, 10, 15, 19
            },
            WARRIOR = {
                0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18
            },
        },
    },
}

-- Assign options and defaults from Options.lua
GreedyLoot.defaults = GreedyLoot_Defaults
GreedyLoot.options = GreedyLoot_Options
GreedyLoot.options.handler = GreedyLoot

-- ============================================================================
-- OPTIONS HANDLING
-- ============================================================================

function GreedyLoot:GetOption(info)
    return GreedyLoot.db.profile[info[#info]]
end

function GreedyLoot:SetOption(info, input)
    GreedyLoot.db.profile[info[#info]] = input
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Helper function to analyze class restrictions from tooltip
local function GL_AnalyzeClassRestriction(itemLink)
    if not itemLink then
        return nil
    end
    
    local tooltip = CreateFrame("GameTooltip", "GLClassAnalysisTooltip", nil, "GameTooltipTemplate")
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:SetHyperlink(itemLink)
    
    local classRestriction = {
        hasRestriction = false,
        allowedClasses = {},
        playerClass = nil,
        playerClassLocalized = nil,
        playerCanUse = false,
        tooltipLines = {}
    }
    
    -- Get player class info
    classRestriction.playerClassLocalized, classRestriction.playerClass = UnitClass("player")
    
    -- Scan tooltip lines
    for i = 1, tooltip:NumLines() do
        local line = _G["GLClassAnalysisTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                table.insert(classRestriction.tooltipLines, text)
                
                -- Check for class restrictions
                if text:find("^Classes:") then
                    classRestriction.hasRestriction = true
                    
                    -- Extract class names from the "Classes: Priest, Mage" format
                    local classList = text:gsub("^Classes:%s*", "")
                    for class in classList:gmatch("[^,]+") do
                        class = class:match("^%s*(.-)%s*$") -- trim whitespace
                        if class and class ~= "" then
                            table.insert(classRestriction.allowedClasses, class)
                            
                            -- Check if player's class is in the allowed list
                            local classUpper = class:upper():gsub("%s+", "") -- Remove spaces
                            local playerClassUpper = classRestriction.playerClass:upper()
                            
                            if classUpper == playerClassUpper then
                                classRestriction.playerCanUse = true
                            end
                        end
                    end
                end
            end
        end
    end
    
    tooltip:Hide()
    
    return classRestriction
end

-- Helper function to get item type text
local function GL_GetItemTypeText(itemClassID, itemSubClassID)
    if itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON then
        return "Weapon"
    elseif itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR then
        return "Armor"
    elseif itemClassID == GreedyLoot.Constants.ITEM_CLASS.RECIPE then
        return "Recipe"
    elseif itemClassID == GreedyLoot.Constants.ITEM_CLASS.BATTLE_PET then
        return "Battle Pet"
    else
        return "Other"
    end
end

-- Check if an armor type is the best for the current class
local function GL_IsBestArmorTypeForClass(itemSubClassID, playerClass)
    local bestArmorType = GreedyLoot.Constants.CLASS_DATA.ARMOR_PROFICIENCY[playerClass]
    if not bestArmorType then
        return false
    end
    return itemSubClassID == bestArmorType
end

-- Check if a class can equip a specific weapon type
local function GL_CanClassEquipWeapon(itemSubClassID, playerClass)
    local classWeapons = GreedyLoot.Constants.CLASS_DATA.WEAPON_PROFICIENCY[playerClass]
    if not classWeapons then
        return false
    end
    for _, weaponType in ipairs(classWeapons) do
        if weaponType == itemSubClassID then
            return true
        end
    end
    return false
end

-- Check if an item has vendor sell value
local function GL_HasVendorValue(itemLink)
    if not itemLink then
        return false
    end
    
    -- Get item info using array destructuring for cleaner code
    local itemInfo = {GetItemInfo(itemLink)}
    
    -- Check if GetItemInfo returned valid data
    if not itemInfo or #itemInfo < 11 then
        return false
    end
    
    local sellPrice = itemInfo[11]
    
    -- Return true if the item has a sell price greater than 0
    return sellPrice and sellPrice > 0
end

-- Extract item ID from item link
local function GL_GetItemIDFromLink(itemLink)
    if not itemLink then
        return nil
    end
    local itemID = select(3, strfind(itemLink, "item:(%d+)"))
    return itemID and tonumber(itemID) or nil
end

-- Check if an item is a weapon slot item (including shields and off-hand)
local function GL_IsWeaponSlotItem(itemEquipLoc)
    if not itemEquipLoc or itemEquipLoc == "" then
        return false
    end
    -- Check if it's a weapon slot item
    local weaponSlots = {
        "INVTYPE_WEAPON",
        "INVTYPE_2HWEAPON", 
        "INVTYPE_WEAPONMAINHAND",
        "INVTYPE_WEAPONOFFHAND",
        "INVTYPE_SHIELD",
        "INVTYPE_HOLDABLE"
    }
    for _, slot in ipairs(weaponSlots) do
        if itemEquipLoc == slot then
            return true
        end
    end
    return false
end

-- Check if an item is collected for transmog
local function GL_IsItemCollectedForTransmog(itemLink)
    local itemID = GL_GetItemIDFromLink(itemLink)
    if not itemID then
        return false
    end
    
    local tooltip = CreateFrame("GameTooltip", "GLTransmogCheckTooltip", nil, "GameTooltipTemplate")
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:SetHyperlink(itemLink)
    
    local foundNotCollected = false
    
    -- Look for transmog-related text in tooltip
    for i = 1, tooltip:NumLines() do
        local line = _G["GLTransmogCheckTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                -- Check for specific not collected phrase
                if text:find("You haven't collected this appearance") then
                    foundNotCollected = true
                end
            end
        end
    end
    
    tooltip:Hide()
    
    -- Return based on what we found
    if foundNotCollected then
        return false
    else
        return true
    end
end

-- Check if a recipe is already learned
local function GL_IsRecipeLearned(itemLink)
    local itemID = GL_GetItemIDFromLink(itemLink)
    if not itemID then
        return false
    end
    
    local success, recipeInfo = pcall(function()
        if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
            return C_TradeSkillUI.GetRecipeInfo(itemID)
        end
        return nil
    end)
    
    if success and recipeInfo and type(recipeInfo) == "table" then
        return recipeInfo.learned or false
    end
    
    return false
end

-- Helper: Check if item is usable by the player's class by scanning the tooltip
local function GL_ItemIsUsableByPlayerClass(itemLink)
    if not itemLink then 
        return false 
    end
    local playerClassLocalized, playerClass = UnitClass("player")
    local allowed = true
    local tooltip = CreateFrame("GameTooltip", "GLClassCheckTooltip", nil, "GameTooltipTemplate")
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:SetHyperlink(itemLink)
    
    for i = 2, tooltip:NumLines() do
        local line = _G["GLClassCheckTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text:find("^Classes:") then
                allowed = false
                -- Extract class names from the "Classes: Priest, Mage" format
                local classList = text:gsub("^Classes:%s*", "")
                local classes = {}
                for class in classList:gmatch("[^,]+") do
                    class = class:match("^%s*(.-)%s*$") -- trim whitespace
                    if class and class ~= "" then
                        table.insert(classes, class)
                    end
                end
                -- Check if player's class is in the allowed list
                for _, allowedClass in ipairs(classes) do
                    -- Convert both to uppercase and remove spaces for case-insensitive comparison
                    local allowedClassUpper = allowedClass:upper():gsub("%s+", "") -- Remove spaces
                    local playerClassUpper = playerClass:upper()
                    
                    if allowedClassUpper == playerClassUpper then
                        allowed = true
                        break
                    end
                end
                break
            end
        end
    end
    tooltip:Hide()
    
    return allowed
end

-- Check if gear is usable by the current character
local function GL_IsGearUsable(itemLink, itemClassID, itemSubClassID, itemEquipLoc, itemBindType)
    if not itemLink then
        return false
    end    
    if not itemClassID then
        return false
    end
    
    -- Check if it's a weapon slot item (including shields and off-hand)
    local isWeaponSlotItem = GL_IsWeaponSlotItem(itemEquipLoc)
    
    -- If it's a weapon slot item, treat it as a weapon regardless of itemClassID
    if isWeaponSlotItem then
        local _, playerClass = UnitClass("player")
        
        -- Check if the weapon subclass is in the class's proficiency list
        local classWeapons = GreedyLoot.Constants.CLASS_DATA.WEAPON_PROFICIENCY[playerClass]
        if not classWeapons then
            return false
        end
        
        local canEquipWeapon = false
        for _, weaponType in ipairs(classWeapons) do
            if weaponType == itemSubClassID then
                canEquipWeapon = true
                break
            end
        end
        
        if not canEquipWeapon then
            return false
        end

        -- Check class restrictions
        local classRestrictionCheck = GL_ItemIsUsableByPlayerClass(itemLink)
        
        if not classRestrictionCheck then
            return false
        end

        return true
    end

    if itemClassID ~= GreedyLoot.Constants.ITEM_CLASS.WEAPON and itemClassID ~= GreedyLoot.Constants.ITEM_CLASS.ARMOR then
        return false
    end

    if itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR then
        local _, playerClass = UnitClass("player")
        
        -- For armor types 1-4 (cloth, leather, mail, plate), check if it matches the class's best armor type
        if itemSubClassID >= 1 and itemSubClassID <= 4 then
            local bestArmorType = GreedyLoot.Constants.CLASS_DATA.ARMOR_PROFICIENCY[playerClass]
            if not bestArmorType or itemSubClassID ~= bestArmorType then
                return false
            end
        end
        -- For armor types outside 1-4 (like shields, back, tabard), allow them
        
        -- Check class restrictions
        local classRestrictionCheck = GL_ItemIsUsableByPlayerClass(itemLink)
        
        if not classRestrictionCheck then
            return false
        end
        
        return true
    end

    if itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON then
        local _, playerClass = UnitClass("player")
        
        -- Check if the weapon subclass is in the class's proficiency list
        local classWeapons = GreedyLoot.Constants.CLASS_DATA.WEAPON_PROFICIENCY[playerClass]
        if not classWeapons then
            return false
        end
        
        local canEquipWeapon = false
        for _, weaponType in ipairs(classWeapons) do
            if weaponType == itemSubClassID then
                canEquipWeapon = true
                break
            end
        end
        
        if not canEquipWeapon then
            return false
        end

        -- Check class restrictions
        local classRestrictionCheck = GL_ItemIsUsableByPlayerClass(itemLink)
        
        if not classRestrictionCheck then
            return false
        end

        return true
    end

    return false
end

local function GL_ExtractBasicItemData(rollIdOrItemLink)
    if not rollIdOrItemLink then
        return nil
    end
    
    local itemLink = nil
    local rollData = nil
    
    -- Determine if we're dealing with a rollId or itemLink
    if type(rollIdOrItemLink) == "number" then
        -- It's a rollId, get loot roll info
        local name, texture, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant = GetLootRollItemInfo(rollIdOrItemLink)
        itemLink = GetLootRollItemLink(rollIdOrItemLink)
        
        rollData = {
            name = name,
            texture = texture,
            count = count,
            quality = quality,
            bindOnPickUp = bindOnPickUp,
            canNeed = canNeed,
            canGreed = canGreed,
            canDisenchant = canDisenchant,
            reasonNeed = reasonNeed,
            reasonGreed = reasonGreed,
            reasonDisenchant = reasonDisenchant,
        }
    else
        -- It's an itemLink, use it directly
        itemLink = rollIdOrItemLink
        
        -- For debug purposes, assume these values
        rollData = {
            name = nil,
            texture = nil,
            count = 1,
            quality = nil, -- Will be set from GetItemInfo
            bindOnPickUp = nil, -- Will be set from GetItemInfo
            canNeed = false,
            canGreed = true,
            canDisenchant = false,
            reasonNeed = nil,
            reasonGreed = nil,
            reasonDisenchant = nil,
        }
    end
    
    if not itemLink then
        return nil
    end
    
    -- Get detailed item info
    local itemInfo = {GetItemInfo(itemLink)}
    if not itemInfo or #itemInfo < 13 then
        return nil
    end
    
    -- Extract all the information we need
    local itemData = {
        -- From GetLootRollItemInfo (or defaults for debug)
        name = rollData.name,
        texture = rollData.texture,
        count = rollData.count,
        quality = rollData.quality or itemInfo[3], -- Use roll quality or fallback to item rarity
        bindOnPickUp = rollData.bindOnPickUp or (itemInfo[14] == 1), -- Use roll bind or fallback to item bind type
        canNeed = rollData.canNeed,
        canGreed = rollData.canGreed,
        canDisenchant = rollData.canDisenchant,
        reasonNeed = rollData.reasonNeed,
        reasonGreed = rollData.reasonGreed,
        reasonDisenchant = rollData.reasonDisenchant,
        
        -- From GetItemInfo
        itemLink = itemLink,
        itemName = itemInfo[1],
        itemRarity = itemInfo[3],
        itemLevel = itemInfo[4],
        itemMinLevel = itemInfo[5],
        itemType = itemInfo[6],
        itemSubType = itemInfo[7],
        itemStackCount = itemInfo[8],
        itemEquipLoc = itemInfo[9],
        itemTexture = itemInfo[10],
        itemSellPrice = itemInfo[11],
        itemClassID = itemInfo[12],
        itemSubClassID = itemInfo[13],
        itemBindType = itemInfo[14],
        itemExpacID = itemInfo[15],
        itemSetID = itemInfo[16],
        itemIsCraftingReagent = itemInfo[17],
        
        -- Derived information
        isRecipe = (itemInfo[12] == GreedyLoot.Constants.ITEM_CLASS.RECIPE),
        isUsable = GL_IsGearUsable(itemLink, itemInfo[12], itemInfo[13], itemInfo[9], itemInfo[14]),
        isLearned = (itemInfo[12] == GreedyLoot.Constants.ITEM_CLASS.RECIPE) and GL_IsRecipeLearned(itemLink),
        hasVendorValue = GL_HasVendorValue(itemLink),
        isTransmogCollected = GL_IsItemCollectedForTransmog(itemLink),
        isWeaponSlotItem = GL_IsWeaponSlotItem(itemInfo[9]),
        
        -- Class restriction analysis
        classRestriction = GL_AnalyzeClassRestriction(itemLink),
    }
    
    return itemData
end

local function GL_EnrichWithItemInfo(itemData)
    -- Add detailed item information
    local itemInfo = {GetItemInfo(itemData.itemLink)}
    if not itemInfo or #itemInfo < 13 then
        return
    end
    itemData.itemName = itemInfo[1]
    itemData.itemRarity = itemInfo[3]
    itemData.itemLevel = itemInfo[4]
    itemData.itemMinLevel = itemInfo[5]
    itemData.itemType = itemInfo[6]
    itemData.itemSubType = itemInfo[7]
    itemData.itemStackCount = itemInfo[8]
    itemData.itemEquipLoc = itemInfo[9]
    itemData.itemTexture = itemInfo[10]
    itemData.itemSellPrice = itemInfo[11]
    itemData.itemClassID = itemInfo[12]
    itemData.itemSubClassID = itemInfo[13]
    itemData.itemBindType = itemInfo[14]
    itemData.itemExpacID = itemInfo[15]
    itemData.itemSetID = itemInfo[16]
    itemData.itemIsCraftingReagent = itemInfo[17]
end

local function GL_AddDerivedProperties(itemData)
    -- Add computed properties like isUsable, hasVendorValue, etc.
    itemData.isUsable = GL_IsGearUsable(itemData.itemLink, itemData.itemClassID, itemData.itemSubClassID, itemData.itemEquipLoc, itemData.itemBindType)
    itemData.isLearned = (itemData.itemClassID == GreedyLoot.Constants.ITEM_CLASS.RECIPE) and GL_IsRecipeLearned(itemData.itemLink)
    itemData.hasVendorValue = GL_HasVendorValue(itemData.itemLink)
    itemData.isTransmogCollected = GL_IsItemCollectedForTransmog(itemData.itemLink)
    itemData.isWeaponSlotItem = GL_IsWeaponSlotItem(itemData.itemEquipLoc)
end

-- Gather all item information for a loot roll or item link in one place
local function GL_GatherItemInfo(rollIdOrItemLink)
    local itemData = GL_ExtractBasicItemData(rollIdOrItemLink)
    if not itemData then return nil end
    
    GL_EnrichWithItemInfo(itemData)
    GL_AddDerivedProperties(itemData)
    
    return itemData
end

-- ============================================================================
-- LOOT ROLL FRAME HOOKING
-- ============================================================================

-- Hook the loot roll frame to detect when rolls start
local function GL_HookLootRollFrame()
    -- Check if GroupLootFrame exists before trying to hook it
    if GroupLootFrame then
        -- Hook the GroupLootFrame to detect when it shows
        GroupLootFrame:HookScript("OnShow", function()
            -- Use a small delay to ensure the frame is fully loaded
            C_Timer.After(0.1, function()
                GL_CheckForAutoGreed()
            end)
        end)
    else
        -- If GroupLootFrame doesn't exist yet, try to hook it later
        -- Try to hook it again after a short delay
        C_Timer.After(1.0, function()
            if GroupLootFrame then
                GroupLootFrame:HookScript("OnShow", function()
                    -- Use a small delay to ensure the frame is fully loaded
                    C_Timer.After(0.1, function()
                        GL_CheckForAutoGreed()
                    end)
                end)
            end
        end)
    end
end

-- Check if we should auto-greed on the current loot roll
local function GL_CheckForAutoGreed()
    -- Get all item data at once
    local itemData = GL_GatherItemInfo(GroupLootFrame.rollId)
    if not itemData then
        return
    end

    -- Use the gathered data
    local itemLink = itemData.itemLink
    local itemClassID = itemData.itemClassID

    -- Call the ShouldAutoGreed function to get the decision
    local shouldGreed = GL_ShouldAutoGreed(itemData)

    -- Determine the action and decision data
    local action = "NO_ACTION"

    -- Check if we should pass
    local shouldPass = GL_ShouldPass(itemData)
    if shouldPass then
        action = "PASS"
    elseif shouldGreed and itemData.canGreed then
        action = "GREED"
        ConfirmLootRoll(GroupLootFrame.rollId, GreedyLoot.Constants.ROLL_TYPE.GREED)
    end

    -- Format decision data for debug window
    if GreedyLoot.Debug then
        local maxQuality = nil
        if itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON then
            maxQuality = GreedyLoot.db.profile.autoGreedWeaponsMaxQuality
        elseif itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR then
            maxQuality = GreedyLoot.db.profile.autoGreedArmorMaxQuality
        elseif itemClassID == GreedyLoot.Constants.ITEM_CLASS.RECIPE then
            maxQuality = GreedyLoot.db.profile.autoGreedRecipesMaxQuality
        else
            maxQuality = GreedyLoot.db.profile.autoGreedOtherMaxQuality
        end
        local decisionData = GreedyLoot.Debug:FormatDecisionData(itemLink, itemClassID, itemData.quality, itemData.isUsable, itemData.isRecipe, itemData.isLearned, itemData.bindOnPickUp, itemData.hasVendorValue, itemData.isTransmogCollected, shouldPass, shouldGreed, maxQuality, nil)
        
        -- Always add to debug window if debug module is available
        GreedyLoot.Debug:AddLootDecision(itemLink, itemClassID, itemData.quality, itemData.isUsable, itemData.isRecipe, itemData.isLearned, itemData.bindOnPickUp, itemData.hasVendorValue, itemData.isTransmogCollected, action, decisionData)
    end
end

-- ============================================================================
-- ADDON LIFECYCLE
-- ============================================================================

function GreedyLoot:OnInitialize()
    -- Initialize database with account-wide settings
    GreedyLoot.db = LibStub("AceDB-3.0"):New("GreedyLootDB", GreedyLoot.defaults, true)
    GreedyLoot.version = GetAddOnMetadata("GreedyLoot", "Version")
    
    -- Register options with Blizzard interface
    LibStub("AceConfig-3.0"):RegisterOptionsTable("Greedy Loot", GreedyLoot.options)
    GreedyLoot.optionsDialog = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Greedy Loot")
end

function GreedyLoot:OnEnable()        
    -- Register events for loot roll handling
    GreedyLoot:RegisterEvent("CONFIRM_LOOT_ROLL", "CONFIRM_ROLL")
    GreedyLoot:RegisterEvent("START_LOOT_ROLL", "START_LOOT_ROLL")
    GreedyLoot:RegisterEvent("LOOT_ROLLS_COMPLETE", "LOOT_ROLLS_COMPLETE")
    
    -- Register slash commands
    GreedyLoot:RegisterChatCommand("gl", "OnSlashCommand")
    
    -- Hook the loot roll frame to detect when rolls start
    GL_HookLootRollFrame()
end

function GreedyLoot:OnDisable()
    GreedyLoot:UnregisterEvent("CONFIRM_LOOT_ROLL")
    GreedyLoot:UnregisterEvent("START_LOOT_ROLL")
    GreedyLoot:UnregisterChatCommand("gl")
end

-- ============================================================================
-- SLASH COMMAND HANDLING
-- ============================================================================

function GreedyLoot:OnSlashCommand(input)
    local command = strlower(input or "")    
    if command == "debug" then
        -- Toggle debug window
        if GreedyLoot.Debug then
            GreedyLoot.Debug:Toggle()
        else
            GreedyLoot:Print("Debug module not available")
        end
    else
        -- Open options panel using the appropriate method for the current WoW version
        if Settings and Settings.OpenToCategory then
            Settings.OpenToCategory("Greedy Loot")
        elseif InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory("Greedy Loot")
        elseif InterfaceOptionsFrame then
            InterfaceOptionsFrame:Show()
            InterfaceOptionsFrame_OpenToCategory("Greedy Loot")
        end
    end
end

-- ============================================================================
-- LOOT SLOT HOOKING
-- ============================================================================

-- Hook the original LootSlot function to auto-confirm BoP items and greed rolls
local GL_OriginalLootSlot = LootSlot
local function GL_HookedLootSlot(slot)
    GL_OriginalLootSlot(slot)
    
    -- Auto-confirm BoP items if enabled
    if GreedyLoot.db.profile.autoConfirmBoP then
        ConfirmLootSlot(slot)
    end
    
    -- Auto-confirm greed rolls if enabled
    if GreedyLoot.db.profile.autoConfirmGreed then
        ConfirmLootSlot(slot)
    end
end
LootSlot = GL_HookedLootSlot

-- ============================================================================
-- AUTO-PASS/GREED DECISION LOGIC
-- ============================================================================

-- Returns true if the item should be passed
local function GL_ShouldPass(itemData)
    local db = GreedyLoot.db.profile
    
    -- Always skip battle pets and miscellaneous items (which can include unlearned pets)
    if itemData.itemClassID == GreedyLoot.Constants.ITEM_CLASS.BATTLE_PET or itemData.itemClassID == 15 then
        return false
    end
    
    -- If auto-pass is disabled, never pass
    if not db.autoPassNoVendorPrice then
        return false
    end
    
    -- Don't pass if it's usable gear
    if db.autoPassExceptUsableGear and itemData.isUsable then
        return false
    end
    
    -- Don't pass if item has vendor value
    if itemData.hasVendorValue then
        return false
    end
    
    -- At this point, item has no vendor value and auto-pass is enabled
    -- Check exceptions for items with no vendor value
    
    -- Don't pass if it's non-BoP and is not a recipe
    if db.autoPassExceptNonBoP and not itemData.bindOnPickUp and itemData.isRecipe then
        return false
    end
    
    -- Don't pass if it's an unlearned recipe
    if db.autoPassExceptUnlearned and itemData.isRecipe and not itemData.isLearned then
        return false
    end
    
    -- All conditions met for auto-pass
    return true
end

-- Returns true if the gear should be greeded
local function GL_ShouldGreedGear(itemData)
    local db = GreedyLoot.db.profile
    
    -- Check if it's a weapon slot item first (including shields and off-hand)
    local isWeaponSlotItem = itemData.isWeaponSlotItem
    
    -- Determine if this should be treated as a weapon or armor
    local treatAsWeapon = false
    local treatAsArmor = false
    
    if isWeaponSlotItem then
        treatAsWeapon = true
    elseif itemData.itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON then
        treatAsWeapon = true
    elseif itemData.itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR then
        treatAsArmor = true
    end
    
    -- Check weapon settings
    if treatAsWeapon then
        if not db.autoGreedWeapons then
            return false
        end
        if itemData.quality > db.autoGreedWeaponsMaxQuality then
            return false
        end
    -- Check armor settings
    elseif treatAsArmor then
        if not db.autoGreedArmor then
            return false
        end
        if itemData.quality > db.autoGreedArmorMaxQuality then
            return false
        end
    else
        -- Not a weapon or armor
        return false
    end
    
    -- Check exceptions
    if db.autoGreedGearExceptBoP and not itemData.bindOnPickUp then
        return false
    end
    
    if db.autoGreedGearExceptUsable and itemData.isUsable then
        return false
    end
    
    if db.autoGreedGearExceptNoVendorPrice and not itemData.hasVendorValue then
        return false
    end
    
    if db.autoGreedGearExceptTransmog and itemData.isUsable and not itemData.isTransmogCollected then
        return false
    end
    
    -- All conditions met for auto-greed gear
    return true
end

-- Returns true if the other item should be greeded
local function GL_ShouldGreedOther(itemData)
    local db = GreedyLoot.db.profile
    
    -- Always skip battle pets and miscellaneous items (which can include unlearned pets)
    if itemData.itemClassID == GreedyLoot.Constants.ITEM_CLASS.BATTLE_PET or itemData.itemClassID == 15 then
        return false
    end
    
    -- Check recipe settings
    if itemData.itemClassID == GreedyLoot.Constants.ITEM_CLASS.RECIPE then
        if not db.autoGreedRecipes then
            return false
        end
        if itemData.quality > db.autoGreedRecipesMaxQuality then
            return false
        end
    -- Check other items settings
    else
        if not db.autoGreedOther then
            return false
        end
        if itemData.quality > db.autoGreedOtherMaxQuality then
            return false
        end
    end
    
    -- Check exceptions
    if db.autoGreedOtherExceptNoVendorPrice and not itemData.hasVendorValue then
        return false
    end
    
    if db.autoGreedOtherExceptUsableGear and itemData.isUsable then
        return false
    end
    
    if db.autoGreedOtherExceptTransmog and itemData.isUsable and not itemData.isTransmogCollected then
        return false
    end
    
    if db.autoGreedOtherExceptUnlearned and itemData.isRecipe and not itemData.isLearned then
        return false
    end
    
    -- All conditions met for auto-greed other
    return true
end

-- Main decision function for auto-greed
local function GL_ShouldAutoGreed(itemData)
    -- Always skip battle pets and miscellaneous items (which can include unlearned pets)
    if itemData.itemClassID == GreedyLoot.Constants.ITEM_CLASS.BATTLE_PET or itemData.itemClassID == 15 then
        return false
    end

    -- Check if we should pass
    local shouldPass = GL_ShouldPass(itemData)
    if shouldPass then
        return false
    end

    -- Check if it's a weapon slot item or gear item
    local isWeaponSlotItem = itemData.isWeaponSlotItem
    local isGearItem = (itemData.itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON or itemData.itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR or isWeaponSlotItem)

    -- Check if we should greed gear
    if isGearItem then
        local shouldGreedGear = GL_ShouldGreedGear(itemData)
        return shouldGreedGear
    end

    -- Check if we should greed other items
    local shouldGreedOther = GL_ShouldGreedOther(itemData)
    return shouldGreedOther
end

-- Main roll handler
local function GL_HandleLootRoll(rollId)
    local itemData = GL_GatherItemInfo(rollId)
    if not itemData then
        return
    end

    local itemLink = itemData.itemLink
    local itemClassID = itemData.itemClassID

    -- Determine the action and decision data
    local action = "NO_ACTION"

    -- Check if we should pass
    local shouldPass = GL_ShouldPass(itemData)
    if shouldPass then
        action = "PASS"
        ConfirmLootRoll(rollId, GreedyLoot.Constants.ROLL_TYPE.PASS)
    else
        -- Check if we should greed
        local shouldGreed = false
        local maxQuality = nil

        -- Check if it's a weapon slot item or gear item
        local isWeaponSlotItem = itemData.isWeaponSlotItem
        local isGearItem = (itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON or itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR or isWeaponSlotItem)

        if isGearItem then
            shouldGreed = GL_ShouldGreedGear(itemData)
            -- Determine max quality based on whether it's treated as weapon or armor
            if isWeaponSlotItem or itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON then
                maxQuality = GreedyLoot.db.profile.autoGreedWeaponsMaxQuality
            else
                maxQuality = GreedyLoot.db.profile.autoGreedArmorMaxQuality
            end
        else
            shouldGreed = GL_ShouldGreedOther(itemData)
            if itemClassID == GreedyLoot.Constants.ITEM_CLASS.RECIPE then
                maxQuality = GreedyLoot.db.profile.autoGreedRecipesMaxQuality
            else
                maxQuality = GreedyLoot.db.profile.autoGreedOtherMaxQuality
            end
        end

        if shouldGreed and itemData.canGreed then
            action = "GREED"
            ConfirmLootRoll(rollId, GreedyLoot.Constants.ROLL_TYPE.GREED)
        end

        -- Format decision data for debug window
        if GreedyLoot.Debug then
            local decisionData = GreedyLoot.Debug:FormatDecisionData(itemLink, itemClassID, itemData.quality, itemData.isUsable, itemData.isRecipe, itemData.isLearned, itemData.bindOnPickUp, itemData.hasVendorValue, itemData.isTransmogCollected, shouldPass, shouldGreed, maxQuality, nil)
            
            -- Always add to debug window if debug module is available (regardless of debug mode setting)
            GreedyLoot.Debug:AddLootDecision(itemLink, itemClassID, itemData.quality, itemData.isUsable, itemData.isRecipe, itemData.isLearned, itemData.bindOnPickUp, itemData.hasVendorValue, itemData.isTransmogCollected, action, decisionData)
        end
    end
end

-- ============================================================================
-- LOOT ROLL EVENT HANDLERS
-- ============================================================================

-- Handle loot roll confirmation events (need/greed rolls)
function GreedyLoot:CONFIRM_ROLL(event, rollId, roll)
    local shouldConfirm = false
    
    -- Check if auto-confirmation is enabled for this roll type
    if roll == GreedyLoot.Constants.ROLL_TYPE.NEED and GreedyLoot.db.profile.autoConfirmNeed then
        shouldConfirm = true
    elseif roll == GreedyLoot.Constants.ROLL_TYPE.GREED and GreedyLoot.db.profile.autoConfirmGreed then
        shouldConfirm = true
    end
    
    -- Auto-confirm the roll if conditions are met
    if shouldConfirm then
        ConfirmLootRoll(rollId, roll)
    end
end

-- Handle loot roll start events (determine whether to auto-greed or auto-pass)
function GreedyLoot:START_LOOT_ROLL(event, rollId, rollTime, lootHandle)
    GL_HandleLootRoll(rollId)
end

-- Handle loot rolls complete event
function GreedyLoot:LOOT_ROLLS_COMPLETE(event)
end

-- ============================================================================
-- EXPOSE FUNCTIONS TO DEBUG MODULE
-- ============================================================================

-- Make the functions accessible to debug module
GreedyLoot.GL_IsItemCollectedForTransmog = GL_IsItemCollectedForTransmog
GreedyLoot.GL_ShouldPass = GL_ShouldPass
GreedyLoot.GL_ShouldAutoGreed = GL_ShouldAutoGreed
GreedyLoot.GL_GatherItemInfo = GL_GatherItemInfo
GreedyLoot.GL_GetItemTypeText = GL_GetItemTypeText
GreedyLoot.GL_ItemIsUsableByPlayerClass = GL_ItemIsUsableByPlayerClass
GreedyLoot.GL_IsGearUsable = GL_IsGearUsable
GreedyLoot.GL_IsWeaponSlotItem = GL_IsWeaponSlotItem
GreedyLoot.GL_CanClassEquipWeapon = GL_CanClassEquipWeapon
GreedyLoot.GL_IsBestArmorTypeForClass = GL_IsBestArmorTypeForClass
