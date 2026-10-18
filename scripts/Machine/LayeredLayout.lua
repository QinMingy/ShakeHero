-- One 402x874 coordinate contract for art, retained UI and hit targets.
local L={width=402,height=874}
L.round={12,26,168,68}
L.score={32,74,292,78}
L.target={258,130,132,54}
L.lamps={42,144,218,48}
L.targetProgress={42,158,226,26}
L.screen={6,190,390,484}
L.board={16,202,370,458}
L.felt={16,650,374,206}
-- 倒计时位置改为紧凑操作带；下方毡面专门展示遗物。
L.deck={300,710,92,34}
L.relicGrid={34,746,334,96}
L.relicColumns=6
L.relicSlot=44
L.relicColumnGap=12
L.relicRowGap=8
-- 牌库页独占底部操作区：两块错落的收藏切换牌，下方居中返回。
L.inventoryItems={26,704,164,56}
L.inventoryRelics={210,718,164,56}
L.deckBack={106,790,190,52}
L.reroll={22,670,144,44}
L.start={180,660,208,48}
-- Draft page: separate shelves and staggered actions below the shared CRT.
-- 点击框等宽且基线固定；主动选中的整块托盘抬升，不暗示品质或推荐顺序。
L.draftSlots={{20,722,112,84},{145,722,112,84},{270,722,112,84}}
L.draftHide={20,674,102,36}
L.draftDeck={294,678,98,36}
L.draftRefresh={18,818,116,40}
L.draftSkip={146,834,72,32}
L.draftConfirm={230,814,160,48}
function L.Style(rect,scale)
    return {position="absolute",left=rect[1]*scale,top=rect[2]*scale,
        width=rect[3]*scale,height=rect[4]*scale,flexGrow=0,flexShrink=0,
        flexBasis="auto",margin=0}
end
return L
