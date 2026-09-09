-- Virtual-key display names for menu rebinding.

local VK_NAMES = {
    [0x08] = "Backspace",
    [0x09] = "Tab",
    [0x0D] = "Enter",
    [0x10] = "Shift",
    [0x11] = "Ctrl",
    [0x12] = "Alt",
    [0x1B] = "Esc",
    [0x20] = "Space",
    [0x25] = "Left",
    [0x26] = "Up",
    [0x27] = "Right",
    [0x28] = "Down",
    [0x2D] = "Insert",
    [0x2E] = "Delete",
    [0x70] = "F1",
    [0x71] = "F2",
    [0x72] = "F3",
    [0x73] = "F4",
    [0x74] = "F5",
    [0x75] = "F6",
    [0x76] = "F7",
    [0x77] = "F8",
    [0x78] = "F9",
    [0x79] = "F10",
    [0x7A] = "F11",
    [0x7B] = "F12",
    [0xC0] = "~",
}

local function vk_name(vk)
    if VK_NAMES[vk] then
        return VK_NAMES[vk]
    end
    if vk >= 0x30 and vk <= 0x39 then
        return string.char(vk)
    end
    if vk >= 0x41 and vk <= 0x5A then
        return string.char(vk)
    end
    return string.format("VK 0x%02X", vk)
end

return {
    VK_NAMES = VK_NAMES,
    vk_name = vk_name,
}
