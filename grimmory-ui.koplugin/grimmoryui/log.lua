--[[--
Eigenes Log des Plugins, grimmory-ui.log im Datenordner. Wird es größer als 4 MB, wird es zu
grimmory-ui.log.1 (die vorige fällt weg) und ein neues beginnt, zusammen also höchstens 8 MB.
Hinein kommen nie Header, Tokens, Passwörter oder Query-Strings. Der Abgleich-Prozess schreibt in
dieselbe Datei.
]]

local M = { max = 4 * 1024 * 1024 }

--- Ab jetzt nach `file` schreiben, nil schaltet das Log ab.
function M.open(file) M.file = file end

--- Eine Zeile mit Zeitstempel, die Argumente durch Leerzeichen getrennt.
function M.write(...)
    if not M.file then return end
    local parts = { os.date("%Y-%m-%d %H:%M:%S") }
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ") .. "\n"
    local fh = io.open(M.file, "a")
    if not fh then return end
    if fh:seek("end") + #line > M.max then
        fh:close()
        os.rename(M.file, M.file .. ".1")
        fh = io.open(M.file, "a")
        if not fh then return end
    end
    fh:write(line)
    fh:close()
end

return M
