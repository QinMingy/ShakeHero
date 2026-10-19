-- 发布状态总开关：发布前只需检查这个文件。
--
-- true  = 发布模式：隐藏并禁用全部 GM／开发调试入口，按 G 也无法打开。
--         包括物品 GM、表现 GM、物理调试菜单及验收调试访问入口。
-- false = 开发模式：允许使用现有 GM；按 G 仍只负责临时显示／隐藏。
--
-- 注意：Lua 布尔值必须写成小写 true / false，不能写 TRUE / FALSE 或字符串。
-- 这是最高优先级的权限开关，独立于 machineSkin.developerVisible（G 键显隐状态）。
-- G 键、菜单、读档、新局及教程均不得修改或绕过它；不会保存到玩家存档。
-- 修改后请重新构建并重新启动预览／游戏，确保发布产物使用新配置。
-- 新增 GM 功能时，界面入口及实际执行入口都必须检查此配置，不能只隐藏按钮。
-- 防误配置：调用方只有在本值明确为 false 时才允许 GM；nil 等异常值也禁用。
local PublishConfig = {
    PUBLISH_MODE = true, -- 发布填 true；需要开发调试时改为 false。
}

return PublishConfig
