import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
import {data,old} from './revision-v2.mjs';
const out=path.dirname(fileURLToPath(import.meta.url));
const {items,products,relics,rules,builds,mappings,examples}=data;
const all=[...items,...products,...relics];
const assert=(p,m)=>{if(!p)throw Error(m);};
assert(items.length===120&&products.length===32&&relics.length===80,'条目数量');
assert(new Set(all.map(x=>x.id)).size===232,'ID重复');
assert(new Set(all.map(x=>x.name)).size===232,'名称重复');
for(const k of ['items','products','relics'])assert(data[k].every((x,i)=>x.id===old[k][i].id),'原ID不稳定');
const removed=/收存|存入|满载|邮戳|路径标记|效率标记|投资箱|存钱猪|储水杯|保险箱|冷热循环|存满奖励|归途|路标/;
for(const x of all){
 assert(x.name&&x.effect&&x.sourceRef&&x.revisionNote,`缺字段:${x.id}`);
 assert(!removed.test([x.name,x.effect,x.limit,x.tags].join('')),`旧机制残留:${x.id}`);
 assert(['普通','优秀','稀有','史诗'].includes(x.quality),`品质:${x.id}`);
}
for(const x of [...items,...products])assert(Number.isFinite(x.base)&&x.standardShape,`物体字段:${x.id}`);
const ephemeral=new Set(['火星','礼花','蒸汽','纸影','魂火','花粉','回声珠']);
assert(products.filter(x=>x.lifetime==='临时').length===7,'临时产物数量');
assert(products.every(x=>(x.lifetime==='临时')===ephemeral.has(x.name)),'临时产物名单');
for(const x of [...items,...relics]){
 if(/生成[^。；]*?(火星|礼花|蒸汽|纸影|魂火|花粉|回声珠)/.test(x.effect)&&!x.effect.startsWith('本回合第一次正常生成蒸汽'))
  assert(x.effect.includes('临时生成'),`临时来源未明写:${x.id}`);
}
for(const b of builds){
 assert(b.length===12,`流派列数:${b[0]}`);
 assert([...b[9].matchAll(/\d+/g)].reduce((s,m)=>s+Number(m[0]),0)===16,`流派样本不为16:${b[0]}`);
 for(const c of [2,3,4])for(const name of b[c].split('、'))assert(items.some(x=>x.name===name),`流派组件缺失:${name}`);
 for(const name of b[5].split('、'))assert(relics.some(x=>x.name===name),`遗物引用缺失:${name}`);
}
const pilot=new Set(builds.flatMap(x=>x[11].replace('先测','').split('、')));
for(const n of pilot)assert(items.some(x=>x.name===n),`首测物品缺失:${n}`);
const scores=examples.map(x=>Math.floor((x[1]+x[2])*(1+x[3]))+x[4]);
assert(JSON.stringify(scores)==='[7,18,48,9,8,12,19,24]','结算算例错误');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(path.join(out,'ShakeHero_物品与遗物设计.xlsx')));
await fs.mkdir(path.join(out,'previews-v2'),{recursive:true});
const before=await wb.render({sheetName:'物品',range:'A54:G60',scale:1,format:'png'});
await fs.writeFile(path.join(out,'previews-v2','before-market.png'),new Uint8Array(await before.arrayBuffer()));
const col=n=>{let a='';for(n++;n;n=Math.floor((n-1)/26))a=String.fromCharCode(65+(n-1)%26)+a;return a;};
function edit(name,title,subtitle,rows,widths){
 const s=wb.worksheets.getItem(name),end=col(widths.length-1),last=rows.length+5;
 s.getRange('A2').values=[[title]];
 s.getRange('A3').values=[[subtitle]];
 s.getRange(`A6:${end}${last}`).values=rows;
 rows.forEach((r,i)=>{
  const lines=Math.max(...r.map((v,j)=>Math.ceil([...String(v??'')].reduce((n,c)=>n+(c.charCodeAt(0)>255?1.7:0.85),0)/(widths[j]-2))));
  s.getRange(`A${i+6}:${end}${i+6}`).format.rowHeight=Math.max(30,lines*14+10);
 });
 return s;
}
edit('物品','瓶内物品设计 · V2','120件物品｜生成、消耗默认永久；临时例外明写。保留原ID，首轮测试数值。',items.map(x=>[x.id,x.name,x.quality,x.base,x.timing,x.effect,x.limit,x.family,x.tags,x.shape,x.standardShape,x.sourceRef,pilot.has(x.name)?'首测候选':'扩展']),[8,17,9,9,16,62,35,10,28,16,13,42,12]);
edit('遗物','遗物设计 · V2','80件遗物｜每5回合三选一；全部按永久牌库增删及直接接触复核。',relics.map(x=>[x.id,x.name,x.quality,x.timing,x.effect,x.limit,x.family,x.sourceRef]),[8,19,9,18,68,40,11,46]);
edit('产物与进阶','产物与进阶 · V2','22种永久生成产物＋3种永久进阶＋7种临时产物；均不进入常规三选一。',products.map(x=>[x.id,x.name,x.quality,x.base,x.effect,x.origin,x.persistence,x.family,x.tags,x.shape,x.standardShape,x.sourceRef]),[8,17,9,9,58,42,34,10,27,15,13,42]);
edit('流派组合','12套组合路线 · V2','每套16件为抽样搭配示例；重点核对长期牌库增减与当回合得分。',builds,[12,28,34,34,25,39,63,47,49,37,62,48]);
const sr=edit('规则','规则口径与来源 · V2','已确认=用户新规则；设计约定=本表具体解释；待定=需要原型验证。',rules,[14,24,120]);
rules.forEach((r,i)=>{
 const row=i+6;
 sr.getRange(`A${row}:C${row}`).format.fill=r[0]==='待定'?'#FFF2CC':row%2===0?'#F3F6FA':'#FFFFFF';
 sr.getRange(`A${row}`).format.font={color:r[0]==='已确认'?'#3B6B54':'#20334D',bold:r[0]==='已确认'};
});
edit('原机制适配','原机制适配 · V2','沿用飞书参考条目；对应本作永久牌库、真实接触和10秒结算。',mappings,[22,29,75,51]);
const se=edit('结算算例','结算算例 · V2','仅计算所述组件贡献；同步说明永久牌库变化，结果列使用公式。',examples.map(x=>[x[0],x[1],x[2],x[3],x[4],null,x[5]]),[31,13,15,15,15,14,58]);
for(let i=0;i<examples.length;i++){const r=i+6;se.getRange(`F${r}`).formulas=[[`=ROUNDDOWN((B${r}+C${r})*(1+D${r}),0)+E${r}`]];}
wb.recalculate();
console.log((await wb.inspect({kind:'region',sheetId:'结算算例',range:'A5:G13',maxChars:4800,tableMaxRows:9,tableMaxCols:7})).ndjson);
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!',options:{useRegex:true,maxResults:30},maxChars:1000})).ndjson);
for(const [sheetName,range,file]of [
 ['物品','A2:G11','items'],['物品','A56:G65','market'],['物品','A76:G85','soul'],['物品','H55:M61','fields'],
 ['遗物','A29:F35','relics'],['产物与进阶','A2:G10','products'],['产物与进阶','B20:G29','products-lifetime'],
 ['流派组合','A2:F8','builds'],['流派组合','G10:L11','build-market'],['规则','A2:C11','rules'],['规则','A18:C22','discard'],
 ['原机制适配','A2:D9','mapping'],['结算算例','A2:G13','examples']
]){
 const b=await wb.render({sheetName,range,scale:1,format:'png'});
 await fs.writeFile(path.join(out,'previews-v2',file+'.png'),new Uint8Array(await b.arrayBuffer()));
}
await (await SpreadsheetFile.exportXlsx(wb)).save(path.join(out,'ShakeHero_物品与遗物设计_V2.xlsx'));
await fs.writeFile(path.join(out,'design-data-v2.json'),JSON.stringify(data,null,2),'utf8');
const report={items:120,products:32,relics:80,reviewed:232,permanentProducts:22,permanentUpgrades:3,temporaryProducts:7,builds:12,pilot:pilot.size,unchangedIds:true,removedMechanicsInActiveEffects:0,examples:scores,playtested:false,changedBySection:Object.fromEntries(['items','products','relics'].map(k=>[k,data[k].filter((x,i)=>['name','base','timing','effect','limit','tags','family','origin','persistence','shape'].some(f=>x[f]!==old[k][i][f])).length]))};
await fs.writeFile(path.join(out,'validation-v2.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify(report));
