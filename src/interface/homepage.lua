local Documents = require("src.editor.document_manager")
local Fonts = require("src.core.fonts")
local FileDialog = require("src.core.file_dialog")
local utf8 = require("utf8")

local Homepage = {}

local query = ""
local searchFocused = false
local scrollOffset = 0
local indexedRevision = -1
local indexedDocuments = {}
local filteredDocuments = {}
local filteredQuery = nil
local modal = nil
local mouseX = 0
local mouseY = 0

local function clamp(value, low, high)
    return math.max(low, math.min(value, high))
end

local function normalize(text)
    local replacements = {
        ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a",
        ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
        ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
        ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o",
        ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
        ["ç"] = "c",
        ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a",
        ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
        ["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i",
        ["Ó"] = "o", ["Ò"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ö"] = "o",
        ["Ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
        ["Ç"] = "c"
    }

    text = (text or ""):lower()

    for accented, plain in pairs(replacements) do
        text = text:gsub(accented, plain)
    end

    return text
end

local function refreshIndex()
    local revision = Documents.getRevision()

    if indexedRevision == revision then
        return
    end

    indexedRevision = revision
    indexedDocuments = {}

    for _, document in ipairs(Documents.getAll()) do
        local parts = {}

        for _, page in ipairs(document.pages or {}) do
            if page.content and page.content ~= "" then
                parts[#parts + 1] = page.content:gsub("[%s]+", " ")
            end

            for _, object in ipairs(page.objects or {}) do
                local objectText = object.content or object.label

                if objectText and objectText ~= "" then
                    parts[#parts + 1] = objectText:gsub("[%s]+", " ")
                end
            end
        end

        local preview = table.concat(parts, " ")

        if preview == "" then
            preview = "Documento vazio"
        elseif (utf8.len(preview) or #preview) > 92 then
            local previewEnd = utf8.offset(preview, 93)
            preview = previewEnd and preview:sub(1, previewEnd - 1) or preview
            preview = preview .. "..."
        end

        indexedDocuments[#indexedDocuments + 1] = {
            document = document,
            preview = preview,
            searchText = normalize(document.title .. " " .. table.concat(parts, " "))
        }
    end

    filteredQuery = nil
end

local function matchingDocuments()
    refreshIndex()

    local needle = normalize(query)

    if filteredQuery ~= needle then
        filteredQuery = needle
        filteredDocuments = {}

        for i = #indexedDocuments, 1, -1 do
            local entry = indexedDocuments[i]

            if needle == "" or entry.searchText:find(needle, 1, true) then
                filteredDocuments[#filteredDocuments + 1] = entry
            end
        end
    end

    return filteredDocuments
end

local function layout(entries)
    local width = love.graphics.getWidth()
    local padding = 55
    local available = math.max(220, width - padding * 2)
    local gap = 18
    local columns = clamp(math.floor((available + gap) / 238), 1, 4)
    local cardWidth = math.floor((available - gap * (columns - 1)) / columns)
    local cardHeight = 158
    local rows = math.max(1, math.ceil(#entries / columns))
    local contentBottom = 338 + rows * cardHeight + (rows - 1) * gap
    local maxScroll = math.max(0, contentBottom - (love.graphics.getHeight() - 24))

    scrollOffset = clamp(scrollOffset, 0, maxScroll)

    return padding, available, columns, cardWidth, cardHeight, gap, rows, maxScroll
end

local function cardAt(x, y, entries)
    if y < 328 or y >= love.graphics.getHeight() then
        return nil
    end

    local padding, _, columns, cardWidth, cardHeight, gap =
        layout(entries)
    local row = math.floor((y + scrollOffset - 338) / (cardHeight + gap))

    if row < 0 then
        return nil
    end

    local column = math.floor((x - padding) / (cardWidth + gap))

    if column < 0 or column >= columns then
        return nil
    end

    local cardX = padding + column * (cardWidth + gap)
    local cardY = 338 + row * (cardHeight + gap) - scrollOffset
    local index = row * columns + column + 1

    if x <= cardX + cardWidth
    and y >= cardY and y <= cardY + cardHeight then
        return entries[index] and index or nil
    end

    return nil
end

local function roundedButton(text, x, y, w, h, dark)
    local tone = dark and 0.07 or 0.96
    love.graphics.setColor(tone, tone, tone)
    love.graphics.rectangle("fill", x, y, w, h, 10, 10)

    love.graphics.setFont(Fonts.ui)
    love.graphics.setColor(dark and 1 or 0.08,
        dark and 1 or 0.08, dark and 1 or 0.08)
    local textWidth = Fonts.ui:getWidth(text)
    love.graphics.print(text, x + (w - textWidth) / 2,
        y + (h - Fonts.ui:getHeight()) / 2)
end

local function drawModal()
    if not modal then
        return
    end

    local width = love.graphics.getWidth()
    local height = love.graphics.getHeight()
    local boxWidth = math.min(460, width - 40)
    local boxX = (width - boxWidth) / 2
    local boxY = (height - 210) / 2

    love.graphics.setColor(0, 0, 0, 0.38)
    love.graphics.rectangle("fill", 0, 0, width, height)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", boxX, boxY, boxWidth, 210, 14, 14)

    love.graphics.setFont(Fonts.title)
    love.graphics.setColor(0.06, 0.06, 0.06)
    love.graphics.print(modal.kind == "new" and "Novo documento" or "Renomear documento",
        boxX + 24, boxY + 22)

    love.graphics.setColor(0.96, 0.96, 0.96)
    love.graphics.rectangle("fill", boxX + 24, boxY + 78, boxWidth - 48, 44, 8, 8)
    love.graphics.setFont(Fonts.ui)
    love.graphics.setColor(0.08, 0.08, 0.08)
    love.graphics.printf(modal.value, boxX + 36, boxY + 90, boxWidth - 72, "left")

    if modal.error then
        love.graphics.setFont(Fonts.small)
        love.graphics.setColor(0.75, 0.12, 0.12)
        love.graphics.print("O nome não pode ficar vazio.", boxX + 24, boxY + 130)
    end

    roundedButton("Cancelar", boxX + boxWidth - 218, boxY + 150, 90, 40, false)
    roundedButton(modal.kind == "new" and "Criar" or "Salvar",
        boxX + boxWidth - 116, boxY + 150, 92, 40, true)
end

local function finishModal()
    local title = modal.value:match("^%s*(.-)%s*$")

    if title == "" then
        modal.error = true
        return nil
    end

    if modal.kind == "new" then
        local document = Documents.create()
        Documents.rename(document, title)
        modal = nil
        return document
    end

    local ok = Documents.rename(modal.document, title)

    if not ok then
        modal.error = true
        return nil
    end

    modal = nil
    return nil
end

function Homepage.draw()
    local width = love.graphics.getWidth()
    local height = love.graphics.getHeight()
    local entries = matchingDocuments()

    love.graphics.clear(1, 1, 1)

    love.graphics.setFont(Fonts.title)
    love.graphics.setColor(0.06, 0.06, 0.06)
    love.graphics.print("Docly", 55, 34)

    local searchX = width - 385
    local searchY = 30
    local searchW = 330

    love.graphics.setColor(searchFocused and 0.94 or 0.965,
        searchFocused and 0.94 or 0.965, searchFocused and 0.94 or 0.965)
    love.graphics.rectangle("fill", searchX, searchY, searchW, 42, 10, 10)

    love.graphics.setFont(Fonts.ui)
    love.graphics.setColor(query == "" and 0.45 or 0.12,
        query == "" and 0.45 or 0.12, query == "" and 0.45 or 0.12)
    local searchText = query == "" and "Pesquisar documentos..." or query
    love.graphics.printf(searchText, searchX + 16, searchY + 11, searchW - 52, "left")

    if query ~= "" then
        love.graphics.setColor(0.70, 0.70, 0.70)
        love.graphics.circle("fill", searchX + searchW - 23, searchY + 21, 10)
        love.graphics.setColor(1, 1, 1)
        love.graphics.setLineWidth(2)
        love.graphics.line(searchX + searchW - 27, searchY + 17,
            searchX + searchW - 19, searchY + 25)
        love.graphics.line(searchX + searchW - 19, searchY + 17,
            searchX + searchW - 27, searchY + 25)
    end

    love.graphics.setFont(Fonts.title)
    love.graphics.setColor(0.06, 0.06, 0.06)
    love.graphics.print("Seus documentos", 55, 116)

    love.graphics.setFont(Fonts.ui)
    love.graphics.setColor(0.48, 0.48, 0.48)
    love.graphics.print("Tudo o que você cria, em um só lugar.", 55, 158)

    roundedButton("+ Novo documento", 55, 208, 190, 48, true)
    roundedButton("Abrir .docly", 260, 208, 190, 48, false)

    love.graphics.setFont(Fonts.ui)
    love.graphics.setColor(0.06, 0.06, 0.06)
    love.graphics.print(query == "" and "Recentes" or "Resultados", 55, 292)

    love.graphics.setFont(Fonts.small)
    love.graphics.setColor(0.50, 0.50, 0.50)
    local countText = #entries == 1 and "1 documento" or #entries .. " documentos"
    love.graphics.print(countText, width - 55 - Fonts.small:getWidth(countText), 297)

    if #entries == 0 then
        love.graphics.setColor(0.965, 0.965, 0.965)
        love.graphics.rectangle("fill", 55, 350, width - 110, 180, 12, 12)
        love.graphics.setFont(Fonts.ui)
        love.graphics.setColor(0.38, 0.38, 0.38)
        love.graphics.printf(
            query == "" and "Crie seu primeiro documento ou abra um arquivo .docly."
                or "Nenhum documento encontrado para \"" .. query .. "\".",
            79, 414, width - 158, "center"
        )
    else
        local padding, available, columns, cardWidth, cardHeight, gap =
            layout(entries)
        local firstRow = math.max(0, math.floor((scrollOffset - 338) / (cardHeight + gap)))
        local lastRow = math.min(math.ceil(#entries / columns) - 1,
            math.floor((height + scrollOffset - 338) / (cardHeight + gap)))

        love.graphics.setScissor(padding, 328, available, math.max(0, height - 328))

        for row = firstRow, lastRow do
            for column = 0, columns - 1 do
                local index = row * columns + column + 1
                local entry = entries[index]

                if entry then
                    local x = padding + column * (cardWidth + gap)
                    local y = 338 + row * (cardHeight + gap) - scrollOffset
                    local isHovered = mouseX >= x and mouseX <= x + cardWidth
                        and mouseY >= y and mouseY <= y + cardHeight
                    local isRenameHovered = isHovered
                        and mouseX >= x + 12 and mouseX <= x + 88
                        and mouseY >= y + cardHeight - 38
                        and mouseY <= y + cardHeight - 8

                    love.graphics.setColor(isHovered and 0.94 or 0.975,
                        isHovered and 0.94 or 0.975,
                        isHovered and 0.94 or 0.975)
                    love.graphics.rectangle("fill", x, y, cardWidth, cardHeight, 12, 12)

                    love.graphics.setFont(Fonts.ui)
                    love.graphics.setColor(0.08, 0.08, 0.08)
                    love.graphics.printf(entry.document.title, x + 18, y + 18,
                        cardWidth - 36, "left")

                    love.graphics.setFont(Fonts.small)
                    love.graphics.setColor(0.48, 0.48, 0.48)
                    love.graphics.printf(entry.preview, x + 18, y + 58,
                        cardWidth - 36, "left")

                    local pageCount = #(entry.document.pages or {})
                    local pageText = pageCount == 1 and "1 página"
                        or pageCount .. " páginas"
                    love.graphics.setColor(0.62, 0.62, 0.62)
                    love.graphics.print(pageText, x + cardWidth - 18 - Fonts.small:getWidth(pageText),
                        y + cardHeight - 28)

                    love.graphics.setColor(isRenameHovered and 0.08 or 0.42,
                        isRenameHovered and 0.08 or 0.42,
                        isRenameHovered and 0.08 or 0.42)
                    love.graphics.print("Renomear", x + 18, y + cardHeight - 28)
                end
            end
        end

        love.graphics.setScissor()
    end

    drawModal()
end

function Homepage.mousepressed(x, y, button)
    if button ~= 1 then
        return nil
    end

    mouseX, mouseY = x, y

    local width = love.graphics.getWidth()

    if modal then
        local boxWidth = math.min(460, width - 40)
        local boxX = (width - boxWidth) / 2
        local boxY = (love.graphics.getHeight() - 210) / 2

        if x >= boxX + boxWidth - 218 and x <= boxX + boxWidth - 128
        and y >= boxY + 150 and y <= boxY + 190 then
            modal = nil
            return nil
        elseif x >= boxX + boxWidth - 116 and x <= boxX + boxWidth - 24
        and y >= boxY + 150 and y <= boxY + 190 then
            return finishModal()
        end

        return nil
    end

    local searchX = width - 385
    local searchY = 30
    local searchW = 330

    if x >= searchX and x <= searchX + searchW
    and y >= searchY and y <= searchY + 42 then
        if query ~= "" and x >= searchX + searchW - 38 then
            query = ""
            scrollOffset = 0
        end

        searchFocused = true
        return nil
    end

    searchFocused = false

    if x >= 55 and x <= 245 and y >= 208 and y <= 256 then
        modal = {
            kind = "new",
            value = "Documento sem título",
            replaceOnInput = true
        }
        return nil
    end

    if x >= 260 and x <= 450 and y >= 208 and y <= 256 then
        local result, reason = FileDialog.pick("docly")

        if result then
            local document, openReason = Documents.openDocly(result.path)

            if document then
                return document
            end

            print("Docly: não foi possível abrir o arquivo (" .. tostring(openReason) .. ")")
        elseif reason ~= "cancelled" then
            print("Docly: não foi possível abrir o seletor")
        end

        return nil
    end

    local entries = matchingDocuments()
    local index = cardAt(x, y, entries)

    if index then
        local padding, _, columns, cardWidth, cardHeight, gap = layout(entries)
        local column = (index - 1) % columns
        local cardX = padding + column * (cardWidth + gap)
        local cardY = 338 + math.floor((index - 1) / columns)
            * (cardHeight + gap) - scrollOffset

        if x >= cardX + 12 and x <= cardX + 100
        and y >= cardY + cardHeight - 38 and y <= cardY + cardHeight - 8 then
            modal = {
                kind = "rename",
                value = entries[index].document.title,
                document = entries[index].document,
                replaceOnInput = true
            }
            return nil
        end

        return entries[index].document
    end

    return nil
end

function Homepage.mousemoved(x, y)
    mouseX, mouseY = x, y
end

function Homepage.isClickable(x, y)
    if modal then
        return true
    end

    if (x >= 55 and x <= 245 and y >= 208 and y <= 256)
    or (x >= 260 and x <= 450 and y >= 208 and y <= 256) then
        return true
    end

    if x >= love.graphics.getWidth() - 385
    and x <= love.graphics.getWidth() - 55
    and y >= 30 and y <= 72 then
        return true
    end

    return cardAt(x, y, matchingDocuments()) ~= nil
end

function Homepage.textinput(text)
    if modal then
        if modal.replaceOnInput then
            modal.value = ""
            modal.replaceOnInput = nil
        end

        modal.value = modal.value .. text
        modal.error = false
        return
    end

    if searchFocused and utf8.len(text) then
        query = query .. text
        scrollOffset = 0
    end
end

function Homepage.keypressed(key)
    if modal then
        if key == "return" or key == "kpenter" then
            return finishModal()
        elseif key == "escape" then
            modal = nil
        elseif key == "backspace" then
            local length = utf8.len(modal.value)

            if length and length > 0 then
                local byteOffset = utf8.offset(modal.value, length)
                modal.value = modal.value:sub(1, byteOffset - 1)
            end

            modal.error = false
        end

        return nil
    end

    if key == "backspace" and searchFocused then
        local length = utf8.len(query)

        if length and length > 0 then
            local byteOffset = utf8.offset(query, length)
            query = query:sub(1, byteOffset - 1)
            scrollOffset = 0
        end
    elseif key == "escape" then
        query = ""
        searchFocused = false
        scrollOffset = 0
    elseif key == "return" or key == "kpenter" then
        searchFocused = false
    end

    return nil
end

function Homepage.wheelmoved(_, y)
    local entries = matchingDocuments()
    local _, _, _, _, _, _, _, maxScroll = layout(entries)
    scrollOffset = clamp(scrollOffset - y * 42, 0, maxScroll)
end

return Homepage
