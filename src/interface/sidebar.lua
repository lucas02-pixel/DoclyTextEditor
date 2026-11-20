local Sidebar = {}

local tools = {
    "draw",
    "eraser",
    "image",
    "shape",
    "text",
    "highlight",
    "attachment"
}

-- Ferramentas que já podem ser selecionadas
local implemented = {
    draw = true,
    eraser = true,
    image = true,
    shape = true,
    text = true,
    highlight = true,
    attachment = true
}

Sidebar.activeTool = nil

local x = 96
local startY = 140
local buttonSize = 44
local gap = 10

local function drawIcon(tool, cx, cy, enabled)
    local tone = enabled and 0.12 or 0.65

    love.graphics.setColor(tone, tone, tone)
    love.graphics.setLineWidth(2)

    if tool == "draw" then
        love.graphics.line(cx - 9, cy + 9, cx + 9, cy - 9)
        love.graphics.line(cx + 9, cy - 9, cx + 12, cy - 6)
        love.graphics.line(cx - 9, cy + 9, cx - 5, cy + 8)

    elseif tool == "eraser" then
        -- Borracha inclinada com uma divisão no meio
        love.graphics.polygon(
            "line",
            cx + 12, cy - 2,
            cx + 6, cy - 11,
            cx - 12, cy + 2,
            cx - 6, cy + 11
        )
        love.graphics.line(cx + 3, cy + 3, cx - 1, cy - 6)
        love.graphics.line(cx - 4, cy + 14, cx + 12, cy + 14)

    elseif tool == "image" then
        love.graphics.rectangle("line", cx - 12, cy - 10, 24, 20)
        love.graphics.circle("line", cx + 5, cy - 5, 3)
        love.graphics.line(cx - 10, cy + 7, cx - 2, cy - 1)
        love.graphics.line(cx - 2, cy - 1, cx + 5, cy + 7)
        love.graphics.line(cx + 5, cy + 7, cx + 10, cy + 2)

    elseif tool == "shape" then
        love.graphics.rectangle("line", cx - 12, cy - 10, 10, 10)
        love.graphics.circle("line", cx + 6, cy + 5, 7)

    elseif tool == "text" then
        love.graphics.line(cx - 10, cy - 9, cx + 10, cy - 9)
        love.graphics.line(cx, cy - 9, cx, cy + 10)
        love.graphics.line(cx - 7, cy + 10, cx + 7, cy + 10)

    elseif tool == "highlight" then
        love.graphics.line(cx - 12, cy - 5, cx + 12, cy - 5)
        love.graphics.line(cx - 12, cy + 2, cx + 12, cy + 2)
        love.graphics.line(cx - 12, cy + 9, cx + 12, cy + 9)

    elseif tool == "attachment" then
        love.graphics.rectangle("line", cx - 8, cy - 11, 16, 22)
        love.graphics.line(cx - 4, cy - 5, cx + 4, cy - 5)
        love.graphics.line(cx - 4, cy, cx + 4, cy)
        love.graphics.line(cx - 4, cy + 5, cx + 4, cy + 5)
    end
end

function Sidebar.draw()
    local height = #tools * (buttonSize + gap) + gap

    love.graphics.setColor(1, 1, 1)

    love.graphics.rectangle(
        "fill",
        x,
        startY,
        buttonSize + 12,
        height,
        12,
        12
    )

    for i, tool in ipairs(tools) do
        local y = startY + gap + (i - 1) * (buttonSize + gap)

        if Sidebar.activeTool == tool then
            love.graphics.setColor(0.85, 0.85, 0.85)
        else
            love.graphics.setColor(0.96, 0.96, 0.96)
        end

        love.graphics.rectangle(
            "fill",
            x + 6,
            y,
            buttonSize,
            buttonSize,
            10,
            10
        )

        drawIcon(
            tool,
            x + 6 + buttonSize / 2,
            y + buttonSize / 2,
            implemented[tool]
        )
    end
end

function Sidebar.mousepressed(mx, my, button)
    if button ~= 1 then
        return false
    end

    for i, tool in ipairs(tools) do
        local y = startY + gap + (i - 1) * (buttonSize + gap)

        if mx >= x + 6 and mx <= x + 6 + buttonSize
        and my >= y and my <= y + buttonSize then

            if implemented[tool] then
                -- Clicar na ferramenta ativa desativa (volta ao modo texto)
                if Sidebar.activeTool == tool then
                    Sidebar.activeTool = nil
                else
                    Sidebar.activeTool = tool
                end
            end

            return true
        end
    end

    return false
end

-- true se o mouse está sobre algum botão de ferramenta
function Sidebar.hit(mx, my)
    for i = 1, #tools do
        local y = startY + gap + (i - 1) * (buttonSize + gap)

        if mx >= x + 6 and mx <= x + 6 + buttonSize
        and my >= y and my <= y + buttonSize then
            return true
        end
    end

    return false
end

return Sidebar