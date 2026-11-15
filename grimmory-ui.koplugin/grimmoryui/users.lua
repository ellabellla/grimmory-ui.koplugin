--[[--
Benutzer des Plugins. Jeder Benutzer ist ein eigener Zugang mit Adresse, Headern, Benutzername und
Passwort. Geteilt wird nichts, so kann jeder Benutzer eine andere Grimmory-Bibliothek nutzen.

In den Einstellungen stehen `users` als Liste und `active_user` als id:

    { id = 1, server = "https://…", headers = { { name =, value = } }, username = "anna",
      remember = true, password = "…", tokens = { … }, name = "Anna" }

`name` kommt aus Grimmory. Ohne `remember` fehlen password und tokens, sie liegen dann nur im
Speicher, bis KOReader neu startet.
]]

local _ = require("grimmoryui/i18n")

local M = {}

--- Der einzelne Zugang bis Version 1.2 als erster Benutzer, nil ohne Server.
function M.fromOld(old)
    if (old.server or "") == "" then return nil end
    return { id = 1, server = old.server, username = old.username or "", password = old.password or "",
        headers = old.headers or {}, tokens = old.tokens, remember = true }
end

--- Neuer Benutzer mit Adresse und Headern von `template` als Vorlage, danach unabhängig davon.
function M.new(list, template)
    local id = 0
    for _, u in ipairs(list) do id = math.max(id, u.id) end
    local headers = {}
    for i, h in ipairs(template and template.headers or {}) do headers[i] = { name = h.name, value = h.value } end
    return { id = id + 1, server = template and template.server or "", headers = headers, username = "", remember = true }
end

--- Benutzer und Position in der Liste.
function M.find(list, id)
    for i, u in ipairs(list) do
        if u.id == id then return u, i end
    end
end

--- Hostname ohne Schema, Port und Pfad: „grimmory.example.com“.
function M.host(server)
    return (server or ""):match("^%a+://([^/:]+)") or ""
end

--- Anzeigename: der Name aus Grimmory, sonst der Benutzername.
function M.label(u)
    if (u.name or "") ~= "" then return u.name end
    if (u.username or "") ~= "" then return u.username end
    return _("Neuer Benutzer")
end

--- Erster Buchstabe für den Kreis, auch wenn er aus mehreren Bytes besteht.
function M.initial(u)
    return (M.label(u):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"):upper()
end

return M
