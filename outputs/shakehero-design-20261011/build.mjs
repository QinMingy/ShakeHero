import fs from 'node:fs/promises';
import path from 'node:path';
import {Workbook, SpreadsheetFile} from '@oai/artifact-tool';
import {items,products,relics,families} from './catalog.mjs';
import {rules,builds,mappings,examples} from './design-notes.mjs';
const out=path.dirname(new URL(import.meta.url).pathname).replace(/^\/([A-Za-z]:)/,'$1');
const source=JSON.parse(await fs.readFile(path.join(out,'source.json'),'utf8'));
const refs=new Map();
for(const sn of ['触发器','增益']) source[sn].slice(1).forEach((r,i)=>refs.set(r[1],{sheet:sn,row:i+2,effect:r[3],category:r[0]}));
const sourceRef=(str)=>str.split(';').map(n=>{
 if(n==='原创') return '原创';
 const ref=refs.get(n); if(!ref) throw Error(`未找到参考名称: ${n}`);
 if(/未收录|没有.*效果/.test(ref.effect)||ref.category==='效果未收录')throw Error(`未知原版效果被使用: ${n}`);
 return `${n}（${ref.sheet}!D${ref.row}）`;
}).join('；');
const shapes=s=>{
 if(['圆形','小圆形','扁圆形','圆柱形','短圆柱形','圆桶形'].includes(s))return '圆形';
 if(['方形','圆角方形','方炉形','扁方形'].includes(s))return '方形';
 if(['三角形','小三角形','钝三角形'].includes(s))return '三角形';
 if(['长方形','圆角长方形','细长形','长条形','短长条形','细长形','长棒形','胶囊形'].includes(s))return '长条形';
 if(['浅碟形','浅碗形','凹字形','凹槽长条','马蹄形','杯形','环形'].includes(s))return '凹槽形';
 if(['月牙形','拱形','拱顶长方形'].includes(s))return '弧形';
 return '不规则形';
};
const pFamilies=['烹饪','烹饪','元素','种植','种植','种植','种植','牧场','牧场','牧场','牧场','牧场','矿业','矿业','矿业','矿业','元素','元素','元素','储存','机械','灵魂','灵魂','探险','探险','结算','烹饪','种植','牧场','矿业','宝石','连锁'];
const pilot=new Set(builds.flatMap(r=>r[11].replace('先测','').split('、')));
const ratios=['生产者3、食材8、增值2、核心3','供水3、植物10、辅助3','动物8、谷穗5、设施3','矿石8、工具4、元素2、核心2','初始元素6、转换器4、接收者6','容器5、货币或产物源8、辅助3','电源3、充能6、被增值目标7','消耗材料9、消费者4、观察者3','宝石7、接收者6、生产源3','木剑5、钥匙5、目标3、辅助3','路径源4、传递盖章4、接收者8','成长核心6、增值源6、结算辅助4'];
builds.forEach((r,i)=>{r[9]=ratios[i];if([...r[9].matchAll(/\d+/g)].reduce((n,m)=>n+Number(m[0]),0)!==16)throw Error('构筑样本不为16件');});
for(const x of items){
 if(x.effect.includes('生成')&&!x.tags.includes('生产者'))x.tags+='、生产者';
 x.standardShape=shapes(x.shape);x.sourceRef=sourceRef(x.source);
}
for(const [i,x]of products.entries()){x.family=pFamilies[i];x.standardShape=shapes(x.shape);x.sourceRef=sourceRef(x.source);}
for(const x of relics)x.sourceRef=sourceRef(x.source);
const all=[...items,...products,...relics];
if(items.length!==120||products.length!==32||relics.length!==80)throw Error('数量不符');
if(new Set(all.map(x=>x.id)).size!==all.length||new Set(all.map(x=>x.name)).size!==all.length)throw Error('ID或名称重复');
for(const x of all){if(!x.name||!x.effect||!x.sourceRef||!['普通','优秀','稀有','史诗'].includes(x.quality))throw Error(`字段不完整:${x.id}`);}
for(const x of items){if(!x.limit||!Number.isFinite(x.base)||!x.timing)throw Error(`物品字段不完整:${x.id}`);}
for(const x of relics){if(!x.limit||!x.timing)throw Error(`遗物字段不完整:${x.id}`);}
for(const name of pilot)if(!items.some(x=>x.name===name))throw Error(`首测条目缺失:${name}`);
const expectedScores=[16,18,48,8,8,11,19,24];
examples.forEach((x,i)=>{const n=Math.floor((x[1]+x[2])*(1+x[3]))+x[4];if(n!==expectedScores[i])throw Error('算例不一致:'+x[0]);});
const colors={ink:'#20334D',header:'#344D6D',muted:'#52627A',rule:'#D7DFE8',stripe:'#F3F6FA',green:'#3B6B54',amber:'#FFF2CC'};
const wb=Workbook.create();
const col=n=>{let a='';for(n++;n;n=Math.floor((n-1)/26))a=String.fromCharCode(65+(n-1)%26)+a;return a;};
function sheet(name,title,subtitle,headers,rows,widths,tableName,heights=64){
 const s=wb.worksheets.add(name);s.showGridLines=false;
 const end=col(headers.length-1),last=rows.length+5;
 const r=s.getRange(`A1:${end}${last}`);r.format.font={name:'Microsoft YaHei',size:10,color:colors.ink};
 r.format.verticalAlignment='center';r.format.wrapText=true;
 s.getRange('A2').values=[[title]];s.getRange('A2').format.font={size:16,bold:true,color:colors.ink};
 s.getRange('A3').values=[[subtitle]];s.getRange('A3').format.font={size:10,color:colors.muted};s.getRange('A2:'+end+'3').format.wrapText=false;
 s.getRange(`A4:${end}4`).format.borders={bottom:{style:'thin',color:colors.rule}};
 s.getRange(`A5:${end}5`).values=[headers];s.getRange(`A6:${end}${last}`).values=rows;
 s.tables.add(`A5:${end}${last}`,true,tableName);
 s.getRange(`A5:${end}5`).format={fill:colors.header,font:{name:'Microsoft YaHei',size:10,bold:true,color:'#FFFFFF'},rowHeight:30,horizontalAlignment:'center',verticalAlignment:'center',wrapText:true};
 rows.forEach((row,i)=>{
  const lines=Math.max(...row.map((v,j)=>Math.ceil([...String(v??'')].reduce((n,c)=>n+(c.charCodeAt(0)>255?1.7:0.85),0)/(widths[j]-2))));
  s.getRange(`A${i+6}:${end}${i+6}`).format.rowHeight=Math.max(30,lines*14+10);
 });
 for(let i=0;i<widths.length;i++)s.getRange(`${col(i)}1:${col(i)}${last}`).format.columnWidth=widths[i];
 for(let r=6;r<=last;r++)if(r%2===0)s.getRange(`A${r}:${end}${r}`).format.fill=colors.stripe;
 s.freezePanes.freezeRows(5);s.freezePanes.freezeColumns(2);s.tabColor=colors.header;
 return s;
}
const itemRows=items.map(x=>[x.id,x.name,x.quality,x.base,x.timing,x.effect,x.limit,x.family,x.tags,x.shape,x.standardShape,x.sourceRef,pilot.has(x.name)?'首测候选':'扩展']);
const sItems=sheet('物品','瓶内物品设计','120件可抽取物品；数值为首轮测试值。规则口径与原表来源见“规则”。',['ID','名称','品质','基础分','触发时机','效果','次数与边界','主流派','标签','外观形状','标准形状','原表参考','测试批次'],itemRows,[8,17,9,9,16,62,35,10,28,16,13,42,12],'Items',72);
sItems.getRange('D6:D125').setNumberFormat('0');
const sRelics=sheet('遗物','遗物设计','80件遗物；每5回合通过三选一获取。遗物在瓶外生效。',['ID','名称','品质','触发时机','效果','次数与边界','主流派','原表参考'],relics.map(x=>[x.id,x.name,x.quality,x.timing,x.effect,x.limit,x.family,x.sourceRef]),[8,19,9,18,68,40,11,46],'Relics',76);
const sProducts=sheet('产物与进阶','产物与进阶物','30种临时产物，2种永久进阶物；不进入常规三选一。',['ID','名称','品质','基础分','能力','来源','存续','主流派','标签','外观形状','标准形状','原表参考'],products.map(x=>[x.id,x.name,x.quality,x.base,x.effect,x.origin,x.persistence,x.family,x.tags,x.shape,x.standardShape,x.sourceRef]),[8,17,9,9,58,42,34,10,27,15,13,42],'Products',74);
sProducts.getRange('D6:D37').setNumberFormat('0');
const sBuilds=sheet('流派组合','12套组合路线','每套配置为16件样本，每件按主要作用只计1次；实际入瓶仍随机抽取。',['流派','得分方式','起步组件','中期组件','核心','推荐遗物','玩家如何安排接触','跨流派搭配','代价与冲突','16件样本比例','局部算例','首测候选'],builds,[12,28,34,34,25,39,63,47,49,37,62,48],'Builds',124);
const sRules=sheet('规则','规则口径与来源','“已确认”来自本轮会话；“设计约定”是本表为消除歧义提出的具体口径。',['状态','条目','内容'],rules,[14,24,120],'Rules',74);
for(let i=0;i<rules.length;i++){
 if(rules[i][0]==='待定')sRules.getRange(`A${i+6}:C${i+6}`).format.fill=colors.amber;
 if(rules[i][0]==='已确认')sRules.getRange(`A${i+6}`).format.font={color:colors.green,bold:true};
}
const sMap=sheet('原机制适配','原机制适配','借鉴机制后重新设计，原版未说明的效果不作推断。',['原表机制','本作设计','适配说明','参考条目'],mappings,[22,29,75,51],'Mappings',62);
const exStart=5;
const exHeaders=['算例','冻结值F','结算加分A','倍率增量M','事件记分E','计算结果','说明'];
const sExamples=sheet('结算算例','结算算例','只计算所述组件贡献；修改数值后，计算结果会随公式更新。',['算例','冻结值F','结算加分A','倍率增量M','事件记分E','计算结果','说明'],examples.map(x=>[x[0],x[1],x[2],x[3],x[4],null,x[5]]),[31,13,15,15,15,14,58],'ScoreExamples',42);
for(let i=0;i<examples.length;i++){
 const r=exStart+i+1;
 sExamples.getRange(`F${r}`).formulas=[[`=ROUNDDOWN((B${r}+C${r})*(1+D${r}),0)+E${r}`]];
}
sExamples.getRange('D6:D13').setNumberFormat('0%');sExamples.getRange('B6:C13').setNumberFormat('0');sExamples.getRange('E6:F13').setNumberFormat('0');
for(const [s,qcol,last]of [[sItems,'C',125],[sRelics,'C',85],[sProducts,'C',37]]){
 s.getRange(`${qcol}6:${qcol}${last}`).conditionalFormats.add('containsText',{text:'稀有',format:{fill:'#DDEBFA',font:{color:'#194F87'}}});
 s.getRange(`${qcol}6:${qcol}${last}`).conditionalFormats.add('containsText',{text:'史诗',format:{fill:'#EADFF4',font:{color:'#68408D'}}});
 s.getRange(`${qcol}6:${qcol}${last}`).conditionalFormats.add('containsText',{text:'优秀',format:{fill:'#E1EFE5',font:{color:'#2A663D'}}});
}
wb.recalculate();
console.log((await wb.inspect({kind:'region',sheetId:'结算算例',range:'A5:G13',maxChars:4500,tableMaxRows:9,tableMaxCols:7})).ndjson);
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!',options:{useRegex:true,maxResults:30},maxChars:2000})).ndjson);
await fs.mkdir(path.join(out,'previews'),{recursive:true});
for(const [sheetName,range,file]of [
 ['物品','A2:G9','items'],['物品','H5:M9','items-fields'],['遗物','A2:F9','relics'],
 ['产物与进阶','A2:G9','products'],['流派组合','A2:D8','builds'],
 ['规则','A2:C11','rules'],['原机制适配','A2:D9','mapping'],['结算算例','A2:G13','examples']
]){
 const blob=await wb.render({sheetName,range,scale:1,format:'png'});
 await fs.writeFile(path.join(out,'previews',file+'.png'),new Uint8Array(await blob.arrayBuffer()));
}
const output=await SpreadsheetFile.exportXlsx(wb);await output.save(path.join(out,'ShakeHero_物品与遗物设计.xlsx'));
await fs.writeFile(path.join(out,'design-data.json'),JSON.stringify({items,products,relics,rules,builds,mappings,examples},null,2),'utf8');
const report={items:items.length,products:products.length,relics:relics.length,builds:builds.length,pilotItems:pilot.size,unknownSourceEffectsUsed:0,sourceRows:{triggers:source['触发器'].length-1,boons:source['增益'].length-1},examples:expectedScores};
await fs.writeFile(path.join(out,'validation.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
