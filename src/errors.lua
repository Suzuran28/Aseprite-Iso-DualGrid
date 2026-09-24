local messages = {
  ALIGNMENT_INVALID="对齐方式必须为居中或顶部。",
  OFFSET_NOT_INTEGER="偏移量必须是整数。",
  SIZE_NOT_INTEGER="基础尺寸必须是整数。",
  SIZE_NOT_EVEN="基础尺寸必须是偶数。",
  SIZE_OUT_OF_RANGE="基础尺寸必须在 16 到 1024 之间。",
  ELEVATION_NOT_INTEGER="立面高度必须是整数。",
  ELEVATION_NEGATIVE="立面高度不能小于 0。",
  FIXED_OVERFLOW="固定模式下，center 对齐的立面高度不能超过尺寸的四分之一，top 对齐不能超过一半。",
  MODE_INVALID="模式必须为固定或扩展。",
  LAYOUT_INVALID="图集布局必须为横排或方阵。",
  ATLAS_SIDE_LIMIT="图集任一边不能超过 16384 像素。",
  ATLAS_PIXEL_LIMIT="图集总像素数不能超过 16777216。",
  API_TOO_OLD="当前 Aseprite API 低于 21。",
  UI_UNAVAILABLE="当前运行环境没有可用界面。",
  NO_ACTIVE_SPRITE="没有可导出的活动文档。",
  FRAME_COUNT_INVALID="模板文档必须且只能包含一个帧。",
  ARTWORK_GROUP_INVALID="模板缺少唯一的顶层 Artwork 组。",
  GUIDES_GROUP_INVALID="模板缺少唯一的顶层 Guides 组。",
  SPRITE_CREATE_FAILED="无法创建模板文档。",
  PATH_REQUIRED="请选择 PNG 导出路径。",
  SAVE_FAILED="PNG 保存失败。"
}

return {
  message=function(code) return assert(messages[code], "unknown error code") end
}
