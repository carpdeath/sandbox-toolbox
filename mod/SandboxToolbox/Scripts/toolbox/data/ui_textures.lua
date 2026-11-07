local widgets = "/Game/ManorLords/UI/Widgets/Widgets_Inventory/Assets/"

local function path(name) return widgets .. name .. "." .. name end
local fonts = "/Game/UWG/fonts/"

return {
    font_body = fonts .. "CombinedFont_SemiBold.CombinedFont_SemiBold",
    font_heading = fonts .. "CombinedFont_Mikadan.CombinedFont_Mikadan",
    paper = path("MI_UI_InventoryFrame"),
    paper_fallback = path("ui_paper_texture_inventory_background_paper_no_frame_v01_512"),
    band = path("MI_UI_InventoryHeaderBG"),
    frame = path("ui_inventory_background_manuscript_style_ornaments_with_gold_frame_v01_512"),
    header = path("M_UI_InventoryHeaderPattern"),
    header_fallback = path("ui_pattern_blue_03_tiled_texture_256"),
    tile = path("square_dark_brown_with_white_outline_02_kopia"),
    button_normal = path("MI_UI_InventoryCastleButton"),
    button_hover = path("MI_UI_InventoryCastleButton_Hover"),
    button_pressed = path("MI_UI_InventoryCastleButton_Pressed"),
    button_disabled = path("MI_UI_InventoryCastleButton_Disabled"),
    button_tex_normal = path("ui_open_castle_planner_button_normal"),
    button_tex_hover = path("ui_open_castle_planner_button_hover"),
    button_tex_pressed = path("ui_open_castle_planner_button_pressed"),
    button_tex_disabled = path("ui_open_castle_planner_button_inactive"),
    ribbon_title = path("MI_UI_LivestockNameRibbon"),
    ribbon_title_fallback = path("ui_simple_ribbon_label_01"),
    ribbon_field = path("MI_UI_FamilyNameRibbon"),
    ribbon_field_fallback = path("ui_simple_ribbon_label_02"),
    tab = path("MI_UI_InventoryTab"),
    tab_hover = path("MI_UI_InventoryTab_Hovered"),
    tab_selected = path("MI_UI_InventoryTab_Selected"),
    tab_fallback = path("ui_paper_tab_01_inactive"),
    tab_selected_fallback = path("ui_paper_tab_01_active"),
    icon_close = "/Game/ManorLords/UI/Icons/Flat/cancel.Cancel",
    exit_normal = path("button_small_red_sguare_01_normal"),
    exit_hover = path("button_small_red_sguare_01_hover"),
    exit_pressed = path("button_small_red_sguare_01_pressed"),
    checkbox_on = "/Game/UI/Assets/MI_UI_Checkbox.MI_UI_Checkbox",
    checkbox_off = "/Game/UI/Assets/MI_UI_Checkbox_Empty.MI_UI_Checkbox_Empty",
}
