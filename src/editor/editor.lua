local Editor = {}

local Documents = require("src.editor.document_manager")
local TextLayout = require("src.editor.text_layout")
local TextEdit = require("src.editor.text_edit")
local Fonts = require("src.core.fonts")
local Draw = require("src.tools.draw")
local FileDialog = require("src.core.file_dialog")
local utf8 = require("utf8")

-- Layout da página -----------------------------------------------------

local pageY = 115
local pageX
local pageWidth
local textWidth

local textPaddingX = 65
local textPaddingTop = 46
local textPaddingBottom = 30

local gap = 18
local peek = 48

-- Folha em pé, como de caderno (largura / altura)
local PAGE_RATIO = 0.72

local buttonRadius = 21
local buttonHitRadius = 25

local boxPadding = 8
local handleRadius = 9

-- Cores ----------------------------------------------------------------

local PALETTE = {
    { 0.05, 0.05, 0.05 },
    { 0.86, 0.20, 0.20 },
    { 0.20, 0.40, 0.90 },
    { 0.15, 0.65, 0.35 },
    { 0.95, 0.55, 0.10 }
}

local HIGHLIGHTS = {
    { 1.00, 0.90, 0.30, 0.75 },
    { 0.55, 0.90, 0.50, 0.70 },
    { 1.00, 0.60, 0.75, 0.70 },
    { 0.55, 0.80, 1.00, 0.70 }
}

local IMAGE_EXTENSIONS = { png = true, jpg = true, jpeg = true, bmp = true, tga = true }

-- Estado ---------------------------------------------------------------

local animation = {
    active = false,
    offset = 0
}

local penColor = 1
local shapeColor = 3
local shapeKind = "rect"
local shapeFill = false
local highlightColor = 1

local ERASER_RADII = { 6, 12, 24 }
local eraserSize = 2
local erasing = false
local lastErase = nil

local selected = nil        -- objeto selecionado da página
local focus = nil           -- caixa de texto com foco (ou nil = texto da página)
local selecting = nil       -- alvo de texto sendo selecionado com o mouse
local highlightDrag = false -- a seleção atual vai virar marca-texto
local dragging = nil        -- arrasto de objeto (mover, redimensionar, criar)
local toolReset = false
local lastTool = nil
local message = nil         -- aviso temporário na barra de opções
local lastClick = { time = 0, x = 0, y = 0 }

local function showMessage(text)
    message = { text = text, expires = love.timer.getTime() + 6 }
end

-- Utilidades -----------------------------------------------------------

local function getPageHeight()
    return love.graphics.getHeight() - pageY - 45
end

local function clamp(value, low, high)
    return math.max(low, math.min(value, high))
end

local function updateLayout()
    local width = love.graphics.getWidth()

    -- A altura vem da janela; a largura segue a proporção de um caderno
    pageWidth = clamp(
        math.floor(getPageHeight() * PAGE_RATIO),
        300,
        math.max(300, width - 180)
    )

    pageX = (width - pageWidth) / 2

    -- Margens proporcionais para sobrar espaço de texto numa folha estreita
    textPaddingX = clamp(math.floor(pageWidth * 0.1), 26, 65)
    textWidth = pageWidth - textPaddingX * 2
end

local function getUsableHeight()
    return getPageHeight() - textPaddingTop - textPaddingBottom
end

local function isInsidePage(x, y)
    return x >= pageX and x <= pageX + pageWidth
        and y >= pageY and y <= pageY + getPageHeight()
end

local function shiftDown()
    return love.keyboard.isDown("lshift", "rshift")
end

local function ctrlDown()
    return love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
end

-- Digitar só faz sentido nestas ferramentas
local function typingAllowed(activeTool)
    return activeTool == nil
        or activeTool == "text"
        or activeTool == "highlight"
end

local function isBox(target)
    return target.type == "textbox"
end

-- Origem e largura do texto de um alvo (página ou caixa de texto)
local function geometry(target)
    if isBox(target) then
        return pageX + target.x + boxPadding,
            pageY + target.y + boxPadding,
            target.w - boxPadding * 2
    end

    return pageX + textPaddingX, pageY + textPaddingTop, textWidth
end

local function layoutOf(target)
    local _, _, width = geometry(target)

    return TextLayout.get(target, width)
end

-- Objetos da página ----------------------------------------------------

local function objectBounds(obj)
    if isBox(obj) then
        local _, _, height = TextLayout.get(obj, obj.w - boxPadding * 2)

        return obj.x, obj.y, obj.w, math.max(height, 30) + boxPadding * 2
    end

    return obj.x, obj.y, obj.w, obj.h
end

local function hitObject(page, px, py)
    local objects = page.objects

    if not objects then
        return nil
    end

    local tolerance = 4

    for i = #objects, 1, -1 do
        local obj = objects[i]
        local x, y, w, h = objectBounds(obj)

        if px >= x - tolerance and px <= x + w + tolerance
        and py >= y - tolerance and py <= y + h + tolerance then
            return obj
        end
    end

    return nil
end

-- Alças de redimensionar: cantos primeiro, depois os lados.
-- (nw = canto superior esquerdo, e = lado direito, etc.)
local HANDLE_CURSORS = {
    nw = "sizenwse", se = "sizenwse",
    ne = "sizenesw", sw = "sizenesw",
    n = "sizens", s = "sizens",
    e = "sizewe", w = "sizewe"
}

