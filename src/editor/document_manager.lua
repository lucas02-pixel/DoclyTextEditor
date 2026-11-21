
local Documents = {}

local documents = {}
local nextId = 1
local APP_FILE = "documents.docly"
local dirty = false
local revision = 0

local function escapeJson(value)
    value = value:gsub("\\", "\\\\")
    value = value:gsub('"', '\\"')
    value = value:gsub("\b", "\\b")
    value = value:gsub("\f", "\\f")
    value = value:gsub("\n", "\\n")
    value = value:gsub("\r", "\\r")
    value = value:gsub("\t", "\\t")

    return '"' .. value:gsub("[%z\1-\31]", function(char)
        return string.format("\\u%04X", string.byte(char))
    end) .. '"'
end

local function isArray(value)
    local count = 0

    for key in pairs(value) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
            return false
        end

        count = count + 1
    end

    for i = 1, count do
        if value[i] == nil then
            return false
        end
    end

    return true
end

local function encodeJson(value)
    local kind = type(value)

    if kind == "nil" then
        return "null"
    elseif kind == "boolean" then
        return value and "true" or "false"
    elseif kind == "number" then
        return tostring(value)
    elseif kind == "string" then
        return escapeJson(value)
    elseif kind == "table" then
        local parts = {}

        if isArray(value) then
            for i = 1, #value do
                parts[#parts + 1] = encodeJson(value[i])
            end

            return "[" .. table.concat(parts, ",") .. "]"
        end

        for key, item in pairs(value) do
            if type(key) == "string" then
                parts[#parts + 1] =
                    escapeJson(key) .. ":" .. encodeJson(item)
            end
        end

        return "{" .. table.concat(parts, ",") .. "}"
    end

    return "null"
end

local function skipWhitespace(text, index)
    while index <= #text do
        local byte = text:byte(index)

        if byte ~= 32 and byte ~= 9 and byte ~= 10 and byte ~= 13 then
            break
        end

        index = index + 1
    end

    return index
end

local function utf8FromCodepoint(codepoint)
    if codepoint < 0x80 then
        return string.char(codepoint)
    elseif codepoint < 0x800 then
        return string.char(
            0xC0 + math.floor(codepoint / 0x40),
            0x80 + codepoint % 0x40
        )
    elseif codepoint < 0x10000 then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + math.floor(codepoint / 0x40) % 0x40,
            0x80 + codepoint % 0x40
        )
    end

    return string.char(
        0xF0 + math.floor(codepoint / 0x40000),
        0x80 + math.floor(codepoint / 0x1000) % 0x40,
        0x80 + math.floor(codepoint / 0x40) % 0x40,
        0x80 + codepoint % 0x40
    )
end

local function decodeJson(text)
    local index = 1

    local function parseString()
        index = index + 1
        local parts = {}

        while index <= #text do
            local char = text:sub(index, index)

            if char == '"' then
                index = index + 1
                return table.concat(parts)
            elseif char == "\\" then
                local nextChar = text:sub(index + 1, index + 1)
                local escapes = {
                    b = "\b", f = "\f", n = "\n",
                    r = "\r", t = "\t", ['"'] = '"',
                    ["\\"] = "\\", ["/"] = "/"
                }

                if nextChar == "u" then
                    local hex = text:sub(index + 2, index + 5)
                    local codepoint = tonumber(hex, 16)

                    if codepoint then
                        parts[#parts + 1] = utf8FromCodepoint(codepoint)
                    end

                    index = index + 6
                elseif escapes[nextChar] then
                    parts[#parts + 1] = escapes[nextChar]
                    index = index + 2
                else
                    return nil
                end
            else
                parts[#parts + 1] = char
                index = index + 1
            end
        end

        return nil
    end

    local parseValue

    local function parseObject()
        index = index + 1
        local result = {}

        index = skipWhitespace(text, index)

        if text:sub(index, index) == "}" then
            index = index + 1
            return result
        end

        while true do
            index = skipWhitespace(text, index)

            if text:sub(index, index) ~= '"' then
                return nil
            end

            local key = parseString()

            if key == nil then
                return nil
            end

            index = skipWhitespace(text, index)

            if text:sub(index, index) ~= ":" then
                return nil
            end

            index = skipWhitespace(text, index + 1)
            local item = parseValue()

            if item == nil then
                return nil
            end

            result[key] = item
            index = skipWhitespace(text, index)

            local separator = text:sub(index, index)

            if separator == "}" then
                index = index + 1
                return result
            elseif separator ~= "," then
                return nil
            end

            index = index + 1
        end
    end

    local function parseArray()
        index = index + 1
        local result = {}

        index = skipWhitespace(text, index)

        if text:sub(index, index) == "]" then
            index = index + 1
            return result
        end

        while true do
            local item = parseValue()

            if item == nil then
                return nil
            end

            result[#result + 1] = item
            index = skipWhitespace(text, index)

            local separator = text:sub(index, index)

            if separator == "]" then
                index = index + 1
                return result
            elseif separator ~= "," then
                return nil
            end

            index = index + 1
        end
    end

    parseValue = function()
        index = skipWhitespace(text, index)
        local char = text:sub(index, index)

        if char == '"' then
            return parseString()
        elseif char == "{" then
            return parseObject()
        elseif char == "[" then
            return parseArray()
        elseif text:sub(index, index + 3) == "true" then
            index = index + 4
            return true
        elseif text:sub(index, index + 4) == "false" then
            index = index + 5
            return false
        elseif text:sub(index, index + 3) == "null" then
            index = index + 4
            return nil
        end

        local number = text:match("^-?%d+%.?%d*[eE]?[+-]?%d*", index)

        if number then
            index = index + #number
            return tonumber(number)
        end

        return nil
    end

    index = skipWhitespace(text, index)
    local result = parseValue()
    index = skipWhitespace(text, index)

    if result == nil or index <= #text then
        return nil
    end

    return result
end

local function plainDocument(document)
    local copy = {
        id = document.id,
        title = document.title,
        currentPage = document.currentPage,
        pages = {}
    }

    for _, page in ipairs(document.pages) do
        local pageCopy = {
            content = page.content,
            cursor = page.cursor,
            anchor = page.anchor,
            sizes = page.sizes,
            marks = page.marks,
            typeSize = page.typeSize,
            typeMark = page.typeMark,
            drawings = page.drawings,
            objects = {}
        }

        if page.objects then
            for _, obj in ipairs(page.objects) do
                local objCopy = {}

                for key, value in pairs(obj) do
                    if key ~= "image" and key ~= "imageData" then
                        objCopy[key] = value
                    end
                end

                if obj.type == "image" and obj.imageData then
                    objCopy.imageData = obj.imageData
                    objCopy.imageName = obj.imageName or "imagem.png"
                end

                pageCopy.objects[#pageCopy.objects + 1] = objCopy
            end
        end

        copy.pages[#copy.pages + 1] = pageCopy
    end

    return copy
end

local function restoreImageObjects(page)
    if not page.objects then
        return
    end

    for _, obj in ipairs(page.objects) do
        if obj.type == "image" and obj.imageData then
            local ok, bytes = pcall(love.data.decode, "string", "base64", obj.imageData)

            if ok and bytes then
                local fileOk, fileData = pcall(
                    love.filesystem.newFileData,
                    bytes,
                    obj.imageName or "imagem.png"
                )

                if fileOk then
                    local imageOk, image = pcall(love.image.newImageData, fileData)

                    if imageOk then
                        local finalOk, loaded = pcall(love.graphics.newImage, image)

                        if finalOk then
                            obj.image = loaded
                        end
                    end
                end
            end

        end
    end
end

local function restoreDocument(saved)
    if type(saved) ~= "table" or type(saved.pages) ~= "table"
    or #saved.pages == 0 then
        return nil
    end

    local document = {
        id = saved.id or nextId,
        title = saved.title or "Documento sem título",
        pages = saved.pages,
        currentPage = math.max(1, math.min(saved.currentPage or 1, #saved.pages))
    }

    nextId = math.max(nextId, tonumber(document.id) or 0)

    for _, page in ipairs(document.pages) do
        restoreImageObjects(page)
    end

    nextId = nextId + 1
    return document
end

local function getSaveText()
    local state = {}

    for _, document in ipairs(documents) do
        state[#state + 1] = plainDocument(document)
    end

    return encodeJson({
        format = "docly",
        version = 1,
        documents = state
    })
end

function Documents.create()
    local document = {
        id = nextId,
        title = "Documento sem título",

        pages = {
            {
                content = "",
                cursor = 1
            }
        },

        currentPage = 1
    }

    nextId = nextId + 1
    table.insert(documents, document)
    Documents.markDirty()

    return document
end

function Documents.getAll()
    return documents
end

function Documents.getRevision()
    return revision
end

function Documents.rename(document, title)
    title = (title or ""):match("^%s*(.-)%s*$")

    if title == "" then
        return nil, "empty_title"
    end

    document.title = title
    Documents.markDirty()
    return true
end

function Documents.getCurrentPage(document)
    return document.pages[document.currentPage]
end

function Documents.addPage(document)
    local newPage = {
        content = "",
        cursor = 1
    }

    local insertPosition = document.currentPage + 1

    table.insert(document.pages, insertPosition, newPage)
    Documents.markDirty()

    return insertPosition
end

function Documents.markDirty()
    dirty = true
    revision = revision + 1
end

function Documents.saveAppData()
    if not dirty then
        return true
    end

    local ok, err = love.filesystem.write(APP_FILE, getSaveText())

    if ok then
        dirty = false
    end

    return ok, err
end

function Documents.loadAppData()
    if not love.filesystem.getInfo(APP_FILE) then
        return
    end

    local ok, text = pcall(love.filesystem.read, APP_FILE)

    if not ok or not text then
        return
    end

    local decodeOk, state = pcall(decodeJson, text)

    if not decodeOk or type(state) ~= "table" or state.format ~= "docly"
    or type(state.documents) ~= "table" then
        return
    end

    documents = {}
    nextId = 1
    revision = revision + 1

    for _, saved in ipairs(state.documents) do
        local document = restoreDocument(saved)

        if document then
            table.insert(documents, document)
        end
    end

    dirty = false
end

local function safeName(name)
    name = name:gsub('[<>:"/\\|?*%c]', "_")
    name = name:gsub("%s+$", "")

    if name == "" then
        return "Documento"
    end

    return name
end

function Documents.exportDocly(document, path)
    if not path then
        return false
    end

    local text = encodeJson({
        format = "docly",
        version = 1,
        documents = { plainDocument(document) }
    })

    local handle = io.open(path, "wb")

    if not handle then
        return false
    end

    local ok = handle:write(text)
    local closeOk = handle:close()

    return ok ~= nil and closeOk ~= nil
end

function Documents.exportTxt(document, path)
    if not path then
        return false
    end

    local lines = { document.title }

    for i, page in ipairs(document.pages) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Pagina " .. i
        lines[#lines + 1] = page.content or ""

        if page.objects then
            for _, obj in ipairs(page.objects) do
                if obj.type == "textbox" and obj.content ~= "" then
                    lines[#lines + 1] = obj.content
                elseif obj.type == "attachment" then
                    lines[#lines + 1] = "[Anexo: " .. (obj.label or obj.path or "") .. "]"
                end
            end
        end
    end

    local handle = io.open(path, "wb")

    if not handle then
        return false
    end

    local ok = handle:write(table.concat(lines, "\n"))
    local closeOk = handle:close()

    return ok ~= nil and closeOk ~= nil
end

function Documents.defaultName(document)
    return safeName(document.title)
end

function Documents.openDocly(path)
    local handle = io.open(path, "rb")

    if not handle then
        return nil, "unavailable"
    end

    local text = handle:read("*a")
    handle:close()

    local decodeOk, state = pcall(decodeJson, text)

    if not decodeOk or type(state) ~= "table" or state.format ~= "docly" then
        return nil, "invalid"
    end

    local savedDocuments = state.documents

    if savedDocuments == nil and type(state.pages) == "table" then
        savedDocuments = { state }
    end

    if type(savedDocuments) ~= "table" then
        return nil, "invalid"
    end

    for _, saved in ipairs(savedDocuments) do
        local document = restoreDocument(saved)

        if document then
            table.insert(documents, document)
            Documents.markDirty()
            return document
        end
    end

    return nil, "invalid"
end

return Documents
