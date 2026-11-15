--[[--
Benutzer wechseln: alle Benutzer mit Server, der angemeldete mit Haken. Ein Tippen wechselt, ohne
gemerktes Passwort erst nach der Eingabe. Darunter Benutzer hinzufügen und verwalten.
]]

local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local users = require("grimmoryui/users")
local UI = require("grimmoryui/ui")
local _ = require("grimmoryui/i18n")
local N_, T = _.ngettext, _.T

local UserList = InputContainer:extend{
    name = "grimmory_users",
    plugin = nil,
    covers_fullscreen = true,
}

local function innerWidth() return UI.width() - 2 * UI.px(48) end

--- Kreis, Name und darunter „Benutzername · Server“. `details`: auch die Zahl der Header.
function UserList.entry(p, u, size, active, details, max_w)
    local sub = {}
    local function add(s) if s and s ~= "" then table.insert(sub, s) end end
    add(u.username)
    add(users.host(u.server))
    local n = #(u.headers or {})
    if details and n > 0 then add(T(N_("%1 Header", "%1 Header", n), n)) end
    if u.remember == false or not p:hasPassword(u) then add(_("Passwort wird abgefragt")) end
    local text_w = (max_w or innerWidth()) - UI.px(size + 28)
    return HorizontalGroup:new{ align = "center",
        UI.avatar(users.initial(u), size, active), UI.hspan(28),
        VerticalGroup:new{ align = "left",
            UI.text(users.label(u), size >= 72 and 30 or 26, { bold = true, max_width = text_w }),
            UI.text(table.concat(sub, " · "), 22, { color = UI.GRAY, max_width = text_w }) } }
end

--- „Benutzer hinzufügen“ mit dem Hinweis auf die Vorlage.
function UserList.addEntry(p, size)
    local current = p:user()
    local text_w = innerWidth() - UI.px(size + 28)
    return HorizontalGroup:new{ align = "center",
        UI.CenterContainer:new{ dimen = Geom:new{ w = UI.px(size), h = UI.px(size) }, UI.icon("plus", 36) }, UI.hspan(28),
        VerticalGroup:new{ align = "left",
            UI.text(_("Benutzer hinzufügen"), 28, { bold = true, max_width = text_w }),
            current and UI.text(T(_("Adresse und Header von %1 als Vorlage"), users.label(current)), 22,
                { color = UI.GRAY, max_width = text_w }) or UI.vspan(0) } }
end

function UserList:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = UI.width(), h = UI.height() }
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    self:render()
end

-- ponytail: keine Seiten, auf dem Kindle passen etwa neun Benutzer. Blättern wie in Picker, wenn mehr nötig sind.
function UserList:render()
    local p = self.plugin
    local parts = { align = "left", UI.header{ back = _("Benutzer"), on_back = function() self:close() end } }
    for _, u in ipairs(p:users()) do
        local active = p:isActive(u)
        table.insert(parts, UI.row(UserList.entry(p, u, 72, active, false, innerWidth() - UI.px(60)),
            active and UI.icon("check", 36) or nil, function() self:pick(u) end, 128))
    end
    table.insert(parts, UI.vspan(32))
    table.insert(parts, UI.line(UI.width(), UI.px(2)))
    table.insert(parts, UI.row(UserList.addEntry(p, 72), nil, function()
        self:close()
        p:showUserEditor(p:addUser(), nil, true)
    end, 104))
    table.insert(parts, UI.row(HorizontalGroup:new{ align = "center",
        UI.CenterContainer:new{ dimen = Geom:new{ w = UI.px(72), h = UI.px(72) }, UI.icon("appbar.settings", 36) },
        UI.hspan(28), UI.text(_("Benutzer verwalten"), 28, { bold = true }) },
        UI.icon("chevron.right", 32), function()
            self:close()
            p:showSettings()
        end, 104))
    if self[1] then self[1]:free() end
    self[1] = FrameContainer:new{
        bordersize = 0, padding = 0, margin = 0, background = UI.WHITE, width = UI.width(), height = UI.height(),
        VerticalGroup:new(parts),
    }
    UIManager:setDirty(self, "ui")
end

function UserList:pick(u)
    self:close()
    self.plugin:switchUser(u)
end

function UserList:close()
    UIManager:close(self, "ui")
end

function UserList:onClose()
    self:close()
    return true
end

return UserList
