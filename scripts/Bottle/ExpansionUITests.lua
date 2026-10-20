-- 98件目录、动态文案与刷新UI纯Lua专项，不依赖Box2D/真实存档。
-- 接线：require("Bottle.ExpansionUITests").Run()；或由ExpansionUIValidation真实界面入口调用。
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local ItemText = require("Bottle.ItemText")
local RefreshUI = require("Bottle.RefreshUI")
local Tests = {}

---@param report fun(condition:boolean,message:string)?
---@return integer checks
function Tests.Run(report)
    local count = 0
    local function Check(condition, message)
        count = count + 1
        if report then report(condition, message) else assert(condition, message) end
    end
    local function Contains(text, fragment) return text:find(fragment, 1, true) ~= nil end
    Check(#Items.list == 98, "目录共98件")
    local blocked = {
        apple=true, banana=true, orange=true, droplet=true, gambling_god=true,
        rotten_banana=true, banana_peel=true, apple_half=true, banana_half=true, orange_half=true,
        fruit_ninja=true, cherry_half=true, tomato_egg=true, coin_4=true, coin_8=true,
        coin_16=true, coin_32=true, coin_64=true, coin_128=true, coin_256=true, coin_512=true,
        coin_1024=true, coin_2048=true, poop=true, golden_poop=true, diamond_poop=true,
        rainbow_poop=true, juice=true, discus_athlete=true, discus=true, wool=true, sweater=true,
    }
    local poolCount = 0
    for index, def in ipairs(Items.list) do
        Check(def.numberId == index and Items.byNumber[index] == def and Items.byId[def.id] == def,
            "目录索引一致#" .. index)
        Check(def.implemented == true, def.id .. "已实装")
        Check(def.pool == (blocked[def.id] ~= true), def.id .. "仅按源表屏蔽列控制pool")
        if def.pool then poolCount = poolCount + 1 end
    end
    Check(poolCount == 66, "66开放/32屏蔽，仅限制新候选，已有实例与生成保留")
    Check(Items.byId.banana.base==6 and not Items.byId.rotten_banana.pool, "香蕉基础6、腐烂香蕉屏蔽卡池")
    Check(Items.byId.glutton.rarity==2 and Items.byId.diner.rarity==1, "大胃王优秀品质、食客普通品质")
    local appended = {
        "chick", "sheep", "pig", "calf", "grass", "hay", "poop", "golden_poop", "diamond_poop",
        "rainbow_poop", "gecko", "cactus", "abacus", "bodyguard", "chicken_keeper", "splitter",
        "juice", "discus_athlete", "discus", "compass", "jelly", "wool", "sweater",
        "spinning_top", "windmill", "gear", "roulette", "removal_coin",
    }
    local newBases = {3,3,4,3,3,5,1,3,8,16,4,4,5,4,3,3,3,4,2,3,4,1,10,3,4,4,4,4}
    local newRarities = {1,1,1,1,1,1,1,3,4,5,2,1,2,1,2,3,3,2,2,1,1,1,1,1,2,2,2,2}
    local newTags = {"动物","动物","动物","动物","植物","植物","垃圾","垃圾","垃圾","垃圾",
        "动物","植物","","人类","人类","","食物","人类","","","","","","","","","",""}
    local cooldowns = {5,0,2,0,1,3,1,1,0,0,1,1,0,0,5,4,0,0,0,3,2.5,1,1,0,0,4,0,0}
    local triggers = {"timer","none","touch","none","touch","touch","touch","touch","none","none",
        "side","touch","none","none","touch","touch","none","none","none","none","touch","touch","touch",
        "none","none","none","none","none"}
    for index, id in ipairs(appended) do
        local def = assert(Items.byId[id])
        Check(def.numberId == index + 70 and def.shape == (id=="removal_coin" and "circle" or id), id .. "固定源表ID及shape")
        Check(def.base == newBases[index] and def.rarity == newRarities[index], id .. "基础价值和品质")
        Check(table.concat(def.tags or {}, "、") == newTags[index], id .. "严格源表tag")
        Check(def.cooldown == cooldowns[index] and def.trigger == triggers[index], id .. "调度参数")
        Check(math.abs(def.radius - ((id=="grass" or id=="wool" or id=="discus") and .23 or .27)*1.25)<1e-8,
            id .. "图案与物理统一尺寸")
    end
    Check(Items.HasTag("soldier", "人类") and Items.HasTag("doctor", "人类"), "保留士兵医生人类tag")
    local chickGame = {relics={}} --[[@as any]]
    for _, text in ipairs({Items.byId.chick.effect, ItemText.Effect(chickGame, "chick"),
        ItemText.Effect(chickGame, "chick", {id="chick"} --[[@as any]])}) do
        Check(text == "每5秒：30%概率产生一个[[egg]]", "小鸡定义、候选及实例说明统一30%产蛋")
    end
    Check(Items.byId.ghost.piercing == true and Items.byId.discus.piercing == true, "幽灵飞盘穿透标记")
    Check(Items.byId.apple_half.name == "半个苹果", "半个苹果更名")
    Check(Contains(Items.byId.teacher.effect, "自身价值永久+3"), "老师说明+3")
    Check(Contains(Items.byId.diner.effect, "整批") and Contains(Items.byId.diner.effect, "超过5"), "食客最后整批说明")
    Check(Contains(Items.byId.pig.effect,"[[banana_peel]]") and Contains(Items.byId.pig.effect,"×2")
        and Contains(Items.byId.pig.effect,"金币"), "猪说明包含香蕉皮及消费前价值两倍金币")
    Check(Contains(Items.byId.star.effect, "价值+1（本回合）"), "星星临时+1说明")
    Check(Items.byId.tomato.rarity==1 and Items.HasTag("tomato","植物") and Items.HasTag("tomato","食物"),
        "西红柿普通品质并保留食物及新增植物tag")
    Check(Items.byId.tomato_egg.rarity==3 and Items.HasTag("fruit_tree","植物"), "炒蛋稀有品质与果树植物tag")
    Check(Contains(Items.byId.cactus.effect,"自身倍率增加对应数值（本回合）"), "仙人掌说明区分临时倍率与永久体积")
    Check(Contains(Items.byId.fitness_coach.effect,"体积变小时") and Contains(Items.byId.fitness_coach.effect,"自身价值永久+1"),
        "教练真实缩小时永久+1说明")
    for _, id in ipairs({"hay","pig","splitter","compass","jelly","chicken_keeper","ball","thief","gear"}) do
        Check(Items.HasCooldown(id), id .. "源表明确冷却提示")
    end
    for _, id in ipairs({"chick","grass","poop","golden_poop","gecko","cactus","wool","sweater",
        "teacher","police","gambler","farmer","droplet","star","fruit_tree","ghost","spinning_top","windmill","roulette","removal_coin"}) do
        Check(not Items.HasCooldown(id), id .. "内部防抖/周期不显示冷却")
    end
    ---@type any
    local game = {relics={},refreshes=3,rerollUsed=true,refreshUsed=true}
    ---@type any
    local first = {scale=1.2,weight=1.7,counter=2,bottleRounds=1,woolCount=7}
    ---@type any
    local second = {scale=1.8,weight=.6,counter=1,bottleRounds=2}
    local pigA, pigB = ItemText.Effect(game,"pig",first), ItemText.Effect(game,"pig",second)
    Check(Contains(pigA,"体积（当前：120%）") and Contains(pigA,"重量（当前：170%）"), "猪A独立体积重量")
    Check(Contains(pigB,"体积（当前：180%）") and Contains(pigB,"重量（当前：60%）"), "猪B独立体积重量")
    local pigDefault = ItemText.Effect(game,"pig")
    Check(Contains(pigDefault,"体积（当前：100%）") and Contains(pigDefault,"重量（当前：100%）"), "候选猪默认各100%")
    Check(Contains(ItemText.Effect(game,"bodyguard",first),"当前：2"), "保镖counter独立显示")
    Check(Contains(ItemText.Effect(game,"egg",first),"当前：1"), "鸡蛋读取bottleRounds不读counter")
    Check(Contains(ItemText.Effect(game,"egg",second),"当前：2"), "第二鸡蛋入瓶回合数")
    Check(Contains(ItemText.Effect(game,"sheep",first),"当前：7"), "小羊显示自己的储毛库存")
    Check(Contains(ItemText.Effect(game,"sheep"),"当前：0"), "小羊新候选默认无储毛")
    local Shapes = require("Bottle.Shapes")
    local MakeSprite = require("Bottle.Sprites").Make
    ---@type table<BottlePixelSprite, {rows:string[],palette:table<string,number[]>}>
    local sourceArt = {}
    ---@type table<string,BottlePixelSprite>
    local sheepArt = {}
    local function CaptureSheep(rows, palette)
        local sprite=MakeSprite(rows,palette)
        sourceArt[sprite]={rows=rows,palette=palette}
        return sprite
    end
    require("Bottle.ExpansionSprites")(CaptureSheep,{10,10,26,255},sheepArt)
    local previousWool,previousArea = -1,0
    for _,id in ipairs({"sheep_0","sheep","sheep_5"}) do
        local sprite=assert(sourceArt[assert(sheepArt[id])])
        local wool,valid=0,#sprite.rows==16
        for _,row in ipairs(sprite.rows) do
            valid=valid and #row==16
            for column=1,#row do
                local glyph=row:sub(column,column)
                if glyph~="." and not sprite.palette[glyph] then valid=false end
                -- 只统计左侧身体，排除深色脸上共用w色的白眼。
                if column<=9 and (glyph=="h" or glyph=="w" or glyph=="s") then wool=wool+1 end
            end
        end
        Check(valid,id.."绵羊16×16图案与色板完整")
        local referencePalette = {
            h={245,242,224,255}, w={255,255,248,255}, s={205,201,186,255},
            d={69,73,87,255}, l={102,106,119,255}, e={213,151,157,255}, m={164,109,119,255},
            o={10,10,26,255},
        }
        local matchesReference=true
        for key,expected in pairs(referencePalette) do
            local color=sprite.palette[key]
            for channel=1,4 do
                matchesReference=matchesReference and color[channel]==expected[channel]
            end
        end
        Check(matchesReference,id.."匹配用户选定的奶白毛、深灰脸腿、粉耳鼻与近黑描边")
        Check(wool>previousWool,id.."身上卷毛像素随档位严格增加")
        if id=="sheep_0" then
            local hasBareBody=false
            for _,row in ipairs(sprite.rows) do
                hasBareBody=hasBareBody or row:find("b",1,true)~=nil or row:find("c",1,true)~=nil
            end
            Check(wool>0 and not hasBareBody,"零库存仍有白色贴身短绒，不露裸色身体")
        end
        previousWool=wool
        local area,convex=0,true
        for _,polygon in ipairs(assert(Shapes.profiles[id].polygons)) do
            local n=#polygon//2
            for i=1,n do
                local j,k=i%n+1,(i+1)%n+1
                local ax,ay=polygon[2*i-1],polygon[2*i]
                local bx,by=polygon[2*j-1],polygon[2*j]
                local cx,cy=polygon[2*k-1],polygon[2*k]
                area=area+ax*by-ay*bx
                if (bx-ax)*(cy-by)-(by-ay)*(cx-bx)<-1e-8 then convex=false end
            end
        end
        Check(convex and area>previousArea,id.."碰撞凸片合法且毛量增加时面积增大")
        previousArea=area
    end
    for _,stock in ipairs({0,1,4,5,7}) do
        local expected=stock==0 and "sheep_0" or (stock<5 and "sheep" or "sheep_5")
        Check(Shapes.Variant("sheep",stock)==expected,"羊毛库存"..stock.."统一选档")
    end
    Check(Shapes.Variant("sheep")=="sheep_0","新候选图案默认剃毛档")
    Check(Contains(Items.byId.knife.effect,"[[chick]]") and Contains(Items.byId.knife.effect,"小鸡价值×2")
        and Contains(Items.byId.knife.effect,"冷却：4秒") and not Contains(Items.byId.knife.effect,"[[sheep]]"), "小刀说明同步消耗小鸡与共用4秒冷却")
    Check(Items.byId.wool.base==1 and not Contains(Items.byId.wool.effect,"被消耗时"), "最新羊毛基础1且不再被耗结算")
    Check(Contains(Items.byId.wool.effect,"不占用抽取数量") and Contains(Items.byId.wool.effect,"临时属性"), "价值1羊毛下回合额外入场说明")
    game.relics.lucky_charm = true
    Check(ItemText.Effect(game,"hay")==Items.byId.hay.effect, "幸运符不改写草堆正文")
    game.relics.wash_hands,game.relics.teach_all,game.relics.thief_handbook = true,true,true
    local thief = ItemText.Effect(game,"thief")
    Check(thief==Items.byId.thief.effect, "洗手与手册不改写小偷正文")
    Check(ItemText.Effect(game,"teacher")==Items.byId.teacher.effect, "有教无类不追加老师正文")
    Check(ItemText.Effect(game,"police")==Items.byId.police.effect, "金盘洗手不改写警察正文")
    game.relics.chef_hat = true
    Check(ItemText.Effect(game,"chef")==Items.byId.chef.effect and Contains(Relics.byId.chef_hat.note or "","每位厨师独立绑定"), "候选不伪造实例强化，遗物说明明确独立累计")
    Check(RefreshUI.Count(game)==3 and RefreshUI.ButtonText(game)=="刷新 · 3 次", "物品刷新池不受准备重抽标记影响")
    game.refreshes=0
    Check(RefreshUI.Count(game)==0 and Contains(RefreshUI.Hint(game),"剩余 0 次"), "耗尽刷新次数及底部提示")
    game.phase,game.relicDraft,game.refreshUsed,game.relicRefreshes="draft",true,false,1
    Check(RefreshUI.Count(game)==1 and RefreshUI.ButtonText(game)=="免费刷新 · 1 次",
        "物品余额为零仍显示独立遗物免费刷新")
    Check(Contains(RefreshUI.Hint(game),"免费1次") and Contains(RefreshUI.Hint(game),"不累计"), "遗物提示每组免费且不累计")
    game.refreshes,game.refreshUsed,game.relicRefreshes=9,true,0
    Check(RefreshUI.Count(game)==0 and RefreshUI.ButtonText(game)=="免费刷新 · 0 次",
        "遗物用尽后不显示物品池的9次")
    game.relicDraft=false
    Check(RefreshUI.Count(game)==9 and RefreshUI.ButtonText(game)=="刷新 · 9 次",
        "返回物品页面显示共享物品余额")
    game.phase,game.rerollUsed="prepare",false
    Check(RefreshUI.Count(game)==9 and RefreshUI.ButtonText(game)=="重新抽取 · 9 次",
        "准备显示共享物品池9次，保留重新抽取文案")
    Check(Contains(RefreshUI.Hint(game),"共享") and not Contains(RefreshUI.Hint(game),"每回合重置")
        and Contains(RefreshUI.Hint(game),"每完成1回合+1"),
        "准备提示每完成1回合增加1次、共享累计且不重置")
    game.rerollUsed=true
    Check(RefreshUI.Count(game)==9 and RefreshUI.ButtonText(game,"重抽")=="重抽 · 9 次",
        "准备已重抽标记不限制共享余额且保留传入文案")
    game.phase,game.refreshes,game.rerollUsed="prepare",0,false
    Check(RefreshUI.Count(game)==0, "共享物品池为空即无准备重抽次数")
    Check(#Relics.list==39, "遗物完整39项")
    local relicIds={"teacher_team","accelerator","ghost_poop","premium_grass","food_comfort",
        "bacon_network","ghost_sport","spin_reward","wool_market","wool_recycle","dice_jackpot","calf_rush","lucky_roulette"}
    local rarities={2,2,2,1,2,2,1,2,1,1,2,2,2}
    for index,id in ipairs(relicIds) do
        local relic=assert(Relics.byId[id])
        Check(relic.numberId==index+24 and Relics.byNumber[index+24]==relic, id.."固定遗物编号")
        Check(relic.rarity==rarities[index] and relic.pool and relic.implemented, id.."品质/开放候选/接线")
    end
    Check(#Relics.Available({relics={}} --[[@as any]])==39, "39遗物全部进入未拥有候选")
    for _,def in ipairs(Relics.list) do
        for ref in def.effect:gmatch("%[%[([%w_]+)%]%]") do
            Check(Items.byId[ref]~=nil,def.id.."遗物说明引用物品已注册："..ref)
        end
    end
    local LoadSprites=require("Bottle.RelicSprites")
    local spriteCount=0
    local function VerifySprite(rows,palette)
        spriteCount=spriteCount+1
        return {rows=rows,palette=palette} --[[@as any]]
    end
    ---@type table<string,{rows:string[],palette:table<string,number[]>}>
    local sprites=LoadSprites(VerifySprite,{30,32,42,255}) --[[@as any]]
    Check(spriteCount==39,"39遗物均有独立像素徽记")
    for id,sprite in pairs(sprites) do
        local size=16
        Check(#sprite.rows==size,id.."遗物像素画布高度"..size)
        local widthValid,paletteValid=true,true
        for _,row in ipairs(sprite.rows) do
            if #row~=size then widthValid=false end
            for glyph in row:gmatch(".") do
                if glyph~="." and sprite.palette[glyph]==nil then paletteValid=false end
            end
        end
        Check(widthValid,id.."遗物像素行宽一致"..size)
        Check(paletteValid,id.."遗物像素调色板完整")
    end
    local LoadItems=require("Bottle.ItemSprites")
    ---@type table<string,{rows:string[],palette:table<string,number[]>}>
    local itemSprites=LoadItems(function(rows,palette)
        return {rows=rows,palette=palette,groups={}} --[[@as any]]
    end,{30,32,42,255}) --[[@as table<string,{rows:string[],palette:table<string,number[]>}>]]
    local enoki=assert(itemSprites.enoki)
    Check(#enoki.rows==16,"金针菇与多数物品统一16×16原稿高度")
    local enokiWidthValid,enokiPaletteValid=true,true
    for _,row in ipairs(enoki.rows) do
        if #row~=16 then enokiWidthValid=false end
        for glyph in row:gmatch(".") do
            if glyph~="." and enoki.palette[glyph]==nil then enokiPaletteValid=false end
        end
    end
    Check(enokiWidthValid,"金针菇16像素行宽一致")
    Check(enokiPaletteValid,"金针菇透明区域与五色色板完整")
    Check(Items.byId.enoki.shape=="circle" and math.abs(Items.byId.enoki.radius-.3)<1e-8,
        "金针菇仅换图，不改圆形碰撞及0.3米半径")
    for _,id in ipairs(relicIds) do Check(sprites[id]~=nil,id.."徽记已注册") end
    game.relics.ghost_poop=true
    for _,id in ipairs({"poop","golden_poop","diamond_poop","rainbow_poop"}) do
        Check(Items.IsPiercing(id,game) and not Items.IsPiercing(id),id.."穿透按对局而非全局定义")
        Check(ItemText.Effect(game,id)==Items.byId[id].effect,id.."实际穿透但不追加遗物说明")
    end
    Check(Items.IsPiercing("ghost") and Items.IsPiercing("discus") and not Items.IsPiercing("apple",game),"默认穿透类型不扩大")
    game.relics.premium_grass,game.relics.wool_market=true,true
    Check(ItemText.Effect(game,"grass")==Items.byId.grass.effect,"优质草不追加物品正文")
    Check(Contains(ItemText.Effect(game,"sheep",first),"当前：7") and not Contains(ItemText.Effect(game,"sheep",first),"羊毛集市"),"小羊保留实例库存且不追加遗物说明")
    game.relics.teacher_team,game.relics.food_comfort,game.relics.bacon_network=true,true,true
    game.relics.ghost_sport,game.relics.spin_reward,game.relics.accelerator=true,true,true
    Check(ItemText.Effect(game,"teacher")==Items.byId.teacher.effect,"名师团队不追加老师正文")
    Check(ItemText.Effect(game,"apple")==Items.byId.apple.effect,"食物加值不追加物品正文")
    Check(ItemText.InitialValue(game,"apple")==4,"食物候选基础包含+2")
    game.relics.tomato_tycoon=true
    Check(ItemText.InitialValue(game,"tomato")==10,"西红柿候选先基础3+2再翻倍")
    Check(ItemText.InitialValue(game,"soldier")==5,"非食物候选不加2")
    Check(not Contains(ItemText.Effect(game,"soldier"),"吃了不烧心"),"食物遗物严格tag")
    Check(ItemText.Effect(game,"bacon")==Items.byId.bacon.effect,"培根邻接遗物不追加物品正文")
    Check(Contains(Relics.byId.bacon_network.note or "","不扩大物理碰撞"),"培根逻辑邻接说明不扩大物理轮廓")
    Check(ItemText.Effect(game,"ghost")==Items.byId.ghost.effect,"幽灵运动不追加物品正文")
    Check(Contains(Relics.byId.ghost_sport.effect,"每移动30m，+1金币")
        and Contains(Relics.byId.ghost_sport.note or "","不直接增加幽灵价值"),"幽灵运动30m固定金币保留在遗物说明")
    Check(ItemText.Effect(game,"compass")==Items.byId.compass.effect and ItemText.Effect(game,"apple")==Items.byId.apple.effect,"旋转及加速遗物不追加物品正文")
    Check(Contains(Relics.byId.spin_reward.effect,"自然旋转三圈") and Contains(Relics.byId.spin_reward.effect,"30%")
        and Contains(Relics.byId.spin_reward.note or "","无论成败都消耗三圈"),"转圈圈三圈30%及失败耗进度保留在遗物说明")
    Check(Contains(Relics.byId.accelerator.effect,"移动速度增加20%")
        and Contains(Relics.byId.accelerator.note or "","不缩短冷却/回合时间"),"加速器20%及不改时间保留在遗物说明")
    game.relics.coin_rain=true
    local cloud=ItemText.Effect(game,"cloud")
    Check(cloud==Items.byId.cloud.effect and Contains(cloud,"6个临时[[droplet]]"),"硬币雨不替换云朵原本生成物说明")
    ---@type any
    local noRelics={relics={}}
    ---@type any
    local allRelics={relics={}}
    for _,relic in ipairs(Relics.list) do allRelics.relics[relic.id]=true end
    for _,def in ipairs(Items.list) do
        if def.id == "chef" then
            first.chefBoost,second.chefBoost=2,5
            Check(ItemText.Effect(allRelics,def.id)==ItemText.Effect(noRelics,def.id)
                and Contains(ItemText.Effect(allRelics,def.id,first),"当前：+2")
                and Contains(ItemText.Effect(allRelics,def.id,second),"当前：+5"),
                "厨师候选保留本体正文，持帽实例分别显示真实累计强化")
        else
            Check(ItemText.Effect(allRelics,def.id)==ItemText.Effect(noRelics,def.id)
                and ItemText.Effect(allRelics,def.id,first)==ItemText.Effect(noRelics,def.id,first)
                and ItemText.Effect(allRelics,def.id,second)==ItemText.Effect(noRelics,def.id,second),
                def.id.."全部遗物不影响候选或两个独立实例的正文")
        end
    end
    Check(Contains(Items.byId.gecko.effect,"其他壁虎") and Contains(Items.byId.gecko.effect,"0.25秒") and Contains(Items.byId.gecko.effect,"每直接连接"),"壁虎延迟和直接邻接结算说明")
    print("[ExpansionUITests] " .. count .. " checks")
    return count
end

return Tests
