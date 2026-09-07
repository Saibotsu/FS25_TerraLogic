-- Player-facing numeric formatting only. Never use for keys, saves, CSV or wire data.
TerraLogicI18n = {}

function TerraLogicI18n.format(pattern, ...)
    if g_languageShort ~= "de" then return string.format(pattern, ...) end

    local args={...}
    local count=select("#", ...)
    local index=0
    -- Parse placeholders, not the rendered text: a vehicle name passed as %s,
    -- a URL or a version number must never have its punctuation rewritten.
    local localized=pattern:gsub("%%[-+ #0]*%d*%.?%d*[cdiouxXeEfgGqs%%]", function(spec)
        if spec=="%%" then return spec end
        index=index+1
        local conversion=spec:sub(-1)
        if conversion:find("[eEfgG]") then
            local value=args[index]
            local rendered=string.format(spec, value)
            local number=tonumber(value)
            if number and number==number and number~=math.huge and number~=-math.huge then
                rendered=rendered:gsub("%.", ",", 1)
            end
            args[index]=rendered
            return "%s"
        end
        return spec
    end)
    return string.format(localized, unpack(args, 1, count))
end
