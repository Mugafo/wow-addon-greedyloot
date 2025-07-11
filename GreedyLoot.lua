-- Greedy Loot: Automates loot roll confirmations and auto-greeding based on item quality and type
-- Supports auto-confirming BoP items, need/greed rolls, and auto-greeding with exclusions

-- Only keep constants that are actually used
-- Create the addon object
GreedyLoot = LibStub("AceAddon-3.0"):NewAddon("Greedy Loot", "AceConsole-3.0", "AceEvent-3.0")

-- ============================================================================
-- CONSTANTS
-- ============================================================================

GreedyLoot.Constants = {
    ARMOR_SUBCLASS = {
        CLOTH = 1,
        LEATHER = 2,
        MAIL = 3,
        PLATE = 4,
    },
    CLASS_ARMOR_PROFICIENCY = {
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
    CLASS_WEAPON_PROFICIENCY = {
        DEATHKNIGHT = {
            1, 4, 6, 5, 17, 18, 19, 8, 9
        },
        DRUID = {
            4, 6, 5, 18, 19, 8, 9, 7
        },
        HUNTER = {
            1, 6, 5, 17, 19, 2, 3, 11, 8, 9, 7
        },
        MAGE = {
            6, 7, 9, 12
        },
        MONK = {
            1, 4, 6, 5, 17, 18, 19, 8, 9, 7
        },
        PALADIN = {
            1, 4, 6, 5, 17, 18, 19, 15, 16
        },
        PRIEST = {
            4, 7, 9, 12
        },
        ROGUE = {
            1, 4, 6, 5, 8, 9, 10, 11, 2, 3
        },
        SHAMAN = {
            1, 4, 6, 5, 17, 18, 15, 16, 8, 9, 7
        },
        WARLOCK = {
            6, 7, 9, 12
        },
        WARRIOR = {
            1, 4, 6, 5, 17, 18, 19, 15, 16, 8, 9
        },
    },
    ITEM_CLASS = {
        WEAPON = 2,
        ARMOR = 4,
        RECIPE = 9,
        BATTLE_PET = 17,
    },
    ROLL_TYPE = {
        PASS = 0,
        NEED = 1,
        GREED = 2,
    },
    WEAPON_SUBCLASS = {
        AXE = 1,
        BOW = 2,
        GUN = 3,
        MACE = 4,
        POLEARM = 5,
        SWORD = 6,
        STAFF = 7,
        FIST = 8,
        DAGGER = 9,
        THROWN = 10,
        CROSSBOW = 11,
        WAND = 12,
        FISHING_POLE = 13,
        MISC = 14,
        SHIELD = 15,
        OFF_HAND = 16,
        TWO_HANDED_AXE = 17,
        TWO_HANDED_MACE = 18,
        TWO_HANDED_SWORD = 19,
        WARGLAIVE = 20,
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

-- Check if an armor type is the best for the current class
local function GL_IsBestArmorTypeForClass(itemSubClassID, playerClass)
    local bestArmorType = GreedyLoot.Constants.CLASS_ARMOR_PROFICIENCY[playerClass]
    if not bestArmorType then
        return false
    end
    return itemSubClassID == bestArmorType
end

-- Check if a class can equip a specific weapon type
local function GL_CanClassEquipWeapon(itemSubClassID, playerClass)
    local classWeapons = GreedyLoot.Constants.CLASS_WEAPON_PROFICIENCY[playerClass]
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

-- Check if an item is collected for transmog
local function GL_IsItemCollectedForTransmog(itemLink)
    local itemID = GL_GetItemIDFromLink(itemLink)
    if not itemID then
        return false
    end
    
    -- Check if the item is collected for transmog using WoW Classic API
    if C_TransmogCollection and C_TransmogCollection.GetItemInfo then
        local itemInfo = C_TransmogCollection.GetItemInfo(itemID)
        if itemInfo and type(itemInfo) == "table" and itemInfo.isCollected then
            return itemInfo.isCollected
        end
    end
    
    -- Fallback: assume not collected if we can't check
    return false
end

-- Check if a recipe is already learned
local function GL_IsRecipeLearned(itemLink)
    local itemID = GL_GetItemIDFromLink(itemLink)
    if not itemID then
        return false
    end
    
    -- Check if the recipe is learned using WoW Classic API
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(itemID)
        if recipeInfo and type(recipeInfo) == "table" and recipeInfo.learned then
            return recipeInfo.learned
        end
    end
    
    -- Fallback: assume not learned if we can't check
    return false
end

-- Helper: Check if item is usable by the player's class by scanning the tooltip
local function GL_ItemIsUsableByPlayerClass(itemLink)
    if not itemLink then return false end
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
                for class in text:gmatch("%a+") do
                    if class:upper() == playerClass:upper() then
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
local function GL_IsGearUsable(itemLink)
    if not itemLink then
        return false
    end
    local itemInfo = {GetItemInfo(itemLink)}
    if not itemInfo or #itemInfo < 13 then
        if GreedyLoot.db.profile.debugMode then
            GreedyLoot:Print(string.format("→ GL_IsGearUsable: GetItemInfo failed or returned insufficient data"))
        end
        return false
    end
    local itemClassID = itemInfo[12]
    local itemSubClassID = itemInfo[13]
    if not itemClassID then
        if GreedyLoot.db.profile.debugMode then
            GreedyLoot:Print(string.format("→ GL_IsGearUsable: No itemClassID found"))
        end
        return false
    end
    if GreedyLoot.db.profile.debugMode then
        local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
        GreedyLoot:Print(string.format("→ GL_IsGearUsable: %s - itemClassID: %s, itemSubClassID: %s", itemName, itemClassID, itemSubClassID))
    end
    if itemClassID ~= GreedyLoot.Constants.ITEM_CLASS.WEAPON and itemClassID ~= GreedyLoot.Constants.ITEM_CLASS.ARMOR then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_IsGearUsable: %s - Not weapon or armor, returning false", itemName))
        end
        return false
    end
    if itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR then
        local _, playerClass = UnitClass("player")
        local isBestArmorType = GL_IsBestArmorTypeForClass(itemSubClassID, playerClass)
        if GreedyLoot.db.profile.debugMode then
            local armorTypeNames = {[1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate"}
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_IsGearUsable: %s - Armor check - Item type: %s (%s), Player class: %s, Best armor type for class: %s, Is best type: %s", 
                itemName,
                armorTypeNames[itemSubClassID] or "Unknown",
                itemSubClassID,
                playerClass, 
                GreedyLoot.Constants.CLASS_ARMOR_PROFICIENCY[playerClass] or "None",
                isBestArmorType and "Yes" or "No"))
        end
        if not isBestArmorType then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_IsGearUsable: %s - Not best armor type for class, returning false", itemName))
            end
            return false
        end
        -- Use tooltip class check
        if not GL_ItemIsUsableByPlayerClass(itemLink) then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_IsGearUsable: %s - Tooltip class check failed, returning false", itemName))
            end
            return false
        end
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_IsGearUsable: %s - Best armor type for class and tooltip class check passed, returning true", itemName))
        end
        return true
    end
    if itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON then
        local _, playerClass = UnitClass("player")
        local canEquipWeapon = GL_CanClassEquipWeapon(itemSubClassID, playerClass)
        if GreedyLoot.db.profile.debugMode then
            local weaponTypeNames = {[1] = "Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Polearm", [6] = "Sword", [7] = "Staff", [8] = "Fist", [9] = "Dagger", [10] = "Thrown", [11] = "Crossbow", [12] = "Wand", [13] = "Fishing Pole", [14] = "Misc", [15] = "Shield", [16] = "Off Hand", [17] = "Two-Handed Axe", [18] = "Two-Handed Mace", [19] = "Two-Handed Sword", [20] = "Warglaive"}
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_IsGearUsable: %s - Weapon check - Item type: %s (%s), Player class: %s, Can equip: %s", 
                itemName,
                weaponTypeNames[itemSubClassID] or "Unknown",
                itemSubClassID,
                playerClass, 
                canEquipWeapon and "Yes" or "No"))
        end
        if not canEquipWeapon then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_IsGearUsable: %s - Cannot equip weapon type, returning false", itemName))
            end
            return false
        end
        if not GL_ItemIsUsableByPlayerClass(itemLink) then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_IsGearUsable: %s - Tooltip class check failed for weapon, returning false", itemName))
            end
            return false
        end
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_IsGearUsable: %s - Can equip weapon type and tooltip class check passed, returning true", itemName))
        end
        return true
    end
    if GreedyLoot.db.profile.debugMode then
        local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
        GreedyLoot:Print(string.format("→ GL_IsGearUsable: %s - Not weapon or armor, returning false", itemName))
    end
    return false
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
            if GreedyLoot.db.profile.debugMode then
                GreedyLoot:Print("GroupLootFrame shown - checking for auto-greed")
            end
            
            -- Use a small delay to ensure the frame is fully loaded
            C_Timer.After(0.1, function()
                GL_CheckForAutoGreed()
            end)
        end)
    else
        -- If GroupLootFrame doesn't exist yet, try to hook it later
        if GreedyLoot.db.profile.debugMode then
            GreedyLoot:Print("GroupLootFrame not found, will retry later")
        end
        
        -- Try to hook it again after a short delay
        C_Timer.After(1.0, function()
            if GroupLootFrame then
                GroupLootFrame:HookScript("OnShow", function()
                    if GreedyLoot.db.profile.debugMode then
                        GreedyLoot:Print("GroupLootFrame shown - checking for auto-greed")
                    end
                    
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
    -- Get the current roll ID from the frame
    local rollId = GroupLootFrame.rollId
    if not rollId then
        return
    end
    
    -- Call the ShouldAutoGreed function to get the decision
    local shouldGreed = GL_ShouldAutoGreed(rollId)
    
    -- Get canGreed from the loot roll info
    local name, texture, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant = GetLootRollItemInfo(rollId)
    
    -- Debug the decision values
    if GreedyLoot.db.profile.debugMode then
        GreedyLoot:Print(string.format("CheckForAutoGreed - shouldGreed: %s, canGreed: %s", 
            shouldGreed and "Yes" or "No", 
            canGreed and "Yes" or "No"))
    end

    -- Auto-greed if requirements are met and greed is available
    local itemLink = select(2, GetLootRollItemInfo(rollId))
    local itemClassID = select(6, GetItemInfoInstant(itemLink))
    if shouldGreed and canGreed then
        if GreedyLoot.db.profile.debugMode and (itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON or itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR) then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown"
            GreedyLoot:Print(string.format("→ Executing auto-greed on: %s", itemName))
        end
        ConfirmLootRoll(rollId, GreedyLoot.Constants.ROLL_TYPE.GREED)
    elseif not shouldGreed then
        if GreedyLoot.db.profile.debugMode and (itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON or itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR) then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown"
            GreedyLoot:Print(string.format("→ Not auto-greeding: %s", itemName))
        end
    elseif shouldGreed and not canGreed then
        if GreedyLoot.db.profile.debugMode and (itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON or itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR) then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown"
            GreedyLoot:Print(string.format("→ Not auto-greeding: Cannot greed on this item (%s)", itemName))
        end
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
    GreedyLoot:Print("Version " .. GreedyLoot.version)
    
    -- Register events for loot roll handling
    GreedyLoot:RegisterEvent("CONFIRM_LOOT_ROLL", "CONFIRM_ROLL")
    GreedyLoot:RegisterEvent("START_LOOT_ROLL", "START_LOOT_ROLL")
    
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
local function GL_ShouldPass(itemLink, itemClassID, isUsable, isRecipe, isLearned, isBoP, hasVendorValue)
    local db = GreedyLoot.db.profile
    
    -- Always skip battle pets and miscellaneous items (which can include unlearned pets)
    if itemClassID == GreedyLoot.Constants.ITEM_CLASS.BATTLE_PET or itemClassID == 15 then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Battle Pet"
            GreedyLoot:Print(string.format("→ GL_ShouldPass: Skipping battle pet/misc item: %s (battle pets and misc items are always skipped)", itemName))
        end
        return false
    end
    
    -- Debug: Print initial conditions
    if GreedyLoot.db.profile.debugMode then
        local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
        GreedyLoot:Print(string.format("→ GL_ShouldPass: %s - autoPassNoVendorPrice: %s, isUsable: %s, isRecipe: %s, isLearned: %s, isBoP: %s, hasVendorValue: %s", 
            itemName, 
            db.autoPassNoVendorPrice and "true" or "false",
            isUsable and "true" or "false",
            isRecipe and "true" or "false", 
            isLearned and "true" or "false",
            isBoP and "true" or "false",
            hasVendorValue and "true" or "false"))
    end
    
    -- If auto-pass is disabled, never pass
    if not db.autoPassNoVendorPrice then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldPass: %s - autoPassNoVendorPrice is disabled, returning false", itemName))
        end
        return false
    end
    
    -- Don't pass if it's usable gear
    if db.autoPassExceptUsableGear and isUsable then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldPass: %s - autoPassExceptUsableGear enabled and item is usable, returning false", itemName))
        end
        return false
    end
    
    -- Don't pass if item has vendor value
    if hasVendorValue then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldPass: %s - item has vendor value, returning false", itemName))
        end
        return false
    end
    
    -- At this point, item has no vendor value and auto-pass is enabled
    -- Check exceptions for items with no vendor value
    
    -- Don't pass if it's non-BoP and is not a recipe
    if db.autoPassExceptNonBoP and not isBoP and isRecipe then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldPass: %s - autoPassExceptNonBoP enabled and item is not BoP, returning false", itemName))
        end
        return false
    end
    
    -- Don't pass if it's an unlearned recipe
    if db.autoPassExceptUnlearned and isRecipe and not isLearned then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldPass: %s - autoPassExceptUnlearned enabled and item is unlearned recipe, returning false", itemName))
        end
        return false
    end
    
    -- All conditions met for auto-pass
    if GreedyLoot.db.profile.debugMode then
        local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
        GreedyLoot:Print(string.format("→ GL_ShouldPass: %s - all conditions met for auto-pass, returning true", itemName))
    end
    return true
end

-- Returns true if the gear should be greeded
local function GL_ShouldGreedGear(itemLink, itemClassID, quality, isUsable, isBoP, hasVendorValue, isTransmogCollected)
    local db = GreedyLoot.db.profile
    
    -- Debug: Print initial conditions
    if GreedyLoot.db.profile.debugMode then
        local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
        GreedyLoot:Print(string.format("→ GL_ShouldGreedGear: %s - itemClassID: %s, quality: %s, isUsable: %s, isBoP: %s, hasVendorValue: %s, isTransmogCollected: %s", 
            itemName, 
            itemClassID,
            quality,
            isUsable and "true" or "false",
            isBoP and "true" or "false",
            hasVendorValue and "true" or "false",
            isTransmogCollected and "true" or "false"))
    end
    
    -- Check weapon settings
    if itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON then
        if not db.autoGreedWeapons then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_ShouldGreedGear: %s - autoGreedWeapons disabled, returning false", itemName))
            end
            return false
        end
        if quality > db.autoGreedWeaponsMaxQuality then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_ShouldGreedGear: %s - quality %s exceeds max %s for weapons, returning false", itemName, quality, db.autoGreedWeaponsMaxQuality))
            end
            return false
        end
    -- Check armor settings
    elseif itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR then
        if not db.autoGreedArmor then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_ShouldGreedGear: %s - autoGreedArmor disabled, returning false", itemName))
            end
            return false
        end
        if quality > db.autoGreedArmorMaxQuality then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_ShouldGreedGear: %s - quality %s exceeds max %s for armor, returning false", itemName, quality, db.autoGreedArmorMaxQuality))
            end
            return false
        end
    else
        -- Not a weapon or armor
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldGreedGear: %s - not weapon or armor (itemClassID: %s), returning false", itemName, itemClassID))
        end
        return false
    end
    
    -- Check exceptions
    if db.autoGreedGearExceptBoP and not isBoP then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldGreedGear: %s - autoGreedGearExceptBoP enabled and item is not BoP, returning false", itemName))
        end
        return false
    end
    
    if db.autoGreedGearExceptUsable and isUsable then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldGreedGear: %s - autoGreedGearExceptUsable enabled and item is usable, returning false", itemName))
        end
        return false
    end
    
    if db.autoGreedGearExceptNoVendorPrice and not hasVendorValue then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldGreedGear: %s - autoGreedGearExceptNoVendorPrice enabled and item has no vendor value, returning false", itemName))
        end
        return false
    end
    
    if db.autoGreedGearExceptTransmog and isUsable and not isTransmogCollected then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldGreedGear: %s - autoGreedGearExceptTransmog enabled and item is usable but not collected, returning false", itemName))
        end
        return false
    end
    
    -- All conditions met for auto-greed gear
    if GreedyLoot.db.profile.debugMode then
        local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
        GreedyLoot:Print(string.format("→ GL_ShouldGreedGear: %s - all conditions met for auto-greed gear, returning true", itemName))
    end
    return true
end

-- Returns true if the other item should be greeded
local function GL_ShouldGreedOther(itemLink, itemClassID, quality, isUsable, isRecipe, isLearned, hasVendorValue, isTransmogCollected)
    local db = GreedyLoot.db.profile
    
    -- Always skip battle pets and miscellaneous items (which can include unlearned pets)
    if itemClassID == GreedyLoot.Constants.ITEM_CLASS.BATTLE_PET or itemClassID == 15 then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Battle Pet"
            GreedyLoot:Print(string.format("→ GL_ShouldGreedOther: Skipping battle pet/misc item: %s (battle pets and misc items are always skipped)", itemName))
        end
        return false
    end
    
    -- Debug: Print initial conditions
    if GreedyLoot.db.profile.debugMode then
        local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
        GreedyLoot:Print(string.format("→ GL_ShouldGreedOther: %s - itemClassID: %s, quality: %s, isUsable: %s, isRecipe: %s, isLearned: %s, hasVendorValue: %s, isTransmogCollected: %s", 
            itemName, 
            itemClassID,
            quality,
            isUsable and "true" or "false",
            isRecipe and "true" or "false",
            isLearned and "true" or "false",
            hasVendorValue and "true" or "false",
            isTransmogCollected and "true" or "false"))
    end
    
    -- Check recipe settings
    if itemClassID == GreedyLoot.Constants.ITEM_CLASS.RECIPE then
        if not db.autoGreedRecipes then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_ShouldGreedOther: %s - autoGreedRecipes disabled, returning false", itemName))
            end
            return false
        end
        if quality > db.autoGreedRecipesMaxQuality then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_ShouldGreedOther: %s - quality %s exceeds max %s for recipes, returning false", itemName, quality, db.autoGreedRecipesMaxQuality))
            end
            return false
        end
    -- Check other items settings
    else
        if not db.autoGreedOther then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_ShouldGreedOther: %s - autoGreedOther disabled, returning false", itemName))
            end
            return false
        end
        if quality > db.autoGreedOtherMaxQuality then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_ShouldGreedOther: %s - quality %s exceeds max %s for other items, returning false", itemName, quality, db.autoGreedOtherMaxQuality))
            end
            return false
        end
    end
    
    -- Check exceptions
    if db.autoGreedOtherExceptNoVendorPrice and not hasVendorValue then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldGreedOther: %s - autoGreedOtherExceptNoVendorPrice enabled and item has no vendor value, returning false", itemName))
        end
        return false
    end
    
    if db.autoGreedOtherExceptUsableGear and isUsable then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldGreedOther: %s - autoGreedOtherExceptUsableGear enabled and item is usable gear, returning false", itemName))
        end
        return false
    end
    
    if db.autoGreedOtherExceptTransmog and isUsable and not isTransmogCollected then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldGreedOther: %s - autoGreedOtherExceptTransmog enabled and item is usable but not collected, returning false", itemName))
        end
        return false
    end
    
    if db.autoGreedOtherExceptUnlearned and isRecipe and not isLearned then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldGreedOther: %s - autoGreedOtherExceptUnlearned enabled and item is unlearned recipe, returning false", itemName))
        end
        return false
    end
    
    -- All conditions met for auto-greed other
    if GreedyLoot.db.profile.debugMode then
        local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
        GreedyLoot:Print(string.format("→ GL_ShouldGreedOther: %s - all conditions met for auto-greed other, returning true", itemName))
    end
    return true
end



-- Main decision function for auto-greed
local function GL_ShouldAutoGreed(rollId)
    local name, texture, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant = GetLootRollItemInfo(rollId)
    local itemLink = GetLootRollItemLink(rollId)
    local itemInfo = {GetItemInfo(itemLink)}
    local itemClassID = itemInfo[12]
    local isRecipe = (itemClassID == GreedyLoot.Constants.ITEM_CLASS.RECIPE)
    local isUsable = GL_IsGearUsable(itemLink)
    local isLearned = isRecipe and GL_IsRecipeLearned(itemLink)
    local isBoP = bindOnPickUp
    local hasVendorValue = GL_HasVendorValue(itemLink)
    local isTransmogCollected = GL_IsItemCollectedForTransmog(itemLink)

    -- Debug: Print initial item info
    if GreedyLoot.db.profile.debugMode then
        local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
        GreedyLoot:Print(string.format("→ GL_ShouldAutoGreed: %s - Starting decision process", itemName))
        GreedyLoot:Print(string.format("→ GL_ShouldAutoGreed: %s - itemClassID: %s, quality: %s, isBoP: %s, hasVendorValue: %s", 
            itemName, itemClassID, quality, isBoP and "true" or "false", hasVendorValue and "true" or "false"))
    end

    -- Always skip battle pets and miscellaneous items (which can include unlearned pets)
    if itemClassID == GreedyLoot.Constants.ITEM_CLASS.BATTLE_PET or itemClassID == 15 then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Battle Pet"
            GreedyLoot:Print(string.format("→ GL_ShouldAutoGreed: Skipping battle pet/misc item: %s (battle pets and misc items are always skipped)", itemName))
        end
        return false
    end

    -- Check if we should pass
    local shouldPass = GL_ShouldPass(itemLink, itemClassID, isUsable, isRecipe, isLearned, isBoP, hasVendorValue)
    if shouldPass then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldAutoGreed: %s - Should pass, returning false (don't greed)", itemName))
        end
        return false
    end

    -- Check if we should greed gear
    if itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON or itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR then
        local shouldGreedGear = GL_ShouldGreedGear(itemLink, itemClassID, quality, isUsable, isBoP, hasVendorValue, isTransmogCollected)
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_ShouldAutoGreed: %s - Gear decision: %s", itemName, shouldGreedGear and "greed" or "no greed"))
        end
        return shouldGreedGear
    end

    -- Check if we should greed other items
    local shouldGreedOther = GL_ShouldGreedOther(itemLink, itemClassID, quality, isUsable, isRecipe, isLearned, hasVendorValue, isTransmogCollected)
    if GreedyLoot.db.profile.debugMode then
        local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
        GreedyLoot:Print(string.format("→ GL_ShouldAutoGreed: %s - Other decision: %s", itemName, shouldGreedOther and "greed" or "no greed"))
    end
    return shouldGreedOther
end

-- Main roll handler
local function GL_HandleLootRoll(rollId)
    local name, texture, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant = GetLootRollItemInfo(rollId)
    local itemLink = GetLootRollItemLink(rollId)
    local itemInfo = {GetItemInfo(itemLink)}
    local itemClassID = itemInfo[12]
    local isRecipe = (itemClassID == GreedyLoot.Constants.ITEM_CLASS.RECIPE)
    local isUsable = GL_IsGearUsable(itemLink)
    local isLearned = isRecipe and GL_IsRecipeLearned(itemLink)
    local isBoP = bindOnPickUp
    local hasVendorValue = GL_HasVendorValue(itemLink)
    local isTransmogCollected = GL_IsItemCollectedForTransmog(itemLink)

    -- Debug: Print initial item info
    if GreedyLoot.db.profile.debugMode then
        local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
        GreedyLoot:Print(string.format("→ GL_HandleLootRoll: %s - Starting roll handler", itemName))
        GreedyLoot:Print(string.format("→ GL_HandleLootRoll: %s - itemClassID: %s, quality: %s, isBoP: %s, hasVendorValue: %s", 
            itemName, itemClassID, quality, isBoP and "true" or "false", hasVendorValue and "true" or "false"))
    end

    if GL_ShouldPass(itemLink, itemClassID, isUsable, isRecipe, isLearned, isBoP, hasVendorValue) then
        if GreedyLoot.db.profile.debugMode then
            local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
            GreedyLoot:Print(string.format("→ GL_HandleLootRoll: %s - Executing auto-pass", itemName))
        end
        ConfirmLootRoll(rollId, GreedyLoot.Constants.ROLL_TYPE.PASS)
        return
    end

    if itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON or itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR then
        if GL_ShouldGreedGear(itemLink, itemClassID, quality, isUsable, isBoP, hasVendorValue, isTransmogCollected) then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_HandleLootRoll: %s - Executing auto-greed (gear)", itemName))
            end
            ConfirmLootRoll(rollId, GreedyLoot.Constants.ROLL_TYPE.GREED)
            return
        end
    else
        if GL_ShouldGreedOther(itemLink, itemClassID, quality, isUsable, isRecipe, isLearned, hasVendorValue, isTransmogCollected) then
            if GreedyLoot.db.profile.debugMode then
                local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
                GreedyLoot:Print(string.format("→ GL_HandleLootRoll: %s - Executing auto-greed (other)", itemName))
            end
            ConfirmLootRoll(rollId, GreedyLoot.Constants.ROLL_TYPE.GREED)
            return
        end
    end
    if GreedyLoot.db.profile.debugMode then
        local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
        GreedyLoot:Print(string.format("→ GL_HandleLootRoll: %s - No auto-pass or auto-greed action taken", itemName))
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
    if GreedyLoot.db.profile.debugMode then
        GreedyLoot:Print(string.format("START_LOOT_ROLL event fired - rollId: %s, rollTime: %s", rollId, rollTime))
    end
    GL_HandleLootRoll(rollId)
end
