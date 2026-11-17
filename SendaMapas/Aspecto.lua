-- Aspecto (skin) engine. Skins.lua holds the data (colors per role, frame style, row structure, info
-- style) of every look; this file applies one: it copies its colors into ns.palette IN PLACE (so every
-- reference stays valid), recolors the widgets that registered themselves, repaints the panel surfaces
-- and draws the frame decoration. Switching is live, no reload.
local _, ns = ...
local Skins = ns.Skins

-- ns.palette: role -> {r, g, b, a}. Filled from the default skin so it exists before the saved
-- variables are read; ApplySkin() refreshes it.
local palette = {}
ns.palette = palette
for role, color in pairs(Skins.list[Skins.default].c) do palette[role] = {color[1], color[2], color[3], color[4]} end

palette.buttonSub = {0.5, 0.5, 0.5, 1}      -- small gray text inside buttons (the default "disabled" font color)
ns.skinKey = Skins.default
local tinted, tintedTextures, skinFrames = {}, {}, {}

function ns:SkinData(key)
    return Skins.list[key or self.skinKey] or Skins.list[Skins.default]
end

-- |cffRRGGBB..|r for a role of the current skin.
function ns.Esc(role, text)
    local c = palette[role] or palette.instruction
    return string.format("|cff%02x%02x%02x%s|r", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5), text)
end

-- Text color that follows the skin.
function ns.Tint(fontString, role)
    local c = palette[role]
    fontString:SetTextColor(c[1], c[2], c[3], 1)
    tinted[#tinted + 1] = {fontString, role}
end

-- Flat-color texture that follows the skin (alpha = alpha of the role unless given).
function ns.TintTexture(texture, role, alpha)
    local c = palette[role]
    texture:SetColorTexture(c[1], c[2], c[3], alpha or c[4])
    tintedTextures[#tintedTextures + 1] = {texture, role, alpha}
end

-- A window with a backdrop that follows the skin, with the frame decoration of the skin.
-- decorOnly: the colors are painted elsewhere (HUD surfaces), only the decoration is managed here.
-- fixedAlpha: use the alpha of the skin color, ignore the panel opacity setting.
local applyFrame
function ns.SkinFrame(frame, backRole, borderRole, decorOnly, fixedAlpha)
    local entry = {frame = frame, back = backRole, border = borderRole, decorOnly = decorOnly, fixedAlpha = fixedAlpha}
    skinFrames[#skinFrames + 1] = entry
    applyFrame(entry, Skins.list[ns.skinKey])
    return frame
end

-- ------------------------------------------------------------------------------ decoration
local CORNER, ARM = 2, 11

local function decor(frame)
    local d = rawget(frame, "skinDecor")
    if d then return d end
    d = {corners = {}, inner = {}}
    for index = 1, 8 do
        local t = frame:CreateTexture(nil, "OVERLAY")
        d.corners[index] = t
    end
    for index = 1, 4 do d.inner[index] = frame:CreateTexture(nil, "OVERLAY") end
    rawset(frame, "skinDecor", d)
    return d
end

local function placeDecor(frame, d)
    local c = d.corners
    -- horizontal and vertical arm at each of the four corners
    local specs = {
        {"TOPLEFT", 0, 0, ARM, CORNER}, {"TOPLEFT", 0, 0, CORNER, ARM},
        {"TOPRIGHT", 0, 0, ARM, CORNER}, {"TOPRIGHT", 0, 0, CORNER, ARM},
        {"BOTTOMLEFT", 0, 0, ARM, CORNER}, {"BOTTOMLEFT", 0, 0, CORNER, ARM},
        {"BOTTOMRIGHT", 0, 0, ARM, CORNER}, {"BOTTOMRIGHT", 0, 0, CORNER, ARM},
    }
    for index, spec in ipairs(specs) do
        c[index]:ClearAllPoints()
        c[index]:SetPoint(spec[1], frame, spec[1], spec[2], spec[3])
        c[index]:SetSize(spec[4], spec[5])
    end
    local inner = d.inner
    local inset = 4
    inner[1]:ClearAllPoints(); inner[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    inner[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset); inner[1]:SetHeight(1)
    inner[2]:ClearAllPoints(); inner[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
    inner[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset); inner[2]:SetHeight(1)
    inner[3]:ClearAllPoints(); inner[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    inner[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset); inner[3]:SetWidth(1)
    inner[4]:ClearAllPoints(); inner[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
    inner[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset); inner[4]:SetWidth(1)
end

applyFrame = function(entry, skin)
    local frame = entry.frame
    local backColor, borderColor = palette[entry.back], palette[entry.border]
    if frame.SetBackdrop and not entry.decorOnly then
        local opacity = not entry.fixedAlpha and ns.saved and type(ns.saved.backgroundOpacity) == "number" and ns.saved.backgroundOpacity / 100
        frame:SetBackdropColor(backColor[1], backColor[2], backColor[3], opacity or backColor[4])
        frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], skin.frame == "none" and 0 or borderColor[4])
    end
    local d = decor(frame)
    placeDecor(frame, d)
    local accent = palette.accent
    for _, t in ipairs(d.corners) do
        t:SetColorTexture(accent[1], accent[2], accent[3], 1)
        t:SetShown(skin.frame == "corners")
    end
    for _, t in ipairs(d.inner) do
        t:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], 1)
        t:SetShown(skin.frame == "double")
    end
end

-- A skin may bring colors of its own for its buttons (Skins.lua `buttonOverrides`, data of the generator).
-- Today only Táctico does: solid turquoise buttons with navy text, because pale text on turquoise is hard to
-- read. Only the roles listed there change; the panel is untouched. HUD.lua keeps the fills the skin lists in
-- `ownAlpha` at their own alpha instead of the panel opacity. Nothing here knows the name of a skin.

-- ------------------------------------------------------------------------------ applying a skin
function ns:ApplySkin(quiet)
    local key = self.saved and self.saved.skin
    if not Skins.list[key] then key = Skins.default end
    self.skinKey = key
    local skin = Skins.list[key]
    for role, color in pairs(skin.c) do
        local target = palette[role]
        if not target then target = {}; palette[role] = target end
        target[1], target[2], target[3], target[4] = color[1], color[2], color[3], color[4]
    end
    local sub = palette.buttonSub
    sub[1], sub[2], sub[3], sub[4] = 0.5, 0.5, 0.5, 1
    for role, color in pairs(skin.buttonOverrides or {}) do
        local target = palette[role]
        if not target then target = {}; palette[role] = target end
        target[1], target[2], target[3], target[4] = color[1], color[2], color[3], color[4]
    end
    for _, entry in ipairs(tinted) do
        local c = palette[entry[2]]
        entry[1]:SetTextColor(c[1], c[2], c[3], 1)
    end
    for _, entry in ipairs(tintedTextures) do
        local c = palette[entry[2]]
        entry[1]:SetColorTexture(c[1], c[2], c[3], entry[3] or c[4])
    end
    for _, entry in ipairs(skinFrames) do applyFrame(entry, skin) end
    if self.RepaintSurfaces then self:RepaintSurfaces() end
    if self.RenderHUD and self.frame then self:RenderHUD() end
    if self.RenderMapPicker and self.mapPicker then self:RenderMapPicker() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:SetSkin(key, quiet)
    if not Skins.list[key] then
        self:Print("Aspectos: " .. table.concat(Skins.order, ", ") .. ".")
        return false
    end
    self.saved.skin = key
    self:ApplySkin()
    if not quiet then self:Print("Aspecto: " .. Skins.list[key].name .. ".") end
    return true
end
