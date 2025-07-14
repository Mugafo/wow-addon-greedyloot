-- GreedyDebug.lua
-- Debug window system for Greedy Loot addon

local GreedyDebug = {}
GreedyLoot.Debug = GreedyDebug

-- Debug data structure to store loot decisions
GreedyDebug.lootHistory = {}
GreedyDebug.maxHistorySize = 20
GreedyDebug.rowFrames = {} -- Store references to row frames for cleanup

-- Quality color codes and text for display
local QUALITY_COLORS = {
    [1] = "|cffffffff", -- Common
    [2] = "|cff1eff00", -- Uncommon
    [3] = "|cff0070dd", -- Rare
    [4] = "|cffa335ee", -- Epic
    [5] = "|cffff8000", -- Legendary
}

local QUALITY_TEXT = {
    [1] = "Common",
    [2] = "Uncommon", 
    [3] = "Rare",
    [4] = "Epic",
    [5] = "Legendary",
}

-- Class color codes for display
local CLASS_COLORS = {
    ["Death Knight"] = "|cffc41f3b",
    ["Druid"] = "|cffff7d0a",
    ["Hunter"] = "|cffabd473",
    ["Mage"] = "|cff69ccf0",
    ["Monk"] = "|cff00ff96",
    ["Paladin"] = "|cfff58cba",
    ["Priest"] = "|cffffffff",
    ["Rogue"] = "|cfffff569",
    ["Shaman"] = "|cff0070de",
    ["Warlock"] = "|cff9482c9",
    ["Warrior"] = "|cffc79c6e",
}

-- Action result strings with updated colors
local ACTION_STRINGS = {
    PASS = "|cff0080ffPASS|r", -- Blue
    GREED = "|cff00ff00GREED|r", -- Green
    NO_ACTION = "|cffffffffNO ACTION|r", -- White
}

-- Column definitions with updated positions
local COLUMNS = {
    {name = "ItemName", x = 5, width = 200},
    {name = "ItemID", x = 205, width = 50},
    {name = "ItemType", x = 255, width = 60},
    {name = "Class", x = 315, width = 80},
    {name = "Usable", x = 395, width = 60},
    {name = "Recipe", x = 455, width = 60},
    {name = "Learned", x = 515, width = 60},
    {name = "BoP", x = 575, width = 50},
    {name = "Vendor", x = 625, width = 55},
    {name = "Transmog", x = 680, width = 80},
    {name = "Action", x = 760, width = 75},
    {name = "Delete", x = 835, width = 14},
}

-- Create a data row frame
function GreedyDebug:CreateDataRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(20)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * 20)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(index - 1) * 20)
    
    -- Create background texture for alternating rows with lighter colors
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if index % 2 == 0 then
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.4) -- Lighter dark
    else
        bg:SetColorTexture(0.25, 0.25, 0.25, 0.4) -- Lighter light
    end
    row.bg = bg
    
    -- Create column text elements
    row.columns = {}
    for i, col in ipairs(COLUMNS) do
        if col.name == "Delete" then
            -- Create trash icon button for delete column
            local deleteButton = CreateFrame("Button", nil, row)
            deleteButton:SetSize(14, 14)
            deleteButton:SetPoint("TOPLEFT", row, "TOPLEFT", col.x - 2, -3)
            
            -- Set trash icon texture
            local icon = deleteButton:CreateTexture(nil, "OVERLAY")
            icon:SetAllPoints()
            icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            icon:SetTexCoord(0, 1, 0, 1)
            deleteButton.icon = icon
            
            -- Set button scripts
            deleteButton:SetScript("OnClick", function(self)
                GreedyDebug:DeleteHistoryEntry(index)
            end)
            deleteButton:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Delete this entry")
                GameTooltip:Show()
            end)
            deleteButton:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
            end)
            
            row.columns[i] = deleteButton
        else
            local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", row, "LEFT", col.x, 0) -- Center vertically by using LEFT anchor
            text:SetWidth(col.width)
            text:SetHeight(20) -- Set height to match row height
            text:SetJustifyH("LEFT")
            text:SetJustifyV("MIDDLE") -- Center text vertically
            row.columns[i] = text
        end
    end
    
    return row
