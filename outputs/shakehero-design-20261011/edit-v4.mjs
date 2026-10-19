import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
import {data,old} from './revision-v4.mjs';
const out=path.dirname(fileURLToPath(import.meta.url));
const assert=(p,m)=>{if(!p)throw Error(m);};
const {items,relics,rules,builds,mappings,examples}=data;
assert(items.length===151&&relics.length===80,'条目数量');
assert(new Set([...items,...relics].map(x=>x.id)).size===231,'ID重复');
assert(items.filter(x=>x.inDraftPool==='是').length===120,'奖励池');
assert(items.filter(x=>x.lifetime==='永久').length===144,'永久物品');
assert(items.filter(x=>x.lifetime==='临时').length===7,'临时物品');
assert(!items.some(x=>['I009','P002'].includes(x.id))&&items.some(x=>x.id==='I121'),'移除新增');
for(const x of [...items,...relics]){
 assert(!/记分|自己|当前值|冻结值|生产|返还|本回合\+|消耗\d[电充]|直接直接/.test(x.effect+' '+x.limit),'旧术语:'+x.id);
 assert(!/烤面包架|烤吐司/.test([x.name,x.effect,x.limit,x.acquisition].join('')),'旧引用:'+x.id);
 assert(x.name&&x.effect&&x.timing&&x.limit&&x.sourceRef,'空字段:'+x.id);
}
for(const b of builds){
 assert([...b[9].matchAll(/\d+/g)].reduce((s,m)=>s+ +m[0],0)===16,'样本比例:'+b[0]);
 for(const c of [2,3,4])for(const n of b[c].split('、'))assert(items.some(x=>x.name===n),'组合引用:'+n);
 for(const n of b[5].split('、'))assert(relics.some(x=>x.name===n),'遗物引用:'+n);
}
const scores=examples.map(x=>Math.floor((x[1]+x[2])*(1+x[3]))+x[4]);
assert(JSON.stringify(scores)==='[7,18,48,9,8,12,19,24]','算例');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(path.join(out,'ShakeHero_物品与遗物设计_V3.xlsx')));
const col=n=>{let a='';for(n++;n;n=Math.floor((n-1)/26))a=String.fromCharCode(65+(n-1)%26)+a;return a;};
function edit(name,title,subtitle,rows,widths,tableName,previousRows){
 const s=wb.worksheets.getItem(name),end=col(widths.length-1),last=rows.length+5;
 s.getRange('A2').values=[[title]];s.getRange('A3').values=[[subtitle]];
 if(previousRows!==rows.length){
  for(const t of [...s.tables.items])t.delete();
  if(previousRows>rows.length)s.getRange(`A${last+1}:${end}${previousRows+5}`).clear({applyTo:'all'});
 }
 s.getRange(`A6:${end}${last}`).values=rows;
 if(previousRows!==rows.length)s.tables.add(`A5:${end}${last}`,true,tableName);
 s.getRange(`A6:${end}${last}`).format.font={name:'Microsoft YaHei',size:10,color:'#20334D'};
 s.getRange(`A6:${end}${last}`).format.verticalAlignment='center';
 s.getRange(`A6:${end}${last}`).format.wrapText=true;
 rows.forEach((r,i)=>{
  const lines=Math.max(...r.map((v,j)=>Math.ceil([...String(v??'')].reduce((a,c)=>a+(c.charCodeAt(0)>255?1.7:0.85),0)/(widths[j]-2))));
  s.getRange(`A${i+6}:${end}${i+6}`).format.rowHeight=Math.max(30,lines*14+10);
  s.getRange(`A${i+6}:${end}${i+6}`).format.fill=(i+6)%2===0?'#F3F6FA':'#FFFFFF';
 });
 return s;
}
const si=edit('物品总表','物品总表 · V4','151件物品，144件永久、7件临时。三选一池120件。统一术语，收窄鸟巢与绵羊条件，精简重复加工。',items.map(x=>[x.id,x.name,x.quality,x.base,x.acquisition,x.inDraftPool,x.lifetime,x.timing,x.effect,x.limit,x.family,x.tags,x.shape,x.standardShape,x.sourceRef,x.pilot]),[8,17,9,9,53,16,10,16,62,35,10,28,16,13,42,14],'Items',old.items.length);
si.getRange('D6:D156').setNumberFormat('0');
edit('遗物','遗物设计 · V4','80件遗物，统一使用接触、消耗、生成、增值、直接计分与结算倍率。',relics.map(x=>[x.id,x.name,x.quality,x.timing,x.effect,x.limit,x.family,x.sourceRef]),[8,19,9,18,68,40,11,46],'Relics',old.relics.length);
edit('流派组合','12套组合路线 · V4','烹饪保留平底锅加工入口，牧场使用母鸡与鸟巢、绵羊与剪毛剪的明确配对。',builds,[12,28,34,34,25,39,63,47,49,37,62,48],'Builds',old.builds.length);
const sr=edit('规则','规则口径与来源 · V4','区分接触时、结算时接触、接触历史。卡面标准句式及新增条目见表内说明。',rules,[14,24,120],'Rules',old.rules.length);
rules.forEach((r,i)=>{
 if(r[0]==='待定')sr.getRange(`A${i+6}:C${i+6}`).format.fill='#FFF2CC';
 sr.getRange(`A${i+6}`).format.font={color:r[0]==='已确认'?'#3B6B54':'#20334D',bold:r[0]==='已确认'};
});
edit('原机制适配','原机制适配 · V4','保留来源引用，统一本作术语与触发条件表述。',mappings,[22,29,75,51],'Mappings',old.mappings.length);
const se=edit('结算算例','结算算例 · V4','分值、直接计分与结算倍率分开描述，结果列保留公式。',examples.map(x=>[x[0],x[1],x[2],x[3],x[4],null,x[5]]),[31,13,15,15,15,14,58],'ScoreExamples',old.examples.length);
se.getRange('A5:G5').values=[['算例','冻结分值F','结算加分A','结算倍率增量M','直接计分E','计算结果','说明']];
for(let i=0;i<examples.length;i++){const r=i+6;se.getRange(`F${r}`).formulas=[[`=ROUNDDOWN((B${r}+C${r})*(1+D${r}),0)+E${r}`]];}
wb.recalculate();
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!|#NULL!',options:{useRegex:true,maxResults:20},maxChars:700})).ndjson);
await fs.mkdir(path.join(out,'previews-v4'),{recursive:true});
for(const [sheetName,range,file]of [
 ['物品总表','H6:J15','cooking'],['物品总表','H25:J32','pasture'],['物品总表','A122:H127','shears'],
 ['物品总表','H122:J127','shears-effect'],['遗物','A2:F10','relics'],['流派组合','A2:F8','builds'],
 ['规则','A36:C39','terms'],['规则','A12:C16','rules'],['原机制适配','A2:D8','mapping'],['结算算例','A2:G13','examples']
]){
 const b=await wb.render({sheetName,range,scale:1,format:'png'});
 await fs.writeFile(path.join(out,'previews-v4',file+'.png'),new Uint8Array(await b.arrayBuffer()));
}
await (await SpreadsheetFile.exportXlsx(wb)).save(path.join(out,'ShakeHero_物品与遗物设计_V4.xlsx'));
await fs.writeFile(path.join(out,'design-data-v4.json'),JSON.stringify(data,null,2),'utf8');
const report={items:items.length,relics:relics.length,draftPool:120,permanent:144,temporary:7,removedIds:['I009','P002'],newIds:['I121'],examples:scores,terminologyScanPassed:true,buildReferencesPassed:true,playtested:false};
await fs.writeFile(path.join(out,'validation-v4.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify(report));