local function getHandles(obj)
    if obj.type == "attachment" then
        return {}
    end

    local x, y, w, h = objectBounds(obj)

    local points = {
        nw = { x, y },
        ne = { x + w, y },
        sw = { x, y + h },
        se = { x + w, y + h },
        n = { x + w / 2, y },
        s = { x + w / 2, y + h },
        w = { x, y + h / 2 },
        e = { x + w, y + h / 2 }
    }

    -- Caixa de texto só muda de largura (a altura segue o texto)
    local order = { "nw", "ne", "sw", "se", "n", "s", "w", "e" }

    if isBox(obj) then
        order = { "w", "e" }
    end

    local handles = {}

    for _, id in ipairs(order) do
        handles[#handles + 1] = { id = id, x = points[id][1], y = points[id][2] }
    end

    return handles
end

-- Qual alça está sob o ponto (px, py), se houver
local function handleAt(obj, px, py)
    if not obj then
        return nil
    end

    for _, handle in ipairs(getHandles(obj)) do
        local dx = px - handle.x
        local dy = py - handle.y

        if dx * dx + dy * dy <= handleRadius * handleRadius then
            return handle.id
        end
    end

    return nil
end

-- Dentro da caixa de texto (fora da borda de arrastar)?
local function isInsideBoxText(box, px, py)
    local x, y, w, h = objectBounds(box)

    return px >= x + boxPadding and px <= x + w - boxPadding
        and py >= y + boxPadding and py <= y + h - boxPadding
end

local function removeObject(page, obj)
    for i, other in ipairs(page.objects or {}) do
        if other == obj then
            table.remove(page.objects, i)
            Documents.markDirty()
            break
        end
    end
end

-- Tira seleção e foco (caixa de texto vazia é descartada)
local function clearSelection(document)
    if focus and focus.content == "" then
        removeObject(Documents.getCurrentPage(document), focus)
    end

    focus = nil
    selected = nil
end

-- Alvo de edição de texto atual -------------------------------------------

local function getContext(document)
    if focus then
        return {
            target = focus,
            isPage = false,
            maxHeight = math.max(
                40,
                getPageHeight() - focus.y - boxPadding * 2
            )
        }
    end

    return {
        target = Documents.getCurrentPage(document),
        isPage = true,
        maxHeight = getUsableHeight()
    }
end

-- Botões laterais ------------------------------------------------------

local function getButtons()
    local width = love.graphics.getWidth()
    local y = love.graphics.getHeight() / 2

    return {
        { id = "prev", x = 42, y = y },
        { id = "next", x = width - 105, y = y },
        { id = "add", x = width - 48, y = y }
    }
end

local function hitButton(mx, my)
    for _, button in ipairs(getButtons()) do
        local dx = mx - button.x
        local dy = my - button.y

        if dx * dx + dy * dy <= buttonHitRadius * buttonHitRadius then
            return button.id
        end
    end

    return nil
end

-- Barra de opções (muda conforme a ferramenta) -----------------------------

-- Tamanho e marcação que a barra de formatação deve mostrar
local function getFormatState(target)
    TextEdit.ensure(target)

    local a, b = TextEdit.selection(target)

    if a then
        local allMarked = true

        for i = a, b - 1 do
            if not target.marks[i] then
                allMarked = false
                break
            end
        end

        return target.sizes[a], allMarked
    end

    local size, mark = TextEdit.insertStyle(target)

    return size, mark and true or false
end

local function buildBar(document, activeTool)
    local font = Fonts.small
    local items = {}

    local function button(id, label, width, active)
        items[#items + 1] = {
            kind = "button", id = id, label = label, w = width, active = active
        }
    end

    local function label(text, width, dark)
        items[#items + 1] = {
            kind = "label",
            label = text,
            w = width or (font:getWidth(text) + 4),
            dark = dark
        }
    end

    local function swatches(prefix, colors, selectedIndex)
        for i, color in ipairs(colors) do
            items[#items + 1] = {
                kind = "swatch",
                id = prefix .. ":" .. i,
                color = color,
                w = 26,
                active = i == selectedIndex
            }
        end
    end

    local function formatControls(target)
        local size, marked = getFormatState(target)

        button("smaller", "A-", 30)
        label(tostring(size), 44, true)
        button("bigger", "A+", 30)
        button("mark", "Marcar", 74, marked)
    end

    local function shapeControls(obj)
        button("fill", "Preencher", 80, obj and obj.fill or (not obj and shapeFill))
        swatches("shape", PALETTE, obj and obj.color or shapeColor)
    end

    if message and love.timer.getTime() < message.expires then
        label(message.text, nil, true)

    elseif activeTool == "draw" then
        swatches("pen", PALETTE, penColor)

    elseif activeTool == "eraser" then
        button("erase:1", "Fino", 52, eraserSize == 1)
        button("erase:2", "Médio", 58, eraserSize == 2)
        button("erase:3", "Grosso", 64, eraserSize == 3)
        button("clear", "Limpar tudo", 96)

    elseif activeTool == "shape" then
        button("kind:rect", "Retângulo", 86, shapeKind == "rect")
        button("kind:ellipse", "Elipse", 64, shapeKind == "ellipse")
        button("kind:line", "Linha", 56, shapeKind == "line")
        shapeControls(nil)

    elseif activeTool == "highlight" then
        label("Cor:")
        swatches("hl", HIGHLIGHTS, highlightColor)

    elseif activeTool == "image" then
        label("Clique na folha ou arraste uma imagem para a janela")

    elseif activeTool == "attachment" then
        label("Clique na folha ou arraste um arquivo para a janela")

    elseif focus then
        formatControls(focus)

    elseif selected and selected.type == "shape" then
        shapeControls(selected)

    elseif selected and selected.type == "image" then
        label("Cantos e lados redimensionam (Shift solta a proporção)  •  Delete remove")

    elseif selected and selected.type == "attachment" then
        label("Duplo clique abre  •  Delete remove")

    elseif activeTool == "text" then
        label("Clique na folha para criar uma caixa de texto")

    else
        formatControls(Documents.getCurrentPage(document))
        button("export:txt", ".TXT", 54)
        button("export:docly", ".DOCLY", 70)
    end

    local spacing = 6
    local total = -spacing

    for _, item in ipairs(items) do
        total = total + item.w + spacing
    end

    local x = pageX + pageWidth / 2 - total / 2

    for _, item in ipairs(items) do
        item.x = x
        item.y = 82
        item.h = 26

        x = x + item.w + spacing
    end

    return items
end

local function hitBar(document, activeTool, mx, my)
    for _, item in ipairs(buildBar(document, activeTool)) do
        if item.id and item.kind ~= "label"
        and mx >= item.x and mx <= item.x + item.w
        and my >= item.y and my <= item.y + item.h then
            return item.id
        end
    end

    return nil
end

-- Desenho --------------------------------------------------------------

local function drawSelection(lines, a, b, originX, originY)
    love.graphics.setColor(0.25, 0.5, 1, 0.28)

    for i, line in ipairs(lines) do
        local first = line.startIndex
        local n = #line.characters
        local last = first + n - 1

        local s = math.max(a, first)
        local e = math.min(b - 1, last)

        local x1, x2

        if s <= e then
            x1 = line.xs[s - first + 1]
            x2 = line.xs[e - first + 2]
        end

        -- Quebra de linha (\n) dentro da seleção
        if i < #lines and line.hardBreak
        and a <= last + 1 and b - 1 >= last + 1 then
            x1 = x1 or line.xs[n + 1]
            x2 = line.xs[n + 1] + 6
        end

        if x1 then
            love.graphics.rectangle(
                "fill",
                originX + x1,
                originY + line.y + 2,
                x2 - x1,
                line.height - 4
            )
        end
    end
end

-- Texto de uma página ou de uma caixa de texto
local function drawTextBlock(target, originX, originY, width, caret, placeholder)
    local lines = TextLayout.get(target, width)

    -- Marca-texto
    for _, line in ipairs(lines) do
        for _, run in ipairs(line.runs) do
            if run.hl then
                local color = HIGHLIGHTS[run.hl] or HIGHLIGHTS[1]

                love.graphics.setColor(color[1], color[2], color[3], color[4])

                love.graphics.rectangle(
                    "fill",
                    originX + run.x,
                    originY + line.y + 2,
                    run.width,
                    line.height - 4,
                    3,
                    3
                )
            end
        end
    end

    -- Seleção
    local a, b = nil, nil

    if caret then
        a, b = TextEdit.selection(target)
    end

    if a then
        drawSelection(lines, a, b, originX, originY)
    end

    -- Texto
    if target.content == "" then
        if placeholder then
            love.graphics.setFont(Fonts.ui)
            love.graphics.setColor(0.65, 0.65, 0.65)
            love.graphics.print(placeholder, originX, originY)
        end
    else
        love.graphics.setColor(0.05, 0.05, 0.05)

        for _, line in ipairs(lines) do
            local textY = originY + line.y + line.pad

            for _, run in ipairs(line.runs) do
                love.graphics.setFont(run.font)

                love.graphics.print(
                    run.text,
                    originX + run.x,
                    textY + line.ascent - run.font:getBaseline()
                )
            end
        end
    end

    -- Cursor (escondido quando há seleção)
    if caret and not a then
        local cursor = TextEdit.cursor(target)
        local line = lines[TextLayout.findLine(lines, cursor)]

        local cursorX = originX + line.xs[cursor - line.startIndex + 1]
        local cursorY = originY + line.y + line.pad

        love.graphics.setColor(0.05, 0.05, 0.05)
        love.graphics.setLineWidth(2)

        love.graphics.line(
            cursorX,
            cursorY,
            cursorX,
            cursorY + line.ascent + line.descent
        )
    end
end

local function drawShape(obj, sx, sy)
    local color = PALETTE[obj.color] or PALETTE[1]
    local w, h = obj.w, obj.h

    love.graphics.setLineWidth(3)
    love.graphics.setLineStyle("smooth")

    if obj.kind == "rect" then
        if obj.fill then
            love.graphics.setColor(color[1], color[2], color[3], 0.25)
            love.graphics.rectangle("fill", sx, sy, w, h, 4, 4)
        end

        love.graphics.setColor(color[1], color[2], color[3])
        love.graphics.rectangle("line", sx, sy, w, h, 4, 4)

    elseif obj.kind == "ellipse" then
        if w > 0 and h > 0 then
            if obj.fill then
                love.graphics.setColor(color[1], color[2], color[3], 0.25)
                love.graphics.ellipse("fill", sx + w / 2, sy + h / 2, w / 2, h / 2)
            end

            love.graphics.setColor(color[1], color[2], color[3])
            love.graphics.ellipse("line", sx + w / 2, sy + h / 2, w / 2, h / 2)
        end

    else
        love.graphics.setColor(color[1], color[2], color[3])

        if obj.flip then
            love.graphics.line(sx, sy + h, sx + w, sy)
        else
            love.graphics.line(sx, sy, sx + w, sy + h)
        end
    end
end

local function drawAttachment(obj, sx, sy)
    love.graphics.setColor(0.97, 0.97, 0.97)
    love.graphics.rectangle("fill", sx, sy, obj.w, obj.h, 10, 10)

    love.graphics.setColor(0.85, 0.85, 0.85)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", sx, sy, obj.w, obj.h, 10, 10)

    -- Ícone de documento
    love.graphics.setColor(0.25, 0.25, 0.25)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", sx + 14, sy + 11, 18, 26, 3, 3)
    love.graphics.line(sx + 18, sy + 19, sx + 28, sy + 19)
    love.graphics.line(sx + 18, sy + 25, sx + 28, sy + 25)
    love.graphics.line(sx + 18, sy + 31, sx + 28, sy + 31)

    love.graphics.setFont(Fonts.small)
    love.graphics.setColor(0.08, 0.08, 0.08)
    love.graphics.print(obj.label, sx + 44, sy + 8)

    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.print(obj.sizeText, sx + 44, sy + 27)
end

local function drawObjects(page, x, isCurrent, activeTool)
    if not page.objects then
        return
    end

    local chrome = isCurrent
        and not animation.active
        and (activeTool == nil or activeTool == "text")

    local canType = isCurrent
        and not animation.active
        and typingAllowed(activeTool)

    for _, obj in ipairs(page.objects) do
        local bx, by, bw, bh = objectBounds(obj)
        local sx, sy = x + bx, pageY + by

        if obj.type == "image" then
            if obj.image then
                love.graphics.setColor(1, 1, 1)

                love.graphics.draw(
                    obj.image,
                    sx,
                    sy,
                    0,
                    obj.w / obj.image:getWidth(),
                    obj.h / obj.image:getHeight()
                )
            else
                love.graphics.setColor(0.94, 0.94, 0.94)
                love.graphics.rectangle("fill", sx, sy, obj.w, obj.h, 6, 6)
                love.graphics.setColor(0.5, 0.2, 0.2)
                love.graphics.printf(
                    "Imagem indisponível",
                    sx + 8,
                    sy + 8,
                    math.max(1, obj.w - 16),
                    "center"
                )
            end

        elseif obj.type == "shape" then
            drawShape(obj, sx, sy)

        elseif obj.type == "attachment" then
            drawAttachment(obj, sx, sy)

        elseif obj.type == "textbox" then
            love.graphics.setColor(1, 1, 1, 0.92)
            love.graphics.rectangle("fill", sx, sy, bw, bh, 6, 6)

            local isFocused = canType and focus == obj

            drawTextBlock(
                obj,
                sx + boxPadding,
                sy + boxPadding,
                bw - boxPadding * 2,
                isFocused,
                isFocused and "Digite aqui" or nil
            )
        end

        if chrome and obj == selected then
            love.graphics.setColor(0.25, 0.5, 1)
            love.graphics.setLineWidth(1.5)
            love.graphics.rectangle("line", sx, sy, bw, bh)

            for _, handle in ipairs(getHandles(obj)) do
                local hx = x + handle.x
                local hy = pageY + handle.y

                love.graphics.setColor(1, 1, 1)
                love.graphics.rectangle("fill", hx - 4.5, hy - 4.5, 9, 9)

                love.graphics.setColor(0.25, 0.5, 1)
                love.graphics.setLineWidth(1.5)
                love.graphics.rectangle("line", hx - 4.5, hy - 4.5, 9, 9)
            end
        end
    end
end

local function drawPage(page, x, isCurrent, showContent, activeTool)
    love.graphics.setColor(1, 1, 1)

    love.graphics.rectangle(
        "fill",
        x,
        pageY,
        pageWidth,
        getPageHeight(),
        8,
        8
    )

    if not showContent then
        return
    end

    Draw.drawStrokes(page, x, pageY)

    local caret = isCurrent
        and not animation.active
        and typingAllowed(activeTool)
        and focus == nil

    drawTextBlock(
        page,
        x + textPaddingX,
        pageY + textPaddingTop,
        textWidth,
        caret,
        "Comece a escrever..."
    )

    drawObjects(page, x, isCurrent, activeTool)
end

-- Os ícones são desenhados com linhas (a fonte padrão
-- do LÖVE não tem os glifos ‹ › ←)
local function drawCircleButton(button, enabled)
    local x, y = button.x, button.y

    if enabled then
        love.graphics.setColor(1, 1, 1)
    else
        love.graphics.setColor(0.90, 0.90, 0.90)
    end

    love.graphics.circle("fill", x, y, buttonRadius)

    local tone = enabled and 0.08 or 0.55

    love.graphics.setColor(tone, tone, tone)
    love.graphics.setLineWidth(2.5)
    love.graphics.setLineStyle("smooth")

    if button.id == "prev" then
        love.graphics.line(x + 3, y - 7, x - 4, y, x + 3, y + 7)
    elseif button.id == "next" then
        love.graphics.line(x - 3, y - 7, x + 4, y, x - 3, y + 7)
    else
        love.graphics.line(x - 8, y, x + 8, y)
        love.graphics.line(x, y - 8, x, y + 8)
    end
end

local function drawBar(document, activeTool)
    local font = Fonts.small

    love.graphics.setFont(font)

    for _, item in ipairs(buildBar(document, activeTool)) do
        if item.kind == "swatch" then
            local cx = item.x + item.w / 2
            local cy = item.y + item.h / 2

            love.graphics.setColor(
                item.color[1], item.color[2], item.color[3]
            )
            love.graphics.circle("fill", cx, cy, 9)

            if item.active then
                love.graphics.setColor(0.1, 0.1, 0.1)
                love.graphics.setLineWidth(2)
                love.graphics.circle("line", cx, cy, 12)
            end

        elseif item.kind == "label" then
            local tone = item.dark and 0.08 or 0.4

            love.graphics.setColor(tone, tone, tone)

            love.graphics.printf(
                item.label,
                item.x,
                item.y + (item.h - font:getHeight()) / 2,
                item.w,
                "center"
            )

        else
            if item.active and item.id == "mark" then
                local color = HIGHLIGHTS[highlightColor]

                love.graphics.setColor(color[1], color[2], color[3])
            elseif item.active then
                love.graphics.setColor(0.82, 0.88, 1)
            else
                love.graphics.setColor(1, 1, 1)
            end

            love.graphics.rectangle(
                "fill", item.x, item.y, item.w, item.h, 8, 8
            )

            love.graphics.setColor(0.08, 0.08, 0.08)

            love.graphics.printf(
                item.label,
                item.x,
                item.y + (item.h - font:getHeight()) / 2,
                item.w,
                "center"
            )
        end
    end
end

-- Navegação ------------------------------------------------------------

local function startNavigation(document, direction)
    local newIndex = document.currentPage + direction

    if newIndex < 1 or newIndex > #document.pages then
        return
    end

    clearSelection(document)
    selecting = nil
    dragging = nil

    document.currentPage = newIndex
    animation.offset = direction * (pageWidth + gap)
    animation.active = true
end

local function createPageAndGo(document)
    clearSelection(document)
    selecting = nil
    dragging = nil

    document.currentPage = Documents.addPage(document)
    animation.offset = pageWidth + gap
    animation.active = true
end

-- Edição de texto ------------------------------------------------------

local function posToCursor(target, x, y)
    local lines = layoutOf(target)
    local originX, originY = geometry(target)
    local relativeY = y - originY
    local index = #lines

    for i, line in ipairs(lines) do
        if relativeY < line.y + line.height then
            index = i
            break
        end
    end

    return TextLayout.cursorFromX(lines[index], x - originX)
end

local function isWordCharacter(character)
    return character ~= nil
        and character ~= " "
        and character ~= "\n"
        and character ~= "\t"
end

local function selectWord(target, position)
    local _, characters = layoutOf(target)

    local c = position

    if not isWordCharacter(characters[c])
    and isWordCharacter(characters[c - 1]) then
        c = c - 1
    end

    if not isWordCharacter(characters[c]) then
        target.cursor = position
        target.anchor = nil
        return
    end

    local first = c

    while first > 1 and isWordCharacter(characters[first - 1]) do
        first = first - 1
    end

    local last = c

    while isWordCharacter(characters[last]) do
        last = last + 1
    end

    target.anchor = first
    target.cursor = last
end

local function resetTypingStyle(target)
    target.typeSize = nil
    target.typeMark = nil
end

-- Tenta inserir texto (substituindo a seleção, se houver).
-- Se estourar a altura, desfaz e retorna false.
local function tryInsert(ctx, text)
    local target = ctx.target
    local snapshot = TextEdit.snapshot(target)

    local cursor = TextEdit.cursor(target)
    local a, b = TextEdit.selection(target)

    local from, to = cursor, cursor
    local size, mark

    if a then
        from, to = a, b
        size, mark = target.sizes[a], target.marks[a]
    else
        size, mark = TextEdit.insertStyle(target)
    end

    local newCursor = TextEdit.replace(target, from, to, text, size, mark)

    local _, _, height = layoutOf(target)

    if height > ctx.maxHeight then
        TextEdit.restore(target, snapshot)
        return false
    end

    target.cursor = newCursor
    target.anchor = nil
    resetTypingStyle(target)

    return true
end

local function insertTyped(document, text)
    local ctx = getContext(document)

    if tryInsert(ctx, text) then
        return
    end

    -- Página cheia: se está escrevendo no fim, continua na próxima
    if not ctx.isPage then
        return
    end

    local page = ctx.target
    local atEnd = TextEdit.cursor(page) == TextEdit.length(page) + 1

    if atEnd and not TextEdit.selection(page) then
        local size, mark = TextEdit.insertStyle(page)

        createPageAndGo(document)

        local newPage = Documents.getCurrentPage(document)
        TextEdit.ensure(newPage)

        if text ~= "\n" then
            newPage.cursor = TextEdit.replace(newPage, 1, 1, text, size, mark)
        else
            newPage.cursor = 1
        end
    end
end

local function deleteRange(target, from, to)
    target.cursor = TextEdit.replace(target, from, to, "")
    target.anchor = nil
    resetTypingStyle(target)
end

local function copySelection(target)
    local a, b = TextEdit.selection(target)

    if a then
        love.system.setClipboardText(TextEdit.getText(target, a, b))
    end

    return a, b
end

local function paste(document)
    local ctx = getContext(document)
    local target = ctx.target

    local text = love.system.getClipboardText() or ""

    text = text:gsub("\r\n", "\n")
    text = text:gsub("\r", "\n")

    if text == "" or not utf8.len(text) then
        return
    end

    if tryInsert(ctx, text) then
        return
    end

    -- Não coube inteiro: insere o maior pedaço que cabe
    local characters = TextLayout.getCharacters(text)
    local low, high, best = 1, #characters - 1, 0

    while low <= high do
        local middle = math.floor((low + high) / 2)
        local snapshot = TextEdit.snapshot(target)

        local fits = tryInsert(
            ctx,
            table.concat(characters, "", 1, middle)
        )

        TextEdit.restore(target, snapshot)

        if fits then
            best = middle
            low = middle + 1
        else
            high = middle - 1
        end
    end

    if best > 0 then
        tryInsert(ctx, table.concat(characters, "", 1, best))
    end
end

-- Aplica formatação de texto (tamanho / marca-texto)
local function applyFormat(document, id)
    local ctx = getContext(document)
    local target = ctx.target

    TextEdit.ensure(target)

    local a, b = TextEdit.selection(target)

    if id == "bigger" or id == "smaller" then
        local direction = id == "bigger" and 1 or -1

        if a then
            local current = target.sizes[a]
            local new = TextEdit.stepSize(current, direction)

            if new ~= current then
                local snapshot = TextEdit.snapshot(target)

                TextEdit.setSize(target, a, b, new)

                local _, _, height = layoutOf(target)

                -- Se o texto maior não cabe, desfaz
                if height > ctx.maxHeight then
                    TextEdit.restore(target, snapshot)
                end
            end
        else
            local current = TextEdit.insertStyle(target)

            target.typeSize = TextEdit.stepSize(current, direction)
        end

    elseif id == "mark" then
        if a then
            local allMarked = true

            for i = a, b - 1 do
                if not target.marks[i] then
                    allMarked = false
                    break
                end
            end

            if allMarked then
                TextEdit.setMark(target, a, b, false)
            else
                TextEdit.setMark(target, a, b, highlightColor)
            end
        else
            local _, mark = TextEdit.insertStyle(target)

            if mark then
                target.typeMark = false
            else
                target.typeMark = highlightColor
            end
        end
    end
end

-- Aplica um clique da barra de opções
local function applyBar(id, document)
    local kind, value = id:match("^(%a+):(%w+)$")

    if kind == "export" then
        local defaultName = Documents.defaultName(document)
        local path, reason = FileDialog.save(value, defaultName)

        if not path then
            if reason ~= "cancelled" then
                showMessage("Não consegui abrir o seletor para exportar.")
            end

            return
        end

        local ok

        if value == "docly" then
            ok = Documents.exportDocly(document, path)
        else
            ok = Documents.exportTxt(document, path)
        end

        showMessage(ok and "Arquivo exportado com sucesso." or "Não consegui salvar o arquivo.")

    elseif kind == "pen" then
        penColor = tonumber(value)

    elseif kind == "shape" then
        shapeColor = tonumber(value)

        if selected and selected.type == "shape" then
            selected.color = shapeColor
        end

    elseif kind == "hl" then
        highlightColor = tonumber(value)

    elseif kind == "erase" then
        eraserSize = tonumber(value)

    elseif id == "clear" then
        Documents.getCurrentPage(document).drawings = nil

    elseif kind == "kind" then
        shapeKind = value

    elseif id == "fill" then
        if selected and selected.type == "shape" then
            selected.fill = not selected.fill
            shapeFill = selected.fill
        else
            shapeFill = not shapeFill
        end

    else
        applyFormat(document, id)
    end
end

-- Posiciona o cursor / começa uma seleção de texto no alvo
local function pointText(target, mx, my, isDouble)
    TextEdit.ensure(target)

    local position = posToCursor(target, mx, my)

    if isDouble then
        selectWord(target, position)
        selecting = nil
        lastClick.time = 0
    elseif shiftDown() then
        target.anchor = target.anchor or TextEdit.cursor(target)
        target.cursor = position
        selecting = target
    else
        target.cursor = position
        target.anchor = position
        selecting = target
    end

    resetTypingStyle(target)
end

-- Redimensiona um objeto arrastando uma das 8 alças.
-- Cantos de imagem mantêm a proporção (Shift solta); lados esticam.
local function resizeObject(d, px, py, pageHeight)
    local obj, handle = d.obj, d.handle

    local east = handle:find("e") ~= nil
    local west = handle:find("w") ~= nil
    local north = handle:find("n") ~= nil
    local south = handle:find("s") ~= nil

    local isImage = obj.type == "image"
    local minW = isBox(obj) and 80 or (isImage and 30 or 8)
    local minH = isImage and 20 or 8

    local dx, dy = px - d.px, py - d.py

    local left, top = d.x, d.y
    local right, bottom = d.x + d.w, d.y + d.h

    local isCorner = (east or west) and (north or south)

    if isImage and isCorner and not shiftDown() then
        -- Proporcional: o canto oposto fica parado
        local anchorX = west and right or left
        local anchorY = north and bottom or top

        local mouseX = (east and right or left) + dx
        local mouseY = (south and bottom or top) + dy

        local wanted = math.max(
            ((east and (mouseX - anchorX)) or (anchorX - mouseX)) / d.w,
            ((south and (mouseY - anchorY)) or (anchorY - mouseY)) / d.h
        )

        local maxScale = math.min(
            (east and (pageWidth - anchorX) or anchorX) / d.w,
            (south and (pageHeight - anchorY) or anchorY) / d.h
        )

        local minScale = math.max(minW / d.w, minH / d.h)
        local scale = math.max(minScale, math.min(wanted, maxScale))

        local w, h = d.w * scale, d.h * scale

        left = east and anchorX or anchorX - w
        top = south and anchorY or anchorY - h
        right = left + w
        bottom = top + h
    else
        -- Livre: cada lado se move sozinho
        if east then
            right = math.max(left + minW, math.min(right + dx, pageWidth))
        end

        if west then
            left = math.min(right - minW, math.max(left + dx, 0))
        end

        if south then
            bottom = math.max(top + minH, math.min(bottom + dy, pageHeight))
        end

        if north then
            top = math.min(bottom - minH, math.max(top + dy, 0))
        end
    end

    obj.x = left
    obj.w = right - left

    if not isBox(obj) then
        obj.y = top
        obj.h = bottom - top
    end
end

-- Arquivos -------------------------------------------------------------

local function formatSize(bytes)
    if not bytes then
        return "Arquivo"
    end

    if bytes < 1024 then
        return bytes .. " B"
    elseif bytes < 1024 * 1024 then
        return string.format("%.0f KB", bytes / 1024)
    end

    return string.format("%.1f MB", bytes / (1024 * 1024))
end

local function shortenName(name, maxWidth)
    local font = Fonts.small

    if font:getWidth(name) <= maxWidth then
        return name
    end

    while #name > 1 and font:getWidth(name .. "...") > maxWidth do
        name = name:sub(1, -2)
    end

    return name .. "..."
end

-- Cria uma imagem na folha a partir dos bytes do arquivo
local function addImage(document, bytes, name)
    local ok, image = pcall(function()
        local fileData = love.filesystem.newFileData(bytes, name)

        return love.graphics.newImage(love.image.newImageData(fileData))
    end)

    if not ok or not image then
        return false
    end

    local page = Documents.getCurrentPage(document)
    page.objects = page.objects or {}

    local iw, ih = image:getDimensions()
    local pageHeight = getPageHeight()

    local scale = math.min(
        pageWidth * 0.7 / iw,
        pageHeight * 0.5 / ih,
        1
    )

    local w, h = iw * scale, ih * scale
    local offset = (#page.objects % 5) * 20

    local obj = {
        type = "image",
        image = image,
        imageData = love.data.encode("string", "base64", bytes),
        imageName = name,
        ratio = ih / iw,
        w = w,
        h = h,
        x = clamp((pageWidth - w) / 2 + offset, 0, math.max(0, pageWidth - w)),
        y = clamp((pageHeight - h) / 2 + offset, 0, math.max(0, pageHeight - h))
    }

    clearSelection(document)
    table.insert(page.objects, obj)
    selected = obj
    Documents.markDirty()

    return true
end

local function addAttachment(document, path, name, size)
    local page = Documents.getCurrentPage(document)
    page.objects = page.objects or {}

    local w = math.min(230, pageWidth - 20)
    local offset = (#page.objects % 5) * 20

    local obj = {
        type = "attachment",
        path = path,
        w = w,
        h = 48,
        label = shortenName(name, w - 60),
        sizeText = formatSize(size),
        x = clamp(40 + offset, 0, math.max(0, pageWidth - w)),
        y = clamp(80 + offset, 0, math.max(0, getPageHeight() - 48))
    }

    clearSelection(document)
    table.insert(page.objects, obj)
    selected = obj
    Documents.markDirty()
end

-- Lê os bytes de um arquivo arrastado para a janela
local function readDropped(file)
    local ok, bytes = pcall(function()
        file:open("r")

        local content = file:read()

        file:close()

        return content
    end)

    if ok and bytes and #bytes > 0 then
        return bytes
    end

    pcall(file.close, file)

    local handle = io.open(file:getFilename(), "rb")

    if handle then
        local content = handle:read("*a")

        handle:close()

        return content
    end

    return nil
end

local function openFile(path)
    local normalized = path:gsub("\\", "/")

    if normalized:sub(1, 1) ~= "/" then
        normalized = "/" .. normalized
    end

    normalized = normalized:gsub(" ", "%%20")

    love.system.openURL("file://" .. normalized)
end

-- API ------------------------------------------------------------------

function Editor.load()
    love.keyboard.setTextInput(true)
    love.keyboard.setKeyRepeat(true)
end

function Editor.update(dt)
    if not animation.active then
        return
    end

    local speed = 12

    animation.offset = animation.offset * math.exp(-speed * dt)

    if math.abs(animation.offset) < 1 then
        animation.offset = 0
        animation.active = false
    end
end

function Editor.isAnimating()
    return animation.active
end

-- Precisa receber eventos de mouse mesmo sem clique (arrastando)
function Editor.wantsMouseMove()
    return Draw.isActive() or selecting ~= nil or dragging ~= nil or erasing
end

-- A ferramenta ativa deve voltar ao modo normal (ex.: após criar algo)
function Editor.takeToolReset()
    local value = toolReset

    toolReset = false

    return value
end

function Editor.reset()
    selected = nil
    focus = nil
    selecting = nil
    dragging = nil
    highlightDrag = false
    erasing = false
    lastErase = nil
    toolReset = false
    lastTool = nil
    message = nil
end

-- Esc: primeiro tira a seleção; só depois sai do documento
function Editor.escape(document)
    if selected or focus then
        clearSelection(document)
        return true
    end

    return false
end

function Editor.hitBack(x, y)
    return x >= 20 and x <= 120 and y >= 15 and y <= 65
end

-- Tipo de cursor do mouse para a posição (x, y)
function Editor.cursorAt(x, y, activeTool, document)
    if Draw.isActive() then
        return "crosshair"
    end

    if erasing then
        return "eraser:" .. ERASER_RADII[eraserSize]
    end

    if dragging then
        if dragging.mode == "move" then
            return "sizeall"
        elseif dragging.mode == "resize" then
            return HANDLE_CURSORS[dragging.handle] or "sizenwse"
        end

        return "crosshair"
    end

    if selecting then
        return "ibeam"
    end

    if animation.active then
        return "arrow"
    end

    updateLayout()

    if hitButton(x, y) or hitBar(document, activeTool, x, y) then
        return "hand"
    end

    if not isInsidePage(x, y) then
        return "arrow"
    end

    if activeTool == "draw" or activeTool == "shape" then
        return "crosshair"
    end

    if activeTool == "eraser" then
        return "eraser:" .. ERASER_RADII[eraserSize]
    end

    if activeTool == "image" or activeTool == "attachment" then
        return "arrow"
    end

    if activeTool == "highlight" then
        return "ibeam"
    end

    local page = Documents.getCurrentPage(document)
    local px, py = x - pageX, y - pageY

    local handle = handleAt(selected, px, py)

    if handle then
        return HANDLE_CURSORS[handle]
    end

    local obj = hitObject(page, px, py)

    if obj then
        if isBox(obj) then
            return isInsideBoxText(obj, px, py) and "ibeam" or "sizeall"
        elseif obj.type == "attachment" then
            return "hand"
        end

        return "sizeall"
    end

    return "ibeam"
end

function Editor.draw(document, activeTool)
    local width = love.graphics.getWidth()
    local height = love.graphics.getHeight()

    updateLayout()

    -- Ao trocar de ferramenta, larga a seleção (exceto texto/normal)
    if activeTool ~= lastTool then
        lastTool = activeTool

        if activeTool ~= nil and activeTool ~= "text" then
            clearSelection(document)
        end
    end

    love.graphics.clear(0.94, 0.94, 0.94)
    love.graphics.setFont(Fonts.ui)

    -- Barra superior
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, width, 75)

    love.graphics.setColor(0.05, 0.05, 0.05)
    love.graphics.setLineWidth(2)
    love.graphics.line(30, 38, 48, 38)
    love.graphics.line(37, 31, 30, 38, 37, 45)
    love.graphics.print("Voltar", 58, 28)

    love.graphics.printf(document.title, 0, 28, width, "center")

    local current = document.currentPage

    -- Barra de opções
    if not animation.active then
        drawBar(document, activeTool)
    end

    -- Área das páginas
    love.graphics.setScissor(
        pageX - peek,
        pageY,
        pageWidth + peek * 2,
        height - pageY - 35
    )

    local step = pageWidth + gap

    for i = current - 1, current + 1 do
        local page = document.pages[i]

        if page then
            local x = pageX + (i - current) * step + animation.offset

            local isCurrent = i == current
            local showContent = isCurrent or animation.active

            drawPage(page, x, isCurrent, showContent, activeTool)
        end
    end

    love.graphics.setScissor()

    -- Controles laterais
    for _, button in ipairs(getButtons()) do
        local enabled = true

        if button.id == "prev" then
            enabled = current > 1
        elseif button.id == "next" then
            enabled = current < #document.pages
        end

        drawCircleButton(button, enabled)
    end

    -- Indicador de página
    love.graphics.setFont(Fonts.ui)
    love.graphics.setColor(0.35, 0.35, 0.35)

    love.graphics.printf(
        "Página " .. current .. " de " .. #document.pages,
        0,
        height - 28,
        width,
        "center"
    )
end

function Editor.mousepressed(x, y, button, document, activeTool)
    if button ~= 1 or animation.active then
        return
    end

    updateLayout()
    message = nil

    local hit = hitButton(x, y)

    if hit == "prev" then
        startNavigation(document, -1)
        return
    elseif hit == "next" then
        startNavigation(document, 1)
        return
    elseif hit == "add" then
        createPageAndGo(document)
        return
    end

    local barId = hitBar(document, activeTool, x, y)

    if barId then
        applyBar(barId, document)
        return
    end

    if not isInsidePage(x, y) then
        return
    end

    local page = Documents.getCurrentPage(document)
    local px, py = x - pageX, y - pageY

    local now = love.timer.getTime()

    local isDouble = now - lastClick.time < 0.4
        and math.abs(x - lastClick.x) < 5
        and math.abs(y - lastClick.y) < 5

    lastClick = { time = now, x = x, y = y }

    -- Rabisco
    if activeTool == "draw" then
        Draw.begin(
            page,
            { w = pageWidth, h = getPageHeight() },
            px,
            py,
            PALETTE[penColor]
        )

        return
    end

    -- Borracha
    if activeTool == "eraser" then
        erasing = true
        lastErase = { px, py }

        Draw.erase(page, px, py, ERASER_RADII[eraserSize])

        return
    end

    -- Formas: arrastar para criar
    if activeTool == "shape" then
        local obj = {
            type = "shape",
            kind = shapeKind,
            color = shapeColor,
            fill = shapeFill,
            x = px,
            y = py,
            w = 0,
            h = 0,
            flip = false
        }

        page.objects = page.objects or {}
        table.insert(page.objects, obj)

        dragging = { mode = "create", obj = obj, startX = px, startY = py }

        return
    end

    -- Imagem / anexo: abre o seletor de arquivos
    if activeTool == "image" or activeTool == "attachment" then
        Editor.pickFile(document, activeTool)
        return
    end

    -- Marca-texto: arrastar sobre o texto
    if activeTool == "highlight" then
        local target = page
        local obj = hitObject(page, px, py)

        if obj and isBox(obj) then
            target = obj
        end

        pointText(target, x, y, false)
        highlightDrag = true

        return
    end

    -- Modo normal (e ferramenta de texto) -------------------------------

    -- Alça de redimensionar do objeto selecionado
    local handle = handleAt(selected, px, py)

    if handle then
        local bx, by, bw, bh = objectBounds(selected)

        dragging = {
            mode = "resize",
            obj = selected,
            handle = handle,
            px = px,
            py = py,
            x = bx,
            y = by,
            w = bw,
            h = bh
        }

        return
    end

    local obj = hitObject(page, px, py)

    if obj then
        selected = obj
        page.anchor = nil

        if isBox(obj) then
            focus = obj

            if isInsideBoxText(obj, px, py) then
                pointText(obj, x, y, isDouble)
            else
                dragging = {
                    mode = "move",
                    obj = obj,
                    dx = px - obj.x,
                    dy = py - obj.y
                }
            end
        else
            focus = nil

            if obj.type == "attachment" and isDouble then
                openFile(obj.path)
                lastClick.time = 0
            else
                dragging = {
                    mode = "move",
                    obj = obj,
                    dx = px - obj.x,
                    dy = py - obj.y
                }
            end
        end

        return
    end

    -- Ferramenta de texto: cria uma caixa onde clicou
    if activeTool == "text" then
        clearSelection(document)

        local box = {
            type = "textbox",
            x = clamp(px, 0, math.max(0, pageWidth - 224)),
            y = clamp(py, 0, math.max(0, getPageHeight() - 60)),
            w = 220,
            content = "",
            cursor = 1
        }

        page.objects = page.objects or {}
        table.insert(page.objects, box)

        selected = box
        focus = box
        toolReset = true

        return
    end

    -- Clicou no vazio: volta para o texto da página
    clearSelection(document)
    pointText(page, x, y, isDouble)
end

function Editor.mousemoved(x, y, dx, dy, document)
    updateLayout()

    if Draw.isActive() then
        Draw.move(x - pageX, y - pageY)
        return
    end

    if erasing then
        local page = Documents.getCurrentPage(document)
        local px, py = x - pageX, y - pageY
        local radius = ERASER_RADII[eraserSize]

        local dx, dy = px - lastErase[1], py - lastErase[2]

        -- Apaga ao longo do caminho para não pular traços quando o mouse é rápido
        local steps = math.max(
            1,
            math.ceil(math.sqrt(dx * dx + dy * dy) / (radius / 2))
        )

        for i = 1, steps do
            Draw.erase(
                page,
                lastErase[1] + dx * i / steps,
                lastErase[2] + dy * i / steps,
                radius
            )
        end

        lastErase = { px, py }

        return
    end

    if dragging then
        local d = dragging
        local obj = d.obj
        local px, py = x - pageX, y - pageY
        local pageHeight = getPageHeight()

        if d.mode == "create" then
            local cx = clamp(px, 0, pageWidth)
            local cy = clamp(py, 0, pageHeight)

            obj.x = math.min(d.startX, cx)
            obj.y = math.min(d.startY, cy)
            obj.w = math.abs(cx - d.startX)
            obj.h = math.abs(cy - d.startY)
            obj.flip = (cx - d.startX) * (cy - d.startY) < 0

        elseif d.mode == "move" then
            local _, _, w, h = objectBounds(obj)

            obj.x = clamp(px - d.dx, 0, math.max(0, pageWidth - w))
            obj.y = clamp(py - d.dy, 0, math.max(0, pageHeight - h))

        elseif d.mode == "resize" then
            resizeObject(d, px, py, pageHeight)
        end

        return
    end

    if selecting then
        selecting.cursor = posToCursor(selecting, x, y)
    end
end

function Editor.mousereleased(x, y, button, document)
    if button ~= 1 then
        return
    end

    Draw.finish()
    erasing = false
    lastErase = nil
    Documents.markDirty()

    -- Forma recém-criada
    if dragging and dragging.mode == "create" then
        local obj = dragging.obj

        -- Clique sem arrastar: forma com tamanho padrão
        if obj.w < 6 and obj.h < 6 then
            obj.w = math.min(140, pageWidth - obj.x)
            obj.h = math.min(100, getPageHeight() - obj.y)
            obj.flip = false
        end

        selected = obj
        toolReset = true
    end

    dragging = nil

    -- Marca-texto: aplica ao soltar o mouse
    if highlightDrag and selecting then
        local target = selecting
        local a, b = TextEdit.selection(target)

        if a then
            local same = true

            for i = a, b - 1 do
                if target.marks[i] ~= highlightColor then
                    same = false
                    break
                end
            end

            if same then
                TextEdit.setMark(target, a, b, false)
            else
                TextEdit.setMark(target, a, b, highlightColor)
            end

            target.anchor = nil
        end
    end

    highlightDrag = false
    selecting = nil
end

-- Abre a janela de escolher arquivo e coloca o resultado na folha
function Editor.pickFile(document, kind)
    if animation.active then
        return
    end

    updateLayout()

    local result, reason = FileDialog.pick(kind)

    if not result then
        if reason == "cancelled" then
            toolReset = true
        else
            showMessage("Não consegui abrir o seletor. Arraste o arquivo para a janela.")
        end

        return
    end

    if kind == "image" then
        if addImage(document, result.data, result.name) then
            toolReset = true
        else
            showMessage("Não consegui abrir essa imagem (use PNG, JPG, BMP ou TGA).")
            toolReset = true
        end
    else
        addAttachment(document, result.path, result.name, result.size)
        toolReset = true
    end
end

-- Arquivo arrastado para a janela: vira imagem ou anexo
function Editor.filedropped(file, document, activeTool)
    if animation.active then
        return
    end

    updateLayout()

    local path = file:getFilename()
    local name = path:match("([^/\\]+)$") or path
    local extension = (name:match("%.([^.]+)$") or ""):lower()

    local wantsImage = activeTool == "image"
        or (activeTool ~= "attachment" and IMAGE_EXTENSIONS[extension])

    if wantsImage then
        local bytes = readDropped(file)

        if bytes and addImage(document, bytes, name) then
            toolReset = true
            return
        end

        if activeTool == "image" then
            showMessage("Não consegui abrir essa imagem (use PNG, JPG, BMP ou TGA).")
            toolReset = true
            return
        end
    end

    local ok, size = pcall(file.getSize, file)

    addAttachment(document, path, name, ok and size or nil)
    toolReset = true
end

function Editor.textinput(text, document, activeTool)
    if animation.active or not typingAllowed(activeTool) or ctrlDown() then
        return
    end

    updateLayout()
    insertTyped(document, text)
    Documents.markDirty()
end

function Editor.keypressed(key, document, activeTool)
    if animation.active then
        return
    end

    updateLayout()
    Documents.markDirty()

    -- Remove o objeto selecionado
    if (key == "delete" or key == "backspace")
    and selected and not focus
    and (activeTool == nil or activeTool == "text") then
        removeObject(Documents.getCurrentPage(document), selected)
        selected = nil
        return
    end

    if not typingAllowed(activeTool) then
        return
    end

    local ctx = getContext(document)
    local target = ctx.target

    TextEdit.ensure(target)

    local lines, characters = layoutOf(target)
    local count = #characters
    local cursor = TextEdit.cursor(target)
    local shift = shiftDown()

    -- Atalhos com Ctrl
    if ctrlDown() then
        if key == "a" then
            target.anchor = 1
            target.cursor = count + 1
            resetTypingStyle(target)

        elseif key == "c" then
            copySelection(target)

        elseif key == "x" then
            local a, b = copySelection(target)

            if a then
                deleteRange(target, a, b)
            end

        elseif key == "v" then
            paste(document)

        elseif key == "=" or key == "+" or key == "kp+" then
            applyFormat(document, "bigger")

        elseif key == "-" or key == "kp-" then
            applyFormat(document, "smaller")
        end

        return
    end

    -- Apagar numa caixa de texto vazia remove a caixa
    if not ctx.isPage and count == 0
    and (key == "backspace" or key == "delete") then
        clearSelection(document)
        return
    end

    local function moveTo(newCursor)
        if shift then
            target.anchor = target.anchor or cursor
        else
            target.anchor = nil
        end

        target.cursor = newCursor
        resetTypingStyle(target)
    end

    local a, b = TextEdit.selection(target)

    if key == "backspace" then
        if a then
            deleteRange(target, a, b)
        elseif cursor > 1 then
            deleteRange(target, cursor - 1, cursor)
        end

    elseif key == "delete" then
        if a then
            deleteRange(target, a, b)
        elseif cursor <= count then
            deleteRange(target, cursor, cursor + 1)
        end

    elseif key == "left" then
        if a and not shift then
            moveTo(a)
        else
            moveTo(math.max(1, cursor - 1))
        end

    elseif key == "right" then
        if a and not shift then
            moveTo(b)
        else
            moveTo(math.min(count + 1, cursor + 1))
        end

    elseif key == "up" or key == "down" then
        local index = TextLayout.findLine(lines, cursor)
        local line = lines[index]
        local other = lines[index + (key == "up" and -1 or 1)]

        if other then
            moveTo(TextLayout.cursorFromX(
                other,
                line.xs[cursor - line.startIndex + 1]
            ))
        else
            moveTo(key == "up" and 1 or count + 1)
        end

    elseif key == "home" then
        local line = lines[TextLayout.findLine(lines, cursor)]

        moveTo(line.startIndex)

    elseif key == "end" then
        local line = lines[TextLayout.findLine(lines, cursor)]

        moveTo(line.startIndex + TextLayout.maxOffset(line))

    elseif key == "return" or key == "kpenter" then
        insertTyped(document, "\n")
    end
end

return Editor