-- Ferramenta de rabisco.
-- Os traços ficam em page.drawings; cada traço guarda suas
-- coordenadas numa lista plana { x1, y1, x2, y2, ... } relativa à página.

local Draw = {}

local DEFAULT_COLOR = { 0.05, 0.05, 0.05 }

local activeStroke = nil
local area = nil

function Draw.isActive()
    return activeStroke ~= nil
end

-- pageArea = { w = largura da página, h = altura da página }
-- x, y já relativos ao canto da página; color = { r, g, b }
function Draw.begin(page, pageArea, x, y, color)
    page.drawings = page.drawings or {}

    activeStroke = { coords = {}, color = color or DEFAULT_COLOR }
    area = pageArea

    table.insert(page.drawings, activeStroke)

    Draw.move(x, y)
end

function Draw.move(x, y)
    if not activeStroke then
        return
    end

    -- Limita o desenho aos limites da folha
    x = math.max(0, math.min(x, area.w))
    y = math.max(0, math.min(y, area.h))

    local coords = activeStroke.coords
    local n = #coords

    -- Ignora pontos repetidos
    if n >= 2 and coords[n - 1] == x and coords[n] == y then
        return
    end

    coords[n + 1] = x
    coords[n + 2] = y
end

function Draw.finish()
    activeStroke = nil
    area = nil
end

function Draw.drawStrokes(page, originX, originY)
    if not page.drawings then
        return
    end

    love.graphics.setLineWidth(3)
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin("bevel")

    love.graphics.push()
    love.graphics.translate(originX, originY)

    for _, stroke in ipairs(page.drawings) do
        local coords = stroke.coords
        local color = stroke.color or DEFAULT_COLOR

        love.graphics.setColor(color[1], color[2], color[3])

        if #coords == 2 then
            love.graphics.circle("fill", coords[1], coords[2], 1.5)
        elseif #coords >= 4 then
            love.graphics.line(coords)
        end
    end

    love.graphics.pop()
end

-- Borracha -------------------------------------------------------------

-- Remove de um traço a parte que está dentro do círculo (cx, cy, r).
-- Retorna nil se o traço não foi tocado; senão, a lista de pedaços que sobraram.
local function eraseFromStroke(stroke, cx, cy, r)
    local c = stroke.coords
    local n = #c
    local r2 = r * r

    -- Ponto isolado
    if n == 2 then
        local dx, dy = c[1] - cx, c[2] - cy

        if dx * dx + dy * dy <= r2 then
            return {}
        end

        return nil
    end

    local pieces = {}
    local current = nil
    local continuing = false
    local touched = false

    for i = 1, n - 3, 2 do
        local ax, ay, bx, by = c[i], c[i + 1], c[i + 2], c[i + 3]
        local dx, dy = bx - ax, by - ay
        local fx, fy = ax - cx, ay - cy

        -- Onde o segmento a→b entra e sai do círculo (t de 0 a 1)
        local a = dx * dx + dy * dy
        local b = fx * dx + fy * dy
        local k = fx * fx + fy * fy - r2

        local enter, leave = nil, nil

        if a > 0 then
            local disc = b * b - a * k

            if disc >= 0 then
                local root = math.sqrt(disc)
                local t0 = (-b - root) / a
                local t1 = (-b + root) / a

                if t1 >= 0 and t0 <= 1 then
                    enter = math.max(t0, 0)
                    leave = math.min(t1, 1)
                end
            end
        end

        -- Partes do segmento que continuam: [de, até]
        local keep = {}

        if not enter then
            keep[1] = { 0, 1 }
        else
            touched = true

            if enter > 0 then
                keep[#keep + 1] = { 0, enter }
            end

            if leave < 1 then
                keep[#keep + 1] = { leave, 1 }
            end
        end

        for _, part in ipairs(keep) do
            local from, to = part[1], part[2]

            local ex = ax + dx * to
            local ey = ay + dy * to

            if current and continuing and from == 0 then
                current[#current + 1] = ex
                current[#current + 1] = ey
            else
                current = { ax + dx * from, ay + dy * from, ex, ey }

                pieces[#pieces + 1] = { coords = current, color = stroke.color }
            end

            continuing = to == 1
        end

        if #keep == 0 then
            continuing = false
        end
    end

    if not touched then
        return nil
    end

    return pieces
end

-- Apaga em volta do ponto (x, y) da página. Retorna true se mudou algo.
function Draw.erase(page, x, y, radius)
    local drawings = page.drawings

    if not drawings or #drawings == 0 then
        return false
    end

    local result = {}
    local changed = false

    for _, stroke in ipairs(drawings) do
        local pieces = eraseFromStroke(stroke, x, y, radius)

        if pieces then
            changed = true

            for _, piece in ipairs(pieces) do
                result[#result + 1] = piece
            end
        else
            result[#result + 1] = stroke
        end
    end

    if changed then
        page.drawings = result
    end

    return changed
end

return Draw