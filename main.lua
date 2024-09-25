local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")
local util = import("micro/util")

local lastResult = nil -- Глобальная переменная для хранения результата

function getTextLoc()
    local v = micro.CurPane()
    local a, b, c = nil, nil, v.Cursor
    if c:HasSelection() then
        if c.CurSelection[1]:GreaterThan(-c.CurSelection[2]) then
            a, b = c.CurSelection[2], c.CurSelection[1]
        else
            a, b = c.CurSelection[1], c.CurSelection[2]
        end
    else
        local eol = string.len(v.Buf:Line(c.Loc.Y))
        a, b = c.Loc, buffer.Loc(eol, c.Y)
    end
    return buffer.Loc(a.X, a.Y), buffer.Loc(b.X, b.Y)
end


function getText(a, b)
    local txt, buf = {}, micro.CurPane().Buf

    -- Editing a single line?
    if a.Y == b.Y then
        return buf:Line(a.Y):sub(a.X+1, b.X)
    end

    -- Add first part of text selection (a.X+1 as Lua is 1-indexed)
    table.insert(txt, buf:Line(a.Y):sub(a.X+1))

    -- Stuff in the middle
    for lineNo = a.Y+1, b.Y-1 do
        table.insert(txt, buf:Line(lineNo))
    end

    -- Insert last part of selection
    table.insert(txt, buf:Line(b.Y):sub(1, b.X))

    return table.concat(txt, "\n")
end

function autocompleteTextCommand(bp)
    if not bp then
        micro.InfoBar():Message("Buffer not found!")
        return
    end
    
    local v = micro.CurPane()
    local a, b = getTextLoc()
    local text = getText(a, b)

    if not text or text == "" then
        micro.InfoBar():Message("No text found in buffer!")
        return
    end

    -- Экранирование текста
    text = text:gsub('"', '\\"') -- Экранируем двойные кавычки
    text = text:gsub('\n', '\\n') -- Экранируем переносы строк

    -- Формируем данные для запроса
    local data = '{"model": "gemma:2b", "prompt": "' .. text .. '", "stream": false}'

    -- Выполняем curl запрос
    local command = "curl -s -X POST http://localhost:11434/api/generate -d '" .. data .. "'"

    -- Используем os.execute для отладки
    local response = io.popen(command):read("*a")

    if response then
        -- Пытаемся найти ответ в строке
        local start_pos, end_pos = string.find(response, '"response":"')
        if start_pos then
            start_pos = end_pos + 1
            end_pos = string.find(response, '"', start_pos)

            if end_pos then
                local newTxt = string.sub(response, start_pos, end_pos - 1)

                -- Заменяем выделенный текст на новый текст
                v.Buf:Replace(a, b, newTxt)
            else
                micro.InfoBar():Message("End quote not found in response")
            end
        else
            micro.InfoBar():Message("Response format incorrect or 'response' key not found")
        end
    else
        micro.InfoBar():Message("No response from server")
    end
end

function init()
    config.MakeCommand("autocompletetext", autocompleteTextCommand, config.NoComplete)
end
