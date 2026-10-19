import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
import {data,old,counts,audit,removedIds} from './revision-v5.mjs';
const out=path.dirname(fileURLToPath(import.meta.url));
const assert=(p,m)=>{if(!p)throw Error(m);};
const {items,relics,rules,builds,mappings,examples}=data;
const byId=new Map([...items,...relics].map(x=>[x.id,x]));
assert(byId.size===items.length+relics.length,'ID重复');
assert(audit.length===231,'审查遗漏');
assert(items.length===125&&relics.length===61,'目录数量');
assert(removedIds.every(id=>!byId.has(id)),'移除失败');
const deadNames=[...old.items,...old.relics].filter(x=>removedIds.includes(x.id)).map(x=>x.name);
for(const x of [...items,...relics]){
 assert(x.name&&x.effect&&x.timing&&x.limit&&x.sourceRef,'空字段 '+x.id);
 const active=[x.name,x.effect,x.limit,x.acquisition].join('|');
 assert(!/临时，生成|收存|记分|当前值|冻结值|生产|直接直接/.test(active),'旧术语 '+x.id);
 for(const n of deadNames)assert(!active.includes(n),'退役引用 '+x.id+':'+n);
}
for(const x of items){assert(typeof x.base==='number'&&x.base>=0,'基础分 '+x.id);assert(x.inDraftPool==='否'||x.lifetime==='永久','临时进入奖励池 '+x.id);}
for(const b of builds){
 assert([...b[9].matchAll(/\d+/g)].reduce((s,m)=>s+ +m[0],0)===16,'样本比例 '+b[0]);
 for(const c of [2,3,4])for(const n of b[c].split('、'))assert(items.some(x=>x.name===n),'物品引用 '+n);
 for(const n of b[5].split('、'))assert(relics.some(x=>x.name===n),'遗物引用 '+n);
 for(const n of b[11].replace(/^先测/,'').split('、'))assert(items.some(x=>x.name===n),'首测引用 '+n);
}
for(const rows of [rules,builds,mappings,examples])for(const r of rows)for(const s of r)if(typeof s==='string')for(const n of deadNames)assert(!s.includes(n),'说明退役引用 '+n);
const acquisitionEdges={I031:['I035'],I097:['R047'],P001:['I004','I085'],P003:['I011','I042','R008','R022'],P004:['I012'],P005:['I014','I085'],P006:['I015','I085'],P007:['I018','I085'],P008:['I021','I022','I085'],P009:['I024','I085'],P010:['I025','I121','I085'],P011:['I027'],P012:['I026'],P013:['I036'],P014:['I037','I040','I098','I085'],P015:['I037','I085'],P016:['I038','I085'],P017:['I045'],P018:['I049'],P019:['I050'],P020:['I100','I085'],P021:['I067'],P022:['I071','I074'],P023:['I076'],P024:['I098','I085'],P025:['I100','I085'],P026:['I115'],P027:['R003'],P028:['R007'],P029:['R012','I085'],P030:['R017'],P032:['R053']};
for(const [id,sources]of Object.entries(acquisitionEdges))for(const source of sources){assert(byId.has(source),'来源缺失 '+id+':'+source);assert(byId.get(id).acquisition.includes(byId.get(source).name),'来源栏不同步 '+id+':'+source);}
assert(items.filter(x=>x.id.startsWith('P')).every(x=>acquisitionEdges[x.id]),'产物来源遗漏');
assert(byId.get('P019').tags==='蒸汽'&&byId.get('P028').tags==='花粉','产物标签');
assert(['I002','I023','P005','P006','P028'].every(id=>!byId.get(id).tags.split('、').includes('植物')),'植物标签');
assert(byId.get('I035').effect.includes('原矿')&&!byId.get('I035').tags.includes('矿石'),'岩脉与原矿区分');
assert(!byId.get('I052').tags.includes('动物'),'摆件标签');
assert(['P026','P027','P030','P032'].every(id=>!byId.get(id).acquisition.includes('黄玉')),'追加或变形不能重复追加');
const scores=examples.map(x=>Math.floor((x[1]+x[2])*(1+x[3]))+x[4]);
assert(JSON.stringify(scores)==='[7,18,48,9,8,12,19,24]','算例');
const pilots=new Set(builds.flatMap(x=>x[11].replace(/^先测/,'').split('、')));
for(const x of items)x.pilot=x.inDraftPool==='否'?'随来源测试':pilots.has(x.name)?'首测候选':'扩展';
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(path.join(out,'ShakeHero_物品与遗物设计_V4.xlsx')));
const col=n=>{let a='';for(n++;n;n=Math.floor((n-1)/26))a=String.fromCharCode(65+(n-1)%26)+a;return a;};
function edit(name,title,subtitle,rows,widths,tableName,previousRows,headers){
 const s=headers?wb.worksheets.add(name):wb.worksheets.getItem(name),end=col(widths.length-1),last=rows.length+5;
 if(headers){s.showGridLines=false;s.getRange(`A5:${end}5`).values=[headers];s.freezePanes.freezeRows(5);s.freezePanes.freezeColumns(2);}
 s.getRange(`A2:${end}2`).merge();s.getRange(`A3:${end}3`).merge();
 s.getRange('A2').values=[[title]];s.getRange('A3').values=[[subtitle]];
 s.getRange(`A2:${end}2`).format={font:{name:'Microsoft YaHei',size:16,bold:true,color:'#20334D'},rowHeight:28};
 s.getRange(`A3:${end}3`).format={font:{name:'Microsoft YaHei',size:10,color:'#54677E'},rowHeight:32,wrapText:true};
 s.getRange(`A4:${end}4`).format.borders={bottom:{style:'thin',color:'#D7DFE8'}};
 for(const t of [...s.tables.items])t.delete();
 if(previousRows>rows.length)s.getRange(`A${last+1}:${end}${previousRows+5}`).clear({applyTo:'all'});
 s.getRange(`A6:${end}${last}`).values=rows;
 s.tables.add(`A5:${end}${last}`,true,tableName);
 s.getRange(`A5:${end}5`).format={fill:'#344D6D',font:{name:'Microsoft YaHei',size:10,bold:true,color:'#FFFFFF'},rowHeight:32,horizontalAlignment:'center',verticalAlignment:'center',wrapText:true};
 s.getRange(`A6:${end}${last}`).format.font={name:'Microsoft YaHei',size:10,color:'#20334D'};
 s.getRange(`A6:${end}${last}`).format.verticalAlignment='center';s.getRange(`A6:${end}${last}`).format.wrapText=true;
 widths.forEach((w,i)=>s.getRange(`${col(i)}1:${col(i)}${last}`).format.columnWidth=w);
 rows.forEach((r,i)=>{
  const lines=Math.max(...r.map((v,j)=>Math.ceil([...String(v??'')].reduce((a,c)=>a+(c.charCodeAt(0)>255?1.7:0.85),0)/(widths[j]-2))));
  s.getRange(`A${i+6}:${end}${i+6}`).format.rowHeight=Math.max(30,lines*14+10);
  s.getRange(`A${i+6}:${end}${i+6}`).format.fill=i%2===0?'#F3F6FA':'#FFFFFF';
 });return s;
}
const si=edit('物品总表','物品总表 · V5',`${counts.items}件物品：${counts.permanent}件永久、${counts.temporary}件临时；${counts.draftPool}件进入三选一。全目录审查与精简，详细决策见“审查调整”。`,items.map(x=>[x.id,x.name,x.quality,x.base,x.acquisition,x.inDraftPool,x.lifetime,x.timing,x.effect,x.limit,x.family,x.tags,x.shape,x.standardShape,x.sourceRef,x.pilot]),[8,17,9,9,53,16,10,16,62,35,10,28,16,13,42,14],'Items',old.items.length);
si.getRange(`D6:D${items.length+5}`).setNumberFormat('0');
edit('遗物','遗物设计 · V5',`${counts.relics}件遗物，合并或移除${counts.removedRelics}件重复、失去依赖或理解成本偏高的旧设计。`,relics.map(x=>[x.id,x.name,x.quality,x.timing,x.effect,x.limit,x.family,x.sourceRef]),[8,19,9,18,68,40,11,46],'Relics',old.relics.length);
edit('流派组合','12套组合路线 · V5','全部路线已同步当前物品、产物及遗物；16件样本比例用于首轮试验，不代表已验证平衡。',builds,[12,28,34,34,25,39,63,47,49,37,62,48],'Builds',old.builds.length);
const sr=edit('规则','规则口径与来源 · V5','默认永久生成、永久消耗；真实接触决定反应。统一活植物、授粉、液态水、铁材质与追加生成的判断。',rules,[14,24,120],'Rules',old.rules.length);
rules.forEach((r,i)=>{if(r[0]==='待定')sr.getRange(`A${i+6}:C${i+6}`).format.fill='#FFF2CC';sr.getRange(`A${i+6}`).format.font={color:r[0]==='已确认'?'#3B6B54':'#20334D',bold:r[0]==='已确认'};});
edit('原机制适配','原机制适配 · V5','保留参考来源；优先采用本作可直接接触、明确消耗与生成的表达。',mappings,[22,29,75,51],'Mappings',old.mappings.length);
const se=edit('结算算例','结算算例 · V5','公式仍按冻结分值、结算加分、倍率增量及直接计分计算，示例名称与当前目录同步。',examples.map(x=>[x[0],x[1],x[2],x[3],x[4],null,x[5]]),[31,13,15,15,15,14,58],'ScoreExamples',old.examples.length);
for(let i=0;i<examples.length;i++){const r=i+6;se.getRange(`F${r}`).formulas=[[`=ROUNDDOWN((B${r}+C${r})*(1+D${r}),0)+E${r}`]];}
const sa=edit('审查调整','逐项审查 · V4 → V5','完整覆盖原151件物品与80件遗物。合并表示职责收敛，不自动叠加旧效果；原效果保留原文，仅用于历史对照。',audit,[9,9,19,10,20,27,64,67,67],'ReviewLog',0,['类别','原ID','原名称','决策','当前名称／状态','职责合并至','判断依据','V4原效果（历史）','V5当前效果']);
for(const [text,fill,color]of [['调整','#DDEBFA','#194F87'],['合并','#FFF2CC','#7D5700'],['移除','#F8DEDE','#9B3636']])sa.getRange(`D6:D${audit.length+5}`).conditionalFormats.add('containsText',{text,format:{fill,font:{color}}});
wb.recalculate();
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!|#NULL!',options:{useRegex:true,maxResults:20},maxChars:700})).ndjson);
await fs.mkdir(path.join(out,'previews-v5'),{recursive:true});
const rowOf=id=>items.findIndex(x=>x.id===id)+6;
const renderSpecs=[['物品总表','A2:H10','overview'],['物品总表',`H${rowOf('I011')}:L${rowOf('I018')}`,'plants'],['物品总表',`H${rowOf('I031')}:L${rowOf('I040')}`,'mining'],['物品总表',`H${rowOf('P017')}:L${rowOf('P021')}`,'temporary'],['遗物','A6:F12','relics'],['流派组合','A8:F12','builds'],['规则',`A${rules.length+3}:C${rules.length+5}`,'rules'],['审查调整','A6:G15','audit'],['结算算例','A2:G13','examples']];
for(const [sheetName,range,file]of renderSpecs){const b=await wb.render({sheetName,range,scale:1,format:'png'});await fs.writeFile(path.join(out,'previews-v5',file+'.png'),new Uint8Array(await b.arrayBuffer()));}
await (await SpreadsheetFile.exportXlsx(wb)).save(path.join(out,'ShakeHero_物品与遗物设计_V5.xlsx'));
await fs.writeFile(path.join(out,'design-data-v5.json'),JSON.stringify(data,null,2),'utf8');
const report={...counts,reviewed:audit.length,decisions:Object.fromEntries(['保留','调整','合并','移除'].map(k=>[k,audit.filter(x=>x[3]===k).length])),removedIds,acquisitionEdges,examples:scores,terminologyScanPassed:true,buildReferencesPassed:true,acquisitionSourcesPassed:true,playtested:false};
await fs.writeFile(path.join(out,'validation-v5.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
