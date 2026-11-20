-- Modelo de texto de uma página.
--
-- page.content  : string UTF-8
-- page.sizes[i] : tamanho da fonte do caractere i
-- page.marks[i] : true se o caractere i está marcado (marca-texto)
-- page.cursor   : posição do cursor (1 .. n+1)
-- page.anchor   : outra ponta da seleção (nil = sem seleção)
-- page.typeSize / page.typeMark : estilo escolhido para o próximo texto
--                                 digitado (sem seleção)
-- page.rev      : versão, usada para invalidar o cache de layout

local utf8 = require("utf8")

local TextEdit = {}

TextEdit.DEFAULT_SIZE = 18
TextEdit.SIZES = { 10, 12, 14, 16, 18, 20, 24, 28, 32, 40, 48 }

function TextEdit.ensure(page)
    page.rev = page.rev or 0

    if not page.sizes then
        page.sizes = {}
        page.marks = {}

        local count = utf8.len(page.content) or 0

        for i = 1, count do
            page.sizes[i] = TextEdit.DEFAULT_SIZE
            page.marks[i] = false
        end
    end
end

local function touch(page)
    page.rev = (page.rev or 0) + 1
end

function TextEdit.length(page)
    return utf8.len(page.content) or 0
end

function TextEdit.cursor(page)
    local n = TextEdit.length(page)

    return math.max(1, math.min(page.cursor or (n + 1), n + 1))
end

-- Retorna a, b (a < b, b exclusivo) ou nil se não há seleção
function TextEdit.selection(page)
    if not page.anchor then
        return nil
    end

    local n = TextEdit.length(page)
    local anchor = math.max(1, math.min(page.anchor, n + 1))
    local cursor = TextEdit.cursor(page)

    if anchor == cursor then
        return nil
    end

    return math.min(anchor, cursor), math.max(anchor, cursor)
end

-- Texto dos caracteres a .. b-1
function TextEdit.getText(page, a, b)
    local content = page.content
    local startByte = utf8.offset(content, a) or (#content + 1)
    local endByte = utf8.offset(content, b) or (#content + 1)

    return content:sub(startByte, endByte - 1)
end

-- Substitui os caracteres [from, to) por text. Retorna o novo cursor.
function TextEdit.replace(page, from, to, text, size, mark)
    TextEdit.ensure(page)

    local content = page.content
    local startByte = utf8.offset(content, from) or (#content + 1)
    local endByte = utf8.offset(content, to) or (#content + 1)

    page.content =
        content:sub(1, startByte - 1)
        .. text
        .. content:sub(endByte)

    for _ = from, to - 1 do
        table.remove(page.sizes, from)
        table.remove(page.marks, from)
    end

    local count = utf8.len(text) or 0

    for k = 0, count - 1 do
        table.insert(page.sizes, from + k, size or TextEdit.DEFAULT_SIZE)
        table.insert(page.marks, from + k, mark or false)
    end

    touch(page)

    return from + count
end

function TextEdit.setSize(page, from, to, size)
    for i = from, to - 1 do
        page.sizes[i] = size
    end

    touch(page)
end

function TextEdit.setMark(page, from, to, value)
    for i = from, to - 1 do
        page.marks[i] = value
    end

    touch(page)
end

-- Estilo do texto que será digitado na posição do cursor
function TextEdit.insertStyle(page)
    TextEdit.ensure(page)

    local previous = TextEdit.cursor(page) - 1

    local size = page.typeSize
        or page.sizes[previous]
        or TextEdit.DEFAULT_SIZE

    local mark = page.typeMark

    if mark == nil then
        mark = page.marks[previous] or false
    end

    return size, mark
end

function TextEdit.stepSize(size, direction)
    local sizes = TextEdit.SIZES

    if direction > 0 then
        for i = 1, #sizes do
            if sizes[i] > size then
                return sizes[i]
            end
        end
    else
        for i = #sizes, 1, -1 do
            if sizes[i] < size then
                return sizes[i]
            end
        end
    end

    return size
end

-- Desfazer rápido (usado quando uma edição não cabe na página)
local function copy(t)
    local c = {}

    for i = 1, #t do
        c[i] = t[i]
    end

    return c
end

function TextEdit.snapshot(page)
    TextEdit.ensure(page)

    return {
        content = page.content,
        sizes = copy(page.sizes),
        marks = copy(page.marks),
        cursor = page.cursor,
        anchor = page.anchor,
        typeSize = page.typeSize,
        typeMark = page.typeMark
    }
end

function TextEdit.restore(page, snap)
    page.content = snap.content
    page.sizes = snap.sizes
    page.marks = snap.marks
    page.cursor = snap.cursor
    page.anchor = snap.anchor
    page.typeSize = snap.typeSize
    page.typeMark = snap.typeMark

    touch(page)
end

return TextEdit