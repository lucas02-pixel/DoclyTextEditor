-- Quebra de linhas com tamanhos de fonte variáveis, com cache por página.
--
-- Cada linha tem:
--   characters, xs[k] (x antes do caractere k), startIndex, hardBreak,
--   runs  (trechos com o mesmo estilo: text, x, width, font, size, hl),
--   y, height, pad, ascent, descent

local utf8 = require("utf8")
local Fonts = require("src.core.fonts")
local TextEdit = require("src.editor.text_edit")

local TextLayout = {}

local DEFAULT = TextEdit.DEFAULT_SIZE
local LINE_FACTOR = 5 / 3

local cache = setmetatable({}, { __mode = "k" })

function TextLayout.getCharacters(content)
    local characters = {}

    for _, codepoint in utf8.codes(content) do
        characters[#characters + 1] = utf8.char(codepoint)
    end

    return characters
end

local function newLine(startIndex)
    return {
        characters = {},
        xs = { 0 },
        startIndex = startIndex,
        -- true quando a linha termina em "\n" (ou é a última):
        -- só nesses casos o cursor pode ficar depois do último caractere
        hardBreak = false,
        runs = {},
        y = 0,
        height = 0,
        pad = 0,
        ascent = 0,
        descent = 0
    }
end

local function finishLine(line, sizes, marks, hard)
    line.hardBreak = hard

    local chars = line.characters
    local n = #chars
    local start = line.startIndex
    local runs = line.runs
    local run = nil

    for k = 1, n do
        local size = sizes[start + k - 1] or DEFAULT
        local mark = marks[start + k - 1] or false

        if not run or run.size ~= size or run.hl ~= mark then
            run = {
                size = size,
                hl = mark,
                font = Fonts.sized(size),
                first = k,
                last = k
            }

            runs[#runs + 1] = run
        else
            run.last = k
        end
    end

    local maxSize = 0
    local ascent = 0
    local descent = 0

    for _, r in ipairs(runs) do
        r.text = table.concat(chars, "", r.first, r.last)
        r.x = line.xs[r.first]
        r.width = line.xs[r.last + 1] - r.x

        local base = r.font:getBaseline()

        maxSize = math.max(maxSize, r.size)
        ascent = math.max(ascent, base)
        descent = math.max(descent, r.font:getHeight() - base)
    end

    if n == 0 then
        -- Linha vazia herda o estilo do caractere anterior (o "\n")
        maxSize = sizes[start - 1] or DEFAULT

        local font = Fonts.sized(maxSize)

        ascent = font:getBaseline()
        descent = font:getHeight() - ascent
    end

    line.size = maxSize
    line.ascent = ascent
    line.descent = descent
    line.height = math.floor(maxSize * LINE_FACTOR + 0.5)
    line.pad = math.max(0, math.floor((line.height - (ascent + descent)) / 2))
end

local function build(page, maxWidth)
    TextEdit.ensure(page)

    local sizes = page.sizes
    local marks = page.marks
    local characters = TextLayout.getCharacters(page.content)

    local lines = {}
    local current = newLine(1)
    local previousChar = nil
    local previousSize = nil

    for i, character in ipairs(characters) do
        if character == "\n" then
            finishLine(current, sizes, marks, true)
            lines[#lines + 1] = current

            current = newLine(i + 1)
            previousChar = nil
            previousSize = nil
        else
            local size = sizes[i] or DEFAULT
            local font = Fonts.sized(size)

            local advance = font:getWidth(character)
            local kerning = 0

            if previousChar and previousSize == size then
                kerning = font:getKerning(previousChar, character)
            end

            local n = #current.characters

            if n > 0 and current.xs[n + 1] + advance + kerning > maxWidth then
                finishLine(current, sizes, marks, false)
                lines[#lines + 1] = current

                current = newLine(i)
                kerning = 0
                n = 0
            end

            current.characters[n + 1] = character
            current.xs[n + 2] = current.xs[n + 1] + advance + kerning

            previousChar = character
            previousSize = size
        end
    end

    finishLine(current, sizes, marks, true)
    lines[#lines + 1] = current

    local y = 0

    for _, line in ipairs(lines) do
        line.y = y
        y = y + line.height
    end

    return lines, characters, y
end

-- Retorna lines, characters, altura total
function TextLayout.get(page, maxWidth)
    TextEdit.ensure(page)

    local entry = cache[page]

    if entry
    and entry.rev == page.rev
    and entry.maxWidth == maxWidth then
        return entry.lines, entry.characters, entry.height
    end

    local lines, characters, height = build(page, maxWidth)

    cache[page] = {
        rev = page.rev,
        maxWidth = maxWidth,
        lines = lines,
        characters = characters,
        height = height
    }

    return lines, characters, height
end

-- Maior posição de cursor permitida na linha.
-- Em quebra automática, o fim da linha é o começo da próxima.
function TextLayout.maxOffset(line)
    if line.hardBreak then
        return #line.characters
    end

    return #line.characters - 1
end

-- Em qual linha o cursor aparece
function TextLayout.findLine(lines, cursor)
    for i, line in ipairs(lines) do
        local endIndex = line.startIndex + #line.characters

        if cursor >= line.startIndex
        and (cursor < endIndex
            or (cursor == endIndex and line.hardBreak)) then
            return i
        end
    end

    return #lines
end

-- Posição do cursor mais próxima de um x (relativo ao início da linha)
function TextLayout.cursorFromX(line, relativeX)
    local xs = line.xs
    local offset = #line.characters

    for k = 1, #line.characters do
        if relativeX < (xs[k] + xs[k + 1]) / 2 then
            offset = k - 1
            break
        end
    end

    return line.startIndex + math.min(offset, TextLayout.maxOffset(line))
end

return TextLayout