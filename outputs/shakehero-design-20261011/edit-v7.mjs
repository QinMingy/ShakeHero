import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const out=path.dirname(fileURLToPath(import.meta.url));
const old=JSON.parse(await fs.readFile(path.join(out,'design-data-v6.json'),'utf8'));
const data=structuredClone(old), {items,relics,rules,builds,examples,audit}=data;
const assert=(ok,msg)=>{if(!ok)throw Error(msg);};
const get=id=>items.find(x=>x.id===id);
const changes=[];
function change(id,patch,reason){const x=get(id);Object.assign(x,patch,{revisionNote:reason});changes.push(id);}
change('I068',{family:'中立',tags:'工具、辅助'},'无需专用原料或流派标签，归为中立辅助；保留接触增值与轻推作用。');
change('I070',{family:'中立',quality:'普通',tags:'计数',effect:'结算时，瓶中每有4件物品，自身本回合分值+1。',limit:'计入自身、永久和临时物品；不足4件的部分不计；最多+6；只统计冻结时仍在瓶中的物品'},'从稀有核心改为普通中立过渡：移除不同名称奖励，16件时得4分，24件及以上封顶6分。');
change('I111',{family:'中立',tags:'计时'},'归为中立操作物品；保留延迟首次接触的收益，不按摇晃强度计分。');
change('I117',{family:'中立',tags:'辅助'},'归为中立辅助；帮助任何构筑中的低分物品，保留冻结分值选目标。');
const common={family:'中立',quality:'普通',acquisition:'三选一',inDraftPool:'是',lifetime:'永久',source:'原创',sourceRef:'原创（V7中立物品）',pilot:'首测候选'};
const fresh=[
 {...common,id:'I124',name:'骰子',base:0,shape:'六面方形',standardShape:'方形',tags:'随机',timing:'入瓶时',effect:'入瓶时，随机掷出1～6点，自身本回合分值增加对应点数。',limit:'每回合限触发1次；六种点数等概率；显示点数；复活不重掷；不受摇晃强度影响',revisionNote:'平均增加3.5分的普通过渡物品；点数作为本回合加分保留，其他增值正常叠加。'},
 {...common,id:'I125',name:'玻璃珠',base:3,shape:'圆形',standardShape:'圆形',tags:'摆件',timing:'无主动触发',effect:'无主动效果。',limit:'按通用规则结算；没有宝石、商品或共鸣标签',revisionNote:'稳定3分的普通过渡物品，用来比较骰子的波动和计数盘对数量的依赖。'}
];
items.splice(items.findIndex(x=>x.id.startsWith('P')),0,...fresh);
// 共通说明是选牌提示；仅实际效果和标签决定反应，不增设跨流派奖励。
const bridges={
 I004:'种植／牧场→烹饪：葡萄、苹果、谷穗、蛋、牛奶等食材均可做热餐；雏鸡与羊毛不是食材。',
 I007:'种植／牧场／烹饪→消费：消耗食物计分；羊毛、雏鸡和工具不在食物范围。',
 I011:'种植／元素：为植物和蒸汽锅炉供水；多余水珠可由海绵消耗。',
 I023:'种植→牧场／烹饪：麦田生产谷穗，可喂母鸡、奶牛，也可直接做热餐；两种用途竞争同一实体。',
 I041:'元素→矿业：点燃熔炉；也能点燃锅炉、蜡烛及融冰。火源不会因此被消耗。',
 I044:'元素→其他流派：点亮后增强接触的非元素物品，也包括中立物品。',
 I053:'种植／元素→集市：处理多余水珠；与植物、锅炉争水，并非供水不足时的必选。',
 I054:'矿业／烹饪／连锁→集市：只回收矿砂、铁屑、饼干屑、纪念票。',
 I058:'生产→集市：保留并增值商品；与消耗商品的拍卖槌是不同取舍。',
 I060:'生产／探险→集市：将热餐、羊毛、晶屑、铁锭、战利品等商品消耗计分。',
 I067:'集市／机械→灵魂：以商品为原本产临时纸影，再交焚化炉；原商品不被复印消耗。',
 I069:'机械→矿业：只增值铁矿块、铁锭、铁屑；金币和奖杯不能代替。',
 I077:'灵魂→各类消耗：接触即将被消耗的物品时得分，不要求目标属于灵魂流派。',
 I082:'宝石→种植／结算：培养带成长标签的物品；不会让无成长标签的中立物品获得永久成长。',
 I083:'宝石→机械／种植：给玩具、电容、复印机或水井充能；不能给小电池补电。',
 I085:'宝石→商品生产：接触生产者以追加1件商品；可用于农产、餐食、矿产，不能追加水珠或幽灵。',
 I090:'宝石→高分构筑：复制接触物品最高冻结分值的一部分；不读取其结算阶段才获得的加分。',
 I102:'连锁→其他流派：接力已被其他物品增值的目标；也可作用于中立物品。',
 I109:'连锁→多来源增值：让冻结时仍接触、且已被两种其他物品增值的目标获得倍率。',
 I113:'结算→种植：年轮树有植物、成长标签，可接受花盆、温室罩和黄水晶；没有开花标签。',
 I116:'结算→高分构筑：放大接触的最高冻结分值目标；不会因计数盘结算加分后升高而重新选择。',
 I118:'结算→分值差异较大的构筑：按冻结分值差给低分目标加分，适合高低分混搭。',
 I119:'结算→种植：吊床需要冻结时接触至少2株植物；不是无条件中立过渡。',
 I122:'机械→种植／元素：初始供1水，补充充能后最多供2水；可独立起步，不强制带电源。',
 I123:'种植→牧场／烹饪：1颗水珠换2束谷穗；既是饲料来源，也是食材来源。',
 P003:'种植／元素／集市：用于植物、麦田、锅炉或海绵；同一颗水珠只能被消耗一次。',
 P005:'种植→烹饪／集市：葡萄同时是食物、食材、商品；可加工、食用计分或出售。',
 P006:'种植→烹饪／集市：苹果同时是食物、食材、商品；选择保留、加工或出售。',
 P008:'牧场→烹饪／集市：蛋可做食材或出售，也可保留3次存活结算孵化；被消耗后不能继续孵化。',
 P009:'牧场→烹饪／集市：牛奶是食物、食材、商品；不需要专属加工器。',
 P010:'牧场→集市：羊毛可保留给货架增值，或交拍卖槌出售；不能做食材。',
 P014:'矿业→宝石／集市：晶屑可参加宝石配合，也可作为商品出售。',
 P015:'矿业→集市：金砂同时是货币和商品；不能被磁铁增值。',
 P016:'矿业→机械／集市：铁锭可被磁铁增值、货架增值或出售；已冶炼完成，不再次进熔炉。',
 P021:'机械→灵魂：临时纸影交焚化炉，可产永久幽灵与临时魂火；不用时结算后消失。',
 P024:'探险→宝石／集市：宝藏徽记可参加宝石配合或出售。',
 P025:'探险→集市：奖杯可作商品出售；虽有金属标签，也不能被磁铁增值。',
 P029:'牧场→烹饪／集市：与蛋相同的用途；保留3次存活结算仅孵化1只雏鸡。'
};
const neutrals={
 I068:['中立辅助','任意构筑：给接触目标少量加分并轻推，帮助创造下一次接触；每回合最多5个目标。'],
 I070:['中立过渡','任意构筑：16件得4分，24件封顶6分；生成流容易保住数量，消耗流会降低收益。'],
 I111:['中立操作','任意构筑：延后首次接触可提高得分；刚入瓶就接触时收益低，不列为稳定过渡。'],
 I117:['中立辅助','任意构筑：照顾接触的低分物品；可增强产物或过渡物品，不需要专用材料。'],
 I124:['中立过渡','任意构筑：随机1～6分，期望3.5分；入瓶后显示结果，再决定是否给它增值。'],
 I125:['中立过渡','任意构筑：稳定基础3分，没有专属连锁；可接受通用增值及圆形徽章。']
};
for(const x of items){x.role=neutrals[x.id]?.[0]||(bridges[x.id]?'共通物品':'流派组件');x.compatibility=neutrals[x.id]?.[1]||bridges[x.id]||'—';}
for(const x of fresh)changes.push(x.id);
const r78=relics.find(x=>x.id==='R078');
r78.effect='结算时，初始抽取且存活的物品覆盖至少6个非中立主流派时，所有初始抽取且存活的物品各本回合分值+3。';
r78.limit='中立不计入流派种类；满足条件后中立物品也享受加分；每件每回合限触发1次';
r78.revisionNote='中立是通用选牌类别，不是第13种主题流派；均衡阵容仍要求6个实际主题流派。';
const mechanical=builds.find(x=>x[0]==='机械');
mechanical[4]='复印机、电容罐';mechanical[11]='先测小电池、电动玩具、电容罐、复印机、水井';
mechanical[7]+='；计数盘可作为中立数量过渡，不再担当机械后期核心';
builds.find(x=>x[0]==='结算')[7]+='；指挥旗与秒表属于可选中立物品，其他构筑同样可用';
builds.push(['中立过渡','构筑尚未成形时提供独立分数或基础辅助；不是第13个主题流派','骰子、玻璃珠、计数盘','弹簧台、指挥旗、秒表','骰子、计数盘','普通奇迹、圆形徽章、结伴绳结','骰子入瓶显示随机点数；计数盘读取冻结总数量；玻璃珠稳定计分。秒表靠延迟首次接触，不依赖摇晃强度。','任意路线都可选用，无需凑齐中立套装；有明确方向后，优先选择能支持现有循环的物品','中立没有专属资源闭环，也不给主题流派计数。持续拿无关过渡牌会稀释关键组件入场率；数量型不适合大量消耗。当前未新增换牌、删牌或跳过奖励功能。','主题组件12、中立过渡4','无外部加分时：玻璃珠3；骰子1～6，平均3.5；计数盘在16件时4、8件时2、24件时6。','先测骰子、玻璃珠、计数盘、弹簧台、指挥旗']);
function rule(topic,text){const r=rules.find(x=>x[1]===topic);assert(r,topic);r[2]=text;}
rule('物品总表与奖励池','V7物品总表共128件，122件永久、6件临时。98件进入三选一，含6件中立物品；其余只由对应生成或变形来源获取。是否永久与是否进入三选一独立。新增I124骰子、I125玻璃珠；水珠仍不进入三选一。');
rule('版本与条目精简','V7在V6基础上新增骰子、玻璃珠，将弹簧台、计数盘、秒表、指挥旗归为中立；简化计数盘，标明自然共通搭配，更新均衡阵容、组合路线与算例。保留历史审查及V6循环检查；未改动资源配方或既有孵化规则。');
rules.push(
 ['设计约定','主流派与共通定位','主流派仍是需要流派条件时唯一读取的字段。共通物品保留原主流派，靠实际标签、名称或事件连接其他路线；共通搭配列仅提供选牌提示，没有额外奖励，也不限制未列出的合法搭配。“—”表示未特别列出连接点，不表示禁止跨流派使用。无需让每条路线都有固定桥梁。'],
 ['设计约定','中立与通用遗物','中立物品不要求专用生产链。中立过渡偏独立得分，中立辅助提供基础增值，中立操作需要接触控制；不是所有中立物品都保证稳定收益。中立不计入均衡阵容所需的非中立主流派种类；其他效果仍照常读取名称、标签、形状与品质。“非元素”“非连锁”均包含中立。通用遗物仍对满足条件的任意物品生效，不是中立专属遗物。'],
 ['设计约定','骰子与数量计分','骰子每回合第一次正常入瓶时等概率掷1～6点，作为自身本回合分值加分并显示；本回合复活不重掷，其他加分不被覆盖。下一回合再次入瓶才重掷；不看速度、力度或最终朝向。计数盘在冻结后按仍在瓶中的总件数结算，包括自身、永久与临时物品，不含牌库未抽到、弃牌堆和遗物；每4件+1，最多+6。'],
 ['设计约定','中立数值与选牌取舍','普通中立过渡先测：玻璃珠稳定3分；骰子1～6分、均值3.5；计数盘16件时4分、8件时2分、24件起6分。计数盘的加分发生在结算阶段，不进入冻结分值F，不能倒推为镜片或放大镜的选取依据。中立没有额外抽取名额、保底出现、转型补偿或自由移除。掉落权重与目标曲线未定，不承诺一定能靠中立过关。']
);
examples.push(
 ['计数盘／瓶中16件',0,4,0,0,'包含计数盘自身；16÷4=4。无外部加分，结算得4。'],
 ['计数盘／消耗后剩8件',0,2,0,0,'只读冻结时仍在瓶中的8件；已消耗物品不计入。'],
 ['计数盘／生成后共28件',0,6,0,0,'28÷4=7，但最多增加6；永久和临时实体均计数。'],
 ['骰子／掷出6点后再获+2',8,0,0,0,'入瓶骰点+6、摇晃阶段外部加分+2，因此冻结分值F=8。不是把其他加分覆盖成骰点。']
);
for(const id of changes){const x=get(id),before=old.items.find(y=>y.id===id);audit.push(['物品',id,before?.name||x.name,before?'调整':'新增',x.name,'—',x.revisionNote,before?.effect||'—',x.effect,'V6→V7']);}
audit.push(['遗物','R078','均衡阵容','调整','均衡阵容','—',r78.revisionNote,old.relics.find(x=>x.id==='R078').effect,r78.effect,'V6→V7']);
const counts={items:items.length,permanent:items.filter(x=>x.lifetime==='永久').length,temporary:items.filter(x=>x.lifetime==='临时').length,draftPool:items.filter(x=>x.inDraftPool==='是').length,neutral:items.filter(x=>x.family==='中立').length,shared:Object.keys(bridges).length,relics:relics.length};
assert(counts.items===128&&counts.neutral===6&&counts.draftPool===98,'数量不符');
assert(new Set([...items,...relics].map(x=>x.id)).size===189,'ID重复');
for(const id of Object.keys(bridges))assert(get(id),'缺桥接物品 '+id);
for(const x of old.items){if(changes.includes(x.id))continue;const y=get(x.id);for(const k of Object.keys(x))assert(JSON.stringify(x[k])===JSON.stringify(y[k]),'非目标改动 '+x.id+' '+k);}
for(const b of builds){assert([...b[9].matchAll(/\d+/g)].reduce((s,m)=>s+ +m[0],0)===16,'16件示例 '+b[0]);for(const c of [2,3,4])for(const n of b[c].split('、'))assert(items.some(x=>x.name===n),'路线名称 '+n);for(const n of b[5].split('、'))assert(relics.some(x=>x.name===n),'遗物名称 '+n);}
const countScore=n=>Math.min(6,Math.floor(n/4));
assert(JSON.stringify([1,3,4,8,15,16,23,24,28,100].map(countScore))==='[0,0,1,2,3,4,5,6,6,6]','计数盘边界');
const diceMean=[1,2,3,4,5,6].reduce((s,n)=>s+n,0)/6;assert(diceMean===3.5,'骰子均值');
const previousReport=JSON.parse(await fs.readFile(path.join(out,'validation-v6.json'),'utf8'));
for(const [id,sources]of Object.entries(previousReport.acquisitionEdges))for(const src of sources)assert(get(id).acquisition.includes([...items,...relics].find(x=>x.id===src).name),'来源不同步 '+id);
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(path.join(out,'ShakeHero_物品与遗物设计_V6.xlsx')));
const col=n=>{let s='';for(n++;n;n=Math.floor((n-1)/26))s=String.fromCharCode(65+(n-1)%26)+s;return s;};
const font={name:'Microsoft YaHei',size:10,color:'#20334D'};
const header={fill:'#344D6D',font:{...font,bold:true,color:'#FFFFFF'},rowHeight:40,horizontalAlignment:'center',verticalAlignment:'center',wrapText:true};
function update(name,title,subtitle,rows,widths,tableName,oldCols,headers){
 const s=wb.worksheets.getItem(name),end=col(widths.length-1),last=rows.length+5;
 s.getRange(`A2:${col(oldCols-1)}2`).unmerge();s.getRange(`A3:${col(oldCols-1)}3`).unmerge();
 for(const r of [2,3])s.getRange(`A${r}:${end}${r}`).merge();
 s.getRange('A2').values=[[title]];s.getRange(`A2:${end}2`).format={font:{...font,size:16,bold:true},rowHeight:28};
 s.getRange('A3').values=[[subtitle]];s.getRange(`A3:${end}3`).format={font:{...font,color:'#54677E'},rowHeight:36,wrapText:true};
 for(const t of [...s.tables.items])t.delete();
 if(headers)s.getRange(`A5:${end}5`).values=[headers];
 s.getRange(`A6:${end}${last}`).values=rows;s.tables.add(`A5:${end}${last}`,true,tableName);
 s.getRange(`A5:${end}5`).format=header;
 widths.forEach((w,i)=>s.getRange(`${col(i)}1:${col(i)}${last}`).format.columnWidth=w);
 rows.forEach((r,i)=>{const lines=Math.max(...r.map((v,j)=>Math.ceil([...String(v??'')].reduce((a,c)=>a+(c.charCodeAt(0)>255?1.7:.85),0)/(widths[j]-2))));s.getRange(`A${i+6}:${end}${i+6}`).format={font,verticalAlignment:'center',wrapText:true,rowHeight:Math.max(30,lines*14+10),fill:i%2===0?'#F3F6FA':'#FFFFFF'};});
 return s;
}
const si=update('物品总表','物品总表 · V7',`128件物品，98件进入三选一；含6件中立物品、${counts.shared}件标注共通搭配的物品。筛选“主流派＝中立”查看中立组；右侧新增构筑定位与搭配说明。`,items.map(x=>[x.id,x.name,x.quality,x.base,x.acquisition,x.inDraftPool,x.lifetime,x.timing,x.effect,x.limit,x.family,x.tags,x.shape,x.standardShape,x.sourceRef,x.pilot,x.role,x.compatibility]),[8,17,9,9,53,16,10,16,62,35,10,28,16,13,42,14,15,67],'Items',16,['ID','名称','品质','基础分','获取方式','是否进入三选一','存续','触发时机','效果','次数与边界','主流派','标签','外观形状','标准形状','原表参考','测试批次','构筑定位','共通搭配／使用条件']);
si.getRange(`D6:D${items.length+5}`).setNumberFormat('0');
si.getRange(`F6:F${items.length+5}`).dataValidation={rule:{type:'list',values:['是','否']}};
si.getRange(`G6:G${items.length+5}`).dataValidation={rule:{type:'list',values:['永久','临时']}};
si.getRange(`Q6:Q${items.length+5}`).dataValidation={rule:{type:'list',values:['流派组件','共通物品','中立过渡','中立辅助','中立操作']}};
items.forEach((x,i)=>{if(x.family==='中立')si.getRange(`K${i+6}`).format={fill:'#E1EFE5',font:{...font,bold:true}};});
update('遗物','遗物设计 · V7','61件遗物。均衡阵容按非中立主流派统计；通用遗物仍服务任意满足条件的物品，不新增中立专属奖励。',relics.map(x=>[x.id,x.name,x.quality,x.timing,x.effect,x.limit,x.family,x.sourceRef]),[8,19,9,18,68,40,11,46],'Relics',8);
update('流派组合','12套主题路线与中立过渡 · V7','共通物品保留主流派，只按原有标签和效果工作；中立用于过渡、基础辅助或操作取舍，不要求每套阵容都携带。',builds,[12,28,34,34,25,39,63,47,49,37,62,48],'Builds',12);
const sr=update('规则','规则口径与来源 · V7','补充中立、共通搭配、骰子与数量计分口径。永久生成与消耗、三次存活孵化及V6供给配方保持一致。',rules,[14,24,120],'Rules',3);
rules.forEach((r,i)=>{if(r[0]==='待定')sr.getRange(`A${i+6}:C${i+6}`).format.fill='#FFF2CC';if(r[0]==='已确认')sr.getRange(`A${i+6}`).format.font={...font,color:'#3B6B54',bold:true};});
const se=update('结算算例','结算算例 · V7','追加数量计分与骰点叠加示例。冻结分值F与结算加分A分开；计数盘本回合计数加分不能被镜片提前读取。',examples.map(x=>[x[0],x[1],x[2],x[3],x[4],null,x[5]]),[31,13,15,15,15,14,58],'ScoreExamples',7);
for(let i=0;i<examples.length;i++){const r=i+6;se.getRange(`F${r}`).formulas=[[`=ROUNDDOWN((B${r}+C${r})*(1+D${r}),0)+E${r}`]];}se.getRange(`D6:D${examples.length+5}`).setNumberFormat('0%');
const sa=update('审查调整','逐项审查 · V4 → V7','保留历史419项，本轮追加4件重新定位物品、2件新增物品及均衡阵容的调整。共通搭配为说明字段，不额外改动配方。',audit,[9,9,19,10,20,27,64,67,67,15],'ReviewLog',10);
sa.getRange(`D6:D${audit.length+5}`).conditionalFormats.clear();
for(const [text,fill,color]of [['调整','#DDEBFA','#194F87'],['合并','#FFF2CC','#7D5700'],['移除','#F8DEDE','#9B3636'],['新增','#E1EFE5','#2A663D']])sa.getRange(`D6:D${audit.length+5}`).conditionalFormats.add('containsText',{text,format:{fill,font:{color}}});
wb.recalculate();
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!|#NULL!',options:{useRegex:true,maxResults:10},maxChars:700})).ndjson);
console.log((await wb.inspect({kind:'region',sheetId:'结算算例',range:'A16:G19',maxChars:1600,tableMaxRows:4,tableMaxCols:7})).ndjson);
await fs.mkdir(path.join(out,'previews-v7'),{recursive:true});
const row=id=>items.findIndex(x=>x.id===id)+6;
for(const [sheetName,range,file]of [['物品总表',`A${row('I124')}:L${row('I125')}`,'new-neutrals'],['物品总表',`H${row('I068')}:L${row('I070')}`,'count'],['物品总表',`Q${row('I122')}:R${row('I125')}`,'roles'],['遗物','A65:H66','relic'],['流派组合','A18:F18','neutral-route'],['规则',`A${rules.length+2}:C${rules.length+5}`,'rules'],['结算算例','A16:G19','examples'],['审查调整',`A${old.audit.length+6}:G${audit.length+5}`,'audit']]){const b=await wb.render({sheetName,range,scale:1,format:'png'});await fs.writeFile(path.join(out,'previews-v7',file+'.png'),new Uint8Array(await b.arrayBuffer()));}
await(await SpreadsheetFile.exportXlsx(wb)).save(path.join(out,'ShakeHero_物品与遗物设计_V7.xlsx'));
await fs.writeFile(path.join(out,'design-data-v7.json'),JSON.stringify(data,null,2));
await fs.writeFile(path.join(out,'validation-v7.json'),JSON.stringify({...counts,changes:[...changes,'R078'],auditRows:audit.length,acquisitionEdges:previousReport.acquisitionEdges,formulaResults:examples.map(x=>Math.floor((x[1]+x[2])*(1+x[3]))+x[4]),checks:{uniqueIDs:true,unchangedRecipes:true,sourceReferences:true,buildReferences:true,countBoundaries:true,diceMean:true},playtested:false},null,2));
console.log(JSON.stringify(counts));
