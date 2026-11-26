--[[--
Einstellungen auf einer Seite: Benutzer, Abgleich, Formate, Bücher, Anzeige. Passt nicht alles auf
den Bildschirm, wird geblättert.

Mit `user` dieselbe Seite für einen Benutzer: Adresse und Extra-Header, Anmeldung mit
Verbindungstest, Wechseln und Entfernen.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local api = require("grimmoryui/api")
local lib = require("grimmoryui/library")
local users = require("grimmoryui/users")
local UserList = require("grimmoryui/userlist")
local UI = require("grimmoryui/ui")
local _ = require("grimmoryui/i18n")
local N_, T = _.ngettext, _.T

local Settings = InputContainer:extend{
    name = "grimmory_settings",
    plugin = nil,
    covers_fullscreen = true,
    user = nil, -- Seite dieses Benutzers statt der Einstellungen
    parent = nil, -- Einstellungen darunter, werden beim Schließen neu gezeichnet
    created = false, -- gerade angelegt: ohne Benutzername beim Schließen wieder weg
}

function Settings:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = UI.width(), h = UI.height() }
    self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
        self.key_events.NextPage = { { Device.input.group.PgFwd } }
        self.key_events.PrevPage = { { Device.input.group.PgBack } }
    end
    self.page = 1
    if not self.user then self.formats_at_open = table.concat(self.plugin:setting("formats"), ",") end
    self:refresh()
end

local function innerWidth() return UI.width() - 2 * UI.px(48) end

local row = UI.row

local function label(text, sub, w)
    local items = { align = "left", UI.text(text, 26, { bold = true, max_width = w }) }
    if sub then table.insert(items, UI.text(sub, 22, { color = UI.GRAY, max_width = w })) end
    return VerticalGroup:new(items)
end

local function chevron() return UI.icon("chevron.right", 32) end

--- Schalter wie im Entwurf: An/Aus als Text und ein Schiebeschalter.
local function switch(on)
    local knob = UI.box(UI.text("", 10), UI.px(34), UI.px(34), {
        border = 0, radius = 17, background = on and UI.WHITE or UI.BLACK })
    local track = FrameContainer:new{
        bordersize = UI.px(3), radius = UI.px(25), color = UI.BLACK, background = on and UI.BLACK or UI.WHITE,
        padding = 0, padding_left = UI.px(5), padding_right = UI.px(5),
        UI.LeftContainer:new{ dimen = Geom:new{ w = UI.px(76), h = UI.px(44) },
            HorizontalGroup:new{ on and UI.hspan(42) or UI.hspan(0), knob } },
    }
    return HorizontalGroup:new{ align = "center",
        UI.text(on and _("An") or _("Aus"), 24, { bold = true, color = on and UI.BLACK or UI.GRAY }), UI.hspan(20), track }
end

--- Eingabedialog für einen Wert, `save` bekommt die Eingabe ohne Leerzeichen am Rand.
function Settings:edit(title, input, save, opts)
    opts = opts or {}
    local dialog
    dialog = InputDialog:new{
        title = title,
        input = input,
        input_hint = opts.hint,
        text_type = opts.password and "password" or nil,
        buttons = { {
            { text = _("Abbrechen"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Speichern"), is_enter_default = true, callback = function()
                local value = dialog:getInputText():gsub("^%s+", ""):gsub("%s+$", "")
                UIManager:close(dialog)
                save(value)
                self:refresh()
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Settings:editSetting(title, key, opts)
    self:edit(title, self.plugin:setting(key), function(value) self.plugin:saveSetting(key, value) end, opts)
end

function Settings:editUser(title, key, opts)
    local p, u = self.plugin, self.user
    local input = key == "password" and p:secret(u).password or u[key]
    self:edit(title, input, function(value) p:saveUser(u, { [key] = value }) end, opts)
end

--- Extra-Header des Benutzers: ändern, entfernen oder mit `index` hinter dem letzten neu anlegen.
function Settings:editHeader(index)
    local p, u = self.plugin, self.user
    local headers = u.headers or {}
    local h = headers[index] or {}
    local dialog
    local buttons = { { text = _("Abbrechen"), id = "close", callback = function() UIManager:close(dialog) end } }
    if headers[index] then
        table.insert(buttons, 1, { text = _("Entfernen"), callback = function()
            UIManager:close(dialog)
            table.remove(headers, index)
            p:saveUser(u, { headers = headers })
            self:refresh()
        end })
    end
    table.insert(buttons, { text = _("Speichern"), callback = function()
        local fields = dialog:getFields()
        UIManager:close(dialog)
        local name = (fields[1] or ""):gsub("%s", "")
        if name ~= "" then
            headers[index] = { name = name, value = fields[2] or "" }
            p:saveUser(u, { headers = headers })
        end
        self:refresh()
    end })
    dialog = MultiInputDialog:new{
        title = _("Extra-Header"),
        description = T(_("gilt nur für %1 und geht bei jeder Anfrage an %2 mit"), users.label(u), users.host(u.server)),
        fields = {
            { description = _("Name"), text = h.name or "", hint = "X-Api-Key" },
            { description = _("Wert"), text = h.value or "", text_type = "password" },
        },
        buttons = { buttons },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Settings:testConnection()
    local p, u = self.plugin, self.user
    if (u.server or "") == "" or (u.username or "") == "" then
        self.test_result = _("Erst Adresse und Benutzer eintragen")
        self:refresh()
        return
    end
    NetworkMgr:runWhenConnected(function()
        -- Anmeldung und Abfrage blockieren; das Popup vorher zeichnen, sonst sieht man nichts davon.
        local info = InfoMessage:new{ text = _("Verbindung zu Grimmory wird getestet …") }
        UIManager:show(info)
        UIManager:forceRePaint()
        local client, err = p:clientFor(u)
        local ok
        if client then
            client.tokens = {}
            ok, err = client:login()
        end
        if ok then
            -- Auch die Liste abfragen, die der Abgleich braucht: Ein Proxy kann die Anmeldung
            -- durchlassen und Anfragen mit Query trotzdem sperren.
            local me, me_err = client:me()
            local list, list_err = client:getJSON("/api/v1/app/books?page=0&size=1")
            self.test_ok = me ~= nil and list ~= nil
            if self.test_ok then
                -- Der Name aus Grimmory steht danach in der Liste und im Gruß.
                p:saveUser(u, { name = (me.name or "") ~= "" and me.name or u.name })
                self.test_result = T(_("Angemeldet als %1"), users.label(u))
            else
                self.test_result = T(_("Anmeldung klappt, Abruf nicht: %1"), api.describe(me_err or list_err))
            end
        else
            self.test_ok = false
            self.test_result = api.describe(err)
        end
        UIManager:close(info)
        self:refresh()
    end)
end

function Settings:chooseStartTab()
    local dialog
    local rows = {}
    for _, tab in ipairs(UI.TABS) do
        table.insert(rows, { { text = tab.label, callback = function()
            UIManager:close(dialog)
            self.plugin:saveSetting("start_tab", tab.id)
            self:refresh()
        end } })
    end
    dialog = ButtonDialog:new{ title = _("Startbereich"), buttons = rows }
    UIManager:show(dialog)
end

--- Welches Regal aus Grimmory der Bereich Regal zeigt, gespeichert beim angemeldeten Benutzer.
--- Die Zahl rechts zählt die Bücher, die davon auf dem Gerät bekannt sind.
function Settings:chooseShelf()
    local p, u = self.plugin, self.plugin:user()
    local books = p.data.books
    local current = lib.findShelf(p.data.shelves, u.regal_shelf)
    local items = { { label = _("Ganze Bibliothek"), right = tostring(#books), value = false, selected = not current,
        keep = true } }
    for _, shelf in ipairs(p.data.shelves or {}) do
        table.insert(items, { label = shelf.name, right = tostring(#lib.shelfBooks(books, shelf)), value = shelf.key,
            selected = current == shelf })
    end
    local Picker = require("grimmoryui/picker")
    UIManager:show(Picker:new{
        back = _("Einstellungen"), items = items, searchable = #items > 8, search_hint = _("Regal suchen"),
        on_pick = function(v)
            p:saveUser(u, { regal_shelf = v })
            if p.app then p.app.page.regal = 1 end
            self:refresh()
        end,
    })
end

function Settings:rows()
    local p = self.plugin
    local w = innerWidth() - UI.px(360)
    local list = {}
    local function add(widget) table.insert(list, widget) end
    local function toggle(text, sub, key)
        add(row(label(text, sub, w), switch(p:setting(key)), function()
            p:saveSetting(key, not p:setting(key))
            self:refresh()
        end))
    end
    local function value(text, shown, callback, sub)
        add(row(label(text, sub, w), HorizontalGroup:new{ align = "center",
            UI.text(shown, 24, { color = UI.DARK, max_width = innerWidth() - w - UI.px(60) }), UI.hspan(12),
            chevron() }, callback))
    end
    local function section(text)
        local widget = UI.section(text)
        widget.keep_with_next = true
        add(widget)
    end

    if self.user then
        self:userRows(add, value, section, w)
        return list
    end

    section(_("BENUTZER"))
    local signed_in = _("Angemeldet")
    for _, u in ipairs(p:users()) do
        local active = p:isActive(u)
        local right = HorizontalGroup:new{ align = "center",
            active and UI.pill(signed_in, { height = 44 }) or UI.hspan(0), UI.hspan(16), chevron() }
        add(row(UserList.entry(p, u, 64, active, true, innerWidth() - right:getSize().w - UI.px(20)), right,
            function() p:showUserEditor(u, self) end, 112))
    end
    add(row(UserList.addEntry(p, 64), nil, function() p:showUserEditor(p:addUser(), self, true) end, 112))

    section(_("ABGLEICH"))
    local minutes, days = p:setting("sync_minutes"), p:setting("remove_read_days")
    toggle(_("Automatisch abgleichen"), T(N_("beim Öffnen, wenn älter als %1 Minute",
        "beim Öffnen, wenn älter als %1 Minuten", minutes), minutes), "auto_sync")
    toggle(_("Lesestand an Grimmory melden"), _("gelesen und angefangen, für alle Geräte"), "report_progress")
    toggle(_("Cover vorab laden"), _("kleine Vorschaubilder beim Abgleich"), "prefetch_covers")

    -- Ein Schalter je Format, das der Server hat oder das gewählt ist. Mindestens eins bleibt an.
    section(_("FORMATE"))
    local counts, selected, names = p.data.formats, {}, {}
    for _, f in ipairs(p:setting("formats")) do selected[f:upper()] = true end
    for f in pairs(counts or {}) do selected[f] = selected[f] or false end
    for f in pairs(selected) do table.insert(names, f) end
    table.sort(names)
    for _, f in ipairs(names) do
        local n = counts and (counts[f] or 0)
        add(row(label(f, n and T(N_("%1 Buch in Grimmory", "%1 Bücher in Grimmory", n), n), w),
            switch(selected[f]), function()
                selected[f] = not selected[f]
                local list = {}
                for _, name in ipairs(names) do if selected[name] then table.insert(list, name) end end
                if #list > 0 then p:saveSetting("formats", list) end
                self:refresh()
            end))
    end

    section(_("BÜCHER"))
    value(_("Speicherort"), p:setting("download_dir"), function() self:editSetting(_("Speicherort für Downloads"), "download_dir") end)
    toggle(_("Gelesene Bücher entfernen"), T(N_("%1 Tag nach dem Lesen vom Gerät löschen",
        "%1 Tage nach dem Lesen vom Gerät löschen", days), days), "remove_read")
    value(_("Belegter Speicher"), _("Suche öffnen"), function() self:close(); p:showOnDevice() end,
        _("Bücher einzeln vom Gerät entfernen"))

    section(_("ANZEIGE"))
    local start = UI.TABS[1].label
    for _, tab in ipairs(UI.TABS) do if tab.id == p:setting("start_tab") then start = tab.label end end
    value(_("Startbereich"), start, function() self:chooseStartTab() end)
    if p:user() then
        local shelf = lib.findShelf(p.data.shelves, p:user().regal_shelf)
        value(_("Regal zeigt"), shelf and shelf.name or _("Ganze Bibliothek"), function() self:chooseShelf() end,
            _("ein Regal aus Grimmory, je Benutzer"))
    end
    toggle(_("Statt des Dateimanagers öffnen"), _("beim Start von KOReader und nach jedem Buch"), "autostart")

    section(_("UPDATES"))
    value(_("GitHub-Repo"), p:setting("update_repo"), function()
        self:editSetting(_("GitHub-Repo für das Selbst-Update"), "update_repo", { hint = _("besitzer/repo") })
    end, _("für Updates ohne AppStore"))
    return list
end

--- Seite eines Benutzers: eigener Server mit Headern, Anmeldung, Wechseln und Entfernen.
function Settings:userRows(add, value, section, w)
    local p, u = self.plugin, self.user
    local active = p:isActive(u)
    local missing = _("nicht eingetragen")
    local function show(v) return (v and v ~= "") and v or missing end
    add(FrameContainer:new{ bordersize = 0, padding = 0, padding_left = UI.px(48), padding_top = UI.px(28),
        padding_bottom = UI.px(28),
        HorizontalGroup:new{ align = "center", UI.avatar(users.initial(u), 96, active), UI.hspan(28),
            VerticalGroup:new{ align = "left",
                UI.text(users.label(u), 44, { bold = true, serif = true, max_width = innerWidth() - UI.px(130) }),
                (u.name or "") ~= "" and UI.text(_("Name aus Grimmory"), 22, { color = UI.GRAY }) or UI.vspan(0) } } })

    section(_("SERVER"))
    value(_("Adresse"), show(u.server), function()
        self:editUser(_("Adresse des Grimmory-Servers"), "server", { hint = "https://grimmory.example.com" })
    end)
    local headers = u.headers or {}
    for i, h in ipairs(headers) do
        value(i == 1 and _("Extra-Header") or "", (h.name or "") .. ": ••••", function() self:editHeader(i) end,
            i == 1 and _("gehen bei jeder Anfrage mit") or nil)
    end
    value(#headers == 0 and _("Extra-Header") or "", _("Header hinzufügen"), function() self:editHeader(#headers + 1) end,
        #headers == 0 and _("gehen bei jeder Anfrage mit") or nil)

    section(_("ANMELDUNG"))
    value(_("Benutzername"), show(u.username), function() self:editUser(_("Benutzername"), "username") end)
    value(_("Passwort"), p:hasPassword(u) and "••••••••" or missing, function()
        self:editUser(_("Passwort"), "password", { password = true })
    end)
    add(row(label(_("Passwort merken"), _("Wechsel ohne Eingabe, liegt unverschlüsselt auf dem Gerät"),
            innerWidth() - UI.px(200)),
        switch(u.remember ~= false), function()
            p:setRemember(u, u.remember == false)
            self:refresh()
        end))
    local result = self.test_result and UI.text(self.test_result, 22, { bold = self.test_ok,
        color = self.test_ok and UI.BLACK or UI.DARK, max_width = innerWidth() - UI.px(400) })
    add(row(HorizontalGroup:new{ align = "center", label(_("Verbindung"), nil, UI.px(200)), UI.hspan(20),
        UI.button(_("Testen"), function() self:testConnection() end, { height = UI.px(64) }) }, result or nil))

    local half = math.floor((innerWidth() - UI.px(24)) / 2)
    local buttons = HorizontalGroup:new{ align = "center" }
    if not active then
        table.insert(buttons, UI.button(T(_("Zu %1 wechseln"), users.label(u)), function() self:switchTo() end,
            { primary = true, width = half, height = UI.px(88) }))
        table.insert(buttons, UI.hspan(24))
    end
    table.insert(buttons, UI.button(_("Benutzer entfernen"), function() self:confirmRemove() end,
        { width = half, height = UI.px(88) }))
    add(UI.padded(VerticalGroup:new{ align = "left", buttons, UI.vspan(16),
        UI.textbox(T(_("Entfernen löscht Zugang, Header und die Bibliothek von %1 auf dem Gerät. Heruntergeladene Bücher bleiben."),
            users.label(u)), 22, innerWidth(), nil, { color = UI.GRAY }) }, 32, 32))
end

--- Zu diesem Benutzer wechseln. Die Einstellungen schließen, der Wechsel öffnet Start.
function Settings:switchTo()
    UIManager:close(self, "flashui")
    if self.parent then self.parent:close() end
    self.plugin:switchUser(self.user)
end

function Settings:confirmRemove()
    local p, u = self.plugin, self.user
    UIManager:show(ConfirmBox:new{
        text = T(_("%1 vom Gerät entfernen?"), users.label(u)),
        ok_text = _("Entfernen"),
        ok_callback = function()
            UIManager:close(self, "flashui")
            -- Geht der angemeldete, öffnet der nächste Benutzer Start; die Einstellungen stünden davor.
            if self.parent then
                if p:isActive(u) then self.parent:close() else UIManager:nextTick(function() self.parent:refresh() end) end
            end
            p:removeUser(u)
        end,
    })
end

function Settings:refresh()
    local H = UI.height()
    local header = UI.header{ back = _("Einstellungen"), on_back = function() self:close() end }
    local avail = H - UI.headerHeight() - UI.px(104)
    local pages, current, used = { {} }, 1, 0
    local rows = self:rows()
    for i, widget in ipairs(rows) do
        local h = widget:getSize().h
        -- Ein Abschnittskopf kommt nur mit seiner ersten Zeile auf die Seite.
        local need = h + ((widget.keep_with_next and rows[i + 1]) and rows[i + 1]:getSize().h or 0)
        if used + need > avail and #pages[current] > 0 then
            current = current + 1
            pages[current] = {}
            used = 0
        end
        table.insert(pages[current], widget)
        used = used + h
    end
    self.pages = #pages
    self.page = math.min(self.page, self.pages)
    local body = { align = "left" }
    for _, widget in ipairs(pages[self.page]) do table.insert(body, widget) end
    local pager = UI.CenterContainer:new{ dimen = Geom:new{ w = UI.width(), h = UI.px(104) },
        UI.pager(self.page, self.pages, function() self:turn(-1) end, function() self:turn(1) end) }
    if self[1] then self[1]:free() end
    self[1] = FrameContainer:new{
        bordersize = 0, padding = 0, margin = 0, background = UI.WHITE, width = UI.width(), height = H,
        VerticalGroup:new{ align = "left", header,
            UI.fixed(VerticalGroup:new(body), UI.width(), avail),
            self.pages > 1 and pager or UI.vspan(0) },
    }
    UIManager:setDirty(self, "ui")
end

function Settings:turn(delta)
    local new = math.min(math.max(self.page + delta, 1), self.pages or 1)
    if new ~= self.page then
        self.page = new
        self:refresh()
    end
end

function Settings:onSwipe(_, ges)
    if ges.direction == "west" then self:turn(1); return true end
    if ges.direction == "east" then self:turn(-1); return true end
end

function Settings:onNextPage() self:turn(1); return true end
function Settings:onPrevPage() self:turn(-1); return true end

function Settings:close()
    local p = self.plugin
    UIManager:close(self, "flashui")
    if self.user then
        local named = (self.user.username or "") ~= ""
        if self.created and not named then p:removeUser(self.user) end
        -- Der erste Benutzer überhaupt meldet sich gleich an.
        if named and not p:user() then
            if self.parent then self.parent:close() end
            p:switchUser(self.user)
            return
        end
        if self.parent then self.parent:refresh() end
        if p.app then p.app:render() end
        return
    end
    if p.app then p.app:render() end
    -- Andere Formate wirken erst mit einem neuen Abgleich.
    if table.concat(p:setting("formats"), ",") ~= self.formats_at_open then p:sync() end
end

function Settings:onClose()
    self:close()
    return true
end

return Settings