end

-- Get item class requirement
local function GetItemClassRequirement(itemLink)
    if not itemLink then return "-" end
    
    -- Create a temporary tooltip to scan for class restrictions
    local tooltip = CreateFrame("GameTooltip", "GLDebugClassCheckTooltip", nil, "GameTooltipTemplate")
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:SetHyperlink(itemLink)
    
    local classRestriction = nil
    
    -- Scan tooltip lines for class restrictions
    for i = 2, tooltip:NumLines() do
        local line = _G["GLDebugClassCheckTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text:find("^Classes:") then
                -- Extract class names from the "Classes: Priest, Mage" format
                -- Remove "Classes:" prefix and split by comma
                local classList = text:gsub("^Classes:%s*", "")
                local classes = {}
                for class in classList:gmatch("[^,]+") do
                    class = class:match("^%s*(.-)%s*$") -- trim whitespace
                    if class and class ~= "" then
                        table.insert(classes, class)
                    end
                end
                if #classes > 0 then
                    classRestriction = table.concat(classes, ", ")
                end
                break
            end
        end
    end
    
    tooltip:Hide()
    
    -- If no class restriction found in tooltip, return "-"
    return classRestriction or "-"
end

-- Show add item dialog
function GreedyDebug:ShowAddItemDialog()
    StaticPopup_Show("GREEDY_DEBUG_ADD_ITEM")
end

-- Register StaticPopup for add item dialog
StaticPopupDialogs["GREEDY_DEBUG_ADD_ITEM"] = {
    text = "Enter Item ID:",
    button1 = "Add",
    button2 = "Cancel",
    hasEditBox = true,
    editBoxWidth = 200,
    OnAccept = function(self)
        local itemID = tonumber(self.editBox:GetText())
        if itemID then
            GreedyDebug:AddTestItem(itemID)
        else
            GreedyLoot:Print("Invalid item ID. Please enter a number.")
        end
    end,
    OnShow = function(self)
        self.editBox:SetText("")
        self.editBox:SetFocus()
    end,
    OnHide = function(self)
        self.editBox:ClearFocus()
    end,
    EditBoxOnEnterPressed = function(self)
        local itemID = tonumber(self:GetText())
        if itemID then
            GreedyDebug:AddTestItem(itemID)
            self:GetParent():Hide()
        else
            GreedyLoot:Print("Invalid item ID. Please enter a number.")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Initialize the debug window
function GreedyDebug:Initialize()
    if not GreedyDebugFrame then
        return
    end
    
    -- Set up the frame
    local frame = GreedyDebugFrame
    
    -- Set backdrop for MoP Classic compatibility
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.95)
    
    frame.title = _G[frame:GetName() .. "Title"]
    frame.title:SetText("Greedy Loot Debug Window")
    frame.title:SetTextColor(1, 1, 1)
    
    -- Set up close button
    frame.closeButton = _G[frame:GetName() .. "CloseButton"]
    frame.closeButton:SetScript("OnClick", function() frame:Hide() end)
    
    -- Set up clear button
    frame.clearButton = _G[frame:GetName() .. "ClearButton"]
    frame.clearButton:SetText("Clear")
    frame.clearButton:SetScript("OnClick", function() 
        GreedyLoot.Debug:ClearHistory()
    end)
    
    -- Set up add item button
    frame.addItemButton = _G[frame:GetName() .. "AddItemButton"]
    frame.addItemButton:SetText("Add Item")
    frame.addItemButton:SetScript("OnClick", function() 
        GreedyDebug:ShowAddItemDialog()
    end)
    
    -- Set up gear button to open options
    frame.gearButton = _G[frame:GetName() .. "GearButton"]
    frame.gearButton:SetScript("OnClick", function(self)
        GreedyDebug:OpenOptions()
    end)
    frame.gearButton:SetScript("OnEnter", function(self)
        GreedyDebug:ShowOptionsTooltip(self)
    end)
    frame.gearButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Set button textures programmatically for Classic compatibility
    frame.gearButton:SetNormalTexture("Interface/Buttons/UI-OptionsButton")
    
    -- Get content frame
    frame.contentFrame = _G[frame:GetName() .. "TableContainerContentFrame"]
    
    -- Set up header text wrapping to prevent overlapping
    local header = _G[frame:GetName() .. "TableContainerHeader"]
    if header then
        -- Set up each header text element with proper width and wrapping
        local headerTexts = {
            {name = "ItemName", width = 200},
            {name = "ItemID", width = 50},
            {name = "ItemType", width = 60},
            {name = "Class", width = 80},
            {name = "Usable", width = 60},
            {name = "Recipe", width = 60},
            {name = "Learned", width = 60},
            {name = "BoP", width = 50},
            {name = "Vendor", width = 55},
            {name = "Transmog", width = 80},
            {name = "Action", width = 75}
        }
        
        for _, textInfo in ipairs(headerTexts) do
            local textElement = _G[header:GetName() .. textInfo.name]
            if textElement then
                textElement:SetWidth(textInfo.width)
                textElement:SetJustifyH("LEFT")
                textElement:SetJustifyV("MIDDLE")
            end
        end
    end
    
    -- Store reference
    self.frame = frame
    
    -- Force the main frame and all its children to be visible
    frame:Show()
    
    -- Force all child frames to be visible
    if frame.contentFrame then
        frame.contentFrame:Show()
    end
    
    local tableContainer = _G[frame:GetName() .. "TableContainer"]
    if tableContainer then
        tableContainer:Show()
    end
    
    local scrollFrame = _G[frame:GetName() .. "TableContainerScrollFrame"]
    if scrollFrame then
        scrollFrame:Show()
    end
end

-- Local function to extract item ID from link (copied from GreedyLoot.lua)
local function GetItemIDFromLink(itemLink)
    if not itemLink then
        return nil
    end
    local itemID = select(3, strfind(itemLink, "item:(%d+)"))
    return itemID and tonumber(itemID) or nil
end

-- Add a loot decision to the history
function GreedyDebug:AddLootDecision(itemLink, itemClassID, quality, isUsable, isRecipe, isLearned, isBoP, hasVendorValue, isTransmogCollected, action, decisionData)
    local itemName = select(2, GetItemInfo(itemLink)) or "Unknown Item"
    local itemID = GetItemIDFromLink(itemLink)
    
    local entry = {
        timestamp = time(),
        itemLink = itemLink,
        itemName = itemName,
        itemID = itemID,
        itemClassID = itemClassID,
        quality = quality,
        isUsable = isUsable,
        isRecipe = isRecipe,
        isLearned = isLearned,
        isBoP = isBoP,
        hasVendorValue = hasVendorValue,
        isTransmogCollected = isTransmogCollected,
        action = action,
        decisionData = decisionData or {}
    }
    
    -- Add to beginning of history
    table.insert(self.lootHistory, 1, entry)
    
    -- Keep only the most recent entries
    if #self.lootHistory > self.maxHistorySize then
        table.remove(self.lootHistory, #self.lootHistory)
    end
    
    -- Update the display if window is open
    if self.frame and self.frame:IsShown() then
        self:UpdateDisplay()
    end
end

-- Delete a specific history entry
function GreedyDebug:DeleteHistoryEntry(index)
    if index >= 1 and index <= #self.lootHistory then
        table.remove(self.lootHistory, index)
        if self.frame and self.frame:IsShown() then
            self:UpdateDisplay()
        end
    end
end

-- Open Greedy Loot options
function GreedyDebug:OpenOptions()
    -- Use the same logic as the /gl command
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory("Greedy Loot")
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory("Greedy Loot")
    elseif InterfaceOptionsFrame then
        InterfaceOptionsFrame:Show()
        InterfaceOptionsFrame_OpenToCategory("Greedy Loot")
    end
end

-- Update the debug window display
function GreedyDebug:UpdateDisplay()
    if not self.frame or not self.frame.contentFrame then 
        return 
    end
    
    local contentFrame = self.frame.contentFrame
    
    -- Clear existing row frames
    for _, rowFrame in ipairs(self.rowFrames) do
        rowFrame:Hide()
    end
    self.rowFrames = {}
    
    -- Create row frames for each entry
    for i, entry in ipairs(self.lootHistory) do
        local rowFrame = self:CreateDataRow(contentFrame, i)
        table.insert(self.rowFrames, rowFrame)
        
        -- Set row data
        local itemTypeText = "Misc"
        
        -- Use the centralized GL_GetItemTypeText function
        itemTypeText = GreedyLoot.GL_GetItemTypeText(entry.itemClassID, entry.itemSubClassID) or "Unknown"
        
        local classRequirement = GetItemClassRequirement(entry.itemLink)
        local actionText = ACTION_STRINGS[entry.action] or "|cff888888UNKNOWN|r"
        
        -- Apply class colors to class requirement text
        local classRequirementDisplay = classRequirement
        if classRequirement and classRequirement ~= "-" then
            local coloredClasses = {}
            for class in classRequirement:gmatch("[^,]+") do
                class = class:match("^%s*(.-)%s*$") -- trim whitespace
                if CLASS_COLORS[class] then
                    table.insert(coloredClasses, CLASS_COLORS[class] .. class .. "|r")
                else
                    table.insert(coloredClasses, class)
                end
            end
            classRequirementDisplay = table.concat(coloredClasses, ", ")
        end
        
        -- Truncate long strings
        local itemName = entry.itemName
        if strlen(itemName) > 35 then
            itemName = strsub(itemName, 1, 32) .. "..."
        end
        
        -- Set column values
        rowFrame.columns[1]:SetText(entry.itemLink) -- Use item link for hoverable tooltip
        rowFrame.columns[2]:SetText(entry.itemID or "N/A") -- Item ID
        rowFrame.columns[3]:SetText(itemTypeText) -- Item Type
        rowFrame.columns[4]:SetText(classRequirementDisplay) -- Class requirement with colors
        rowFrame.columns[5]:SetText(entry.isUsable and "Yes" or "No")
        rowFrame.columns[6]:SetText(entry.isRecipe and "Yes" or "-") -- Show dash for non-recipe items
        rowFrame.columns[7]:SetText(entry.isRecipe and (entry.isLearned and "Yes" or "No") or "-") -- Show dash for non-recipe items
        rowFrame.columns[8]:SetText(entry.isBoP and "Yes" or "No")
        rowFrame.columns[9]:SetText(entry.hasVendorValue and "Yes" or "No")
        -- Transmog: show '-' if not weapon or armor
        if entry.itemClassID == GreedyLoot.Constants.ITEM_CLASS.WEAPON or entry.itemClassID == GreedyLoot.Constants.ITEM_CLASS.ARMOR then
            rowFrame.columns[10]:SetText(entry.isTransmogCollected and "Yes" or "No")
        else
            rowFrame.columns[10]:SetText("-")
        end
        rowFrame.columns[11]:SetText(actionText) -- Action column
        -- rowFrame.columns[12] is the delete button, already set up
        
        -- Make the item name column hoverable for tooltips
        rowFrame.columns[1]:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(entry.itemLink)
            GameTooltip:Show()
        end)
        rowFrame.columns[1]:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        
        rowFrame:Show()
    end
    
    -- Force the content frame to be visible
    contentFrame:Show()
    
    -- Force child frames to be visible and properly sized
    local tableContainer = _G[self.frame:GetName() .. "TableContainer"]
    if tableContainer then
        tableContainer:Show()
    end
end

-- Show the debug window
function GreedyDebug:Show()
    if not self.frame then
        self:Initialize()
    end
    
    if self.frame then
        self:UpdateDisplay()
        self.frame:Show()
    end
end

-- Hide the debug window
function GreedyDebug:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

-- Toggle the debug window
function GreedyDebug:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Clear the loot history
function GreedyDebug:ClearHistory()
    self.lootHistory = {}
    -- Clear row frames
    for _, rowFrame in ipairs(self.rowFrames) do
        rowFrame:Hide()
    end
    self.rowFrames = {}
    
    if self.frame and self.frame:IsShown() then
        self:UpdateDisplay()
    end
end

-- Get the number of entries in debug history
function GreedyDebug:GetHistoryCount()
    return #self.lootHistory
end

-- Check if debug data is available
function GreedyDebug:HasData()
    return #self.lootHistory > 0
end

-- Get formatted decision data for display
function GreedyDebug:FormatDecisionData(itemLink, itemClassID, quality, isUsable, isRecipe, isLearned, isBoP, hasVendorValue, isTransmogCollected, shouldPass, shouldGreed, maxQuality, exception)
    local decisionData = {}
    
    -- Determine pass reason
    if shouldPass then
        decisionData.passReason = "Yes"
    else
        decisionData.passReason = "No"
    end
    
    -- Determine greed reason
    if shouldGreed then
        decisionData.greedReason = "Yes"
    else
        decisionData.greedReason = "No"
    end
    
    -- Add max quality info
    if maxQuality then
        decisionData.maxQuality = tostring(maxQuality)
    else
        decisionData.maxQuality = ""
    end
    
    -- Add exception info
    if exception then
        decisionData.exception = exception
    else
        decisionData.exception = ""
    end
    
    -- Determine final result
    if shouldPass then
        decisionData.result = "PASS"
    elseif shouldGreed then
        decisionData.result = "GREED"
    else
        decisionData.result = "NO ACTION"
    end
    
    return decisionData
end

-- Test function to add a single item by ID
function GreedyDebug:AddTestItem(itemID)
    -- Get item info and create proper item link
    local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice, itemClassID, itemSubClassID, itemBindType, itemExpacID, itemSetID, itemIsCraftingReagent = GetItemInfo(itemID)
    
    -- Check if item exists
    if not itemName then  
        -- Schedule a retry after a short delay
        C_Timer.After(0.2, function()
            local retryItemName, retryItemLink = GetItemInfo(itemID)
            if retryItemName then
                GreedyDebug:AddTestItem(itemID) -- Recursive call to retry
            else
                GreedyLoot:Print("Invalid item ID: " .. itemID .. ". Item not found in game database.")
            end
        end)
        return
    end
    
    -- Get the actual item link with proper name
    itemLink = select(2, GetItemInfo(itemID))
    
    -- Use the centralized GL_GatherItemInfo function
    local itemData = GreedyLoot.GL_GatherItemInfo and GreedyLoot.GL_GatherItemInfo(itemLink)
    if not itemData then
        GreedyLoot:Print("Failed to gather item data")
        return
    end
    
    -- Use the main addon's decision functions
    local shouldPass = false
    local shouldGreed = false
    
    if GreedyLoot.GL_ShouldPass then
        shouldPass = GreedyLoot.GL_ShouldPass(itemData)
    end
    
    if GreedyLoot.GL_ShouldAutoGreed then
        shouldGreed = GreedyLoot.GL_ShouldAutoGreed(itemData)
    end
    
    -- Determine action based on main addon logic
    local action = "NO_ACTION"
    if shouldPass then
        action = "PASS"
    elseif shouldGreed then
        action = "GREED"
    end
    
    -- Format decision data
    local decisionData = self:FormatDecisionData(itemData.itemLink, itemData.itemClassID, itemData.quality, itemData.isUsable, itemData.isRecipe, itemData.isLearned, itemData.bindOnPickUp, itemData.hasVendorValue, itemData.isTransmogCollected, shouldPass, shouldGreed, nil, nil)
    
    -- Add to debug history
    self:AddLootDecision(
        itemData.itemLink,
        itemData.itemClassID,
        itemData.quality,
        itemData.isUsable,
        itemData.isRecipe,
        itemData.isLearned,
        itemData.bindOnPickUp,
        itemData.hasVendorValue,
        itemData.isTransmogCollected,
        action,
        decisionData
    )
    
    -- Show debug window if not already shown
    if not self.frame or not self.frame:IsShown() then
        self:Show()
    end
    
    -- Provide feedback
    GreedyLoot:Print("Added item " .. itemData.itemName .. " (ID: " .. itemID .. ") to debug window.")
end

-- Show options tooltip when hovering over gear icon
function GreedyDebug:ShowOptionsTooltip(button)
    if not GreedyLoot.db or not GreedyLoot.db.profile then
        return
    end
    
    local db = GreedyLoot.db.profile
    
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText("Greedy Loot Options", 1, 1, 1)
    GameTooltip:AddLine("")
    
    -- Auto-confirm settings
    GameTooltip:AddLine("Auto-Confirm Settings:", 1, 1, 0)
    GameTooltip:AddLine("  BoP Items: " .. (db.autoConfirmBoP and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("  Need Rolls: " .. (db.autoConfirmNeed and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("  Greed Rolls: " .. (db.autoConfirmGreed and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("")
    
    -- Auto-pass settings
    GameTooltip:AddLine("Auto-Pass Settings:", 1, 1, 0)
    GameTooltip:AddLine("  No Vendor Price: " .. (db.autoPassNoVendorPrice and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("  Except Usable Gear: " .. (db.autoPassExceptUsableGear and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("  Except Non-BoP: " .. (db.autoPassExceptNonBoP and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("  Except Unlearned: " .. (db.autoPassExceptUnlearned and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("")
    
    -- Auto-greed weapon settings
    GameTooltip:AddLine("Weapon Auto-Greed:", 1, 1, 0)
    GameTooltip:AddLine("  Enabled: " .. (db.autoGreedWeapons and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    local weaponQualityText = QUALITY_TEXT[db.autoGreedWeaponsMaxQuality] or "None"
    local weaponQualityColor = QUALITY_COLORS[db.autoGreedWeaponsMaxQuality] or "|cffffffff"
    GameTooltip:AddLine("  Max Quality: " .. weaponQualityColor .. weaponQualityText .. "|r", 1, 1, 1)
    GameTooltip:AddLine("  Except BoP: " .. (db.autoGreedGearExceptBoP and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("  Except Usable: " .. (db.autoGreedGearExceptUsable and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("  Except No Vendor: " .. (db.autoGreedGearExceptNoVendorPrice and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("  Except Transmog: " .. (db.autoGreedGearExceptTransmog and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("")
    
    -- Auto-greed armor settings
    GameTooltip:AddLine("Armor Auto-Greed:", 1, 1, 0)
    GameTooltip:AddLine("  Enabled: " .. (db.autoGreedArmor and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    local armorQualityText = QUALITY_TEXT[db.autoGreedArmorMaxQuality] or "None"
    local armorQualityColor = QUALITY_COLORS[db.autoGreedArmorMaxQuality] or "|cffffffff"
    GameTooltip:AddLine("  Max Quality: " .. armorQualityColor .. armorQualityText .. "|r", 1, 1, 1)
    GameTooltip:AddLine("")
    
    -- Auto-greed recipe settings
    GameTooltip:AddLine("Recipe Auto-Greed:", 1, 1, 0)
    GameTooltip:AddLine("  Enabled: " .. (db.autoGreedRecipes and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    local recipeQualityText = QUALITY_TEXT[db.autoGreedRecipesMaxQuality] or "None"
    local recipeQualityColor = QUALITY_COLORS[db.autoGreedRecipesMaxQuality] or "|cffffffff"
    GameTooltip:AddLine("  Max Quality: " .. recipeQualityColor .. recipeQualityText .. "|r", 1, 1, 1)
    GameTooltip:AddLine("")
    
    -- Auto-greed other settings
    GameTooltip:AddLine("Other Items Auto-Greed:", 1, 1, 0)
    GameTooltip:AddLine("  Enabled: " .. (db.autoGreedOther and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    local otherQualityText = QUALITY_TEXT[db.autoGreedOtherMaxQuality] or "None"
    local otherQualityColor = QUALITY_COLORS[db.autoGreedOtherMaxQuality] or "|cffffffff"
    GameTooltip:AddLine("  Max Quality: " .. otherQualityColor .. otherQualityText .. "|r", 1, 1, 1)
    GameTooltip:AddLine("  Except No Vendor: " .. (db.autoGreedOtherExceptNoVendorPrice and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("  Except Usable Gear: " .. (db.autoGreedOtherExceptUsableGear and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("  Except Transmog: " .. (db.autoGreedOtherExceptTransmog and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("  Except Unlearned: " .. (db.autoGreedOtherExceptUnlearned and "|cff00ff00ON|r" or "|cffff0000OFF|r"), 1, 1, 1)
    GameTooltip:AddLine("")
    
    GameTooltip:Show()
end 