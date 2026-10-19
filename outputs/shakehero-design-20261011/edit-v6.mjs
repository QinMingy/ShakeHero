import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
import {data,old,counts,loops,balances,auditCurrent,changedIds} from './revision-v6.mjs';
const out=path.dirname(fileURLToPath(import.meta.url));
const assert=(p,m)=>{if(!p)throw Error(m);};
const {items,relics,rules,builds,mappings,examples,audit}=data;
const byId=new Map([...items,...relics].map(x=>[x.id,x]));
assert(items.length===126&&relics.length===61&&byId.size===187,'数量/ID');
assert(!byId.has('I027')&&byId.has('I122')&&byId.has('I123'),'删除与新增');
assert(auditCurrent.length===188&&audit.length===419,'逐项覆盖');
const oldReport=JSON.parse(await fs.readFile(path.join(out,'validation-v5.json'),'utf8'));
const edges=structuredClone(oldReport.acquisitionEdges);
Object.assign(edges,{I023:['I123'],I033:['I035'],I034:['I035'],P003:['I011','I122','I042','R008','R022'],P011:['P008','P029'],P022:['I071','I074','P021']});
for(const [id,sources]of Object.entries(edges))for(const source of sources){assert(byId.has(source),'来源退役 '+id);assert(byId.get(id).acquisition.includes(byId.get(source).name),'来源不同步 '+id+':'+source);}
assert(items.filter(x=>x.inDraftPool==='否').every(x=>edges[x.id]),'产物缺来源');
for(const x of [...items,...relics]){
 assert(x.name&&x.effect&&x.limit&&x.timing&&x.sourceRef,'缺字段 '+x.id);
 assert(!/孵化器|雏鸟|临时，生成|记分|当前值|冻结值|直接直接/.test([x.name,x.effect,x.limit,x.acquisition].join('|')),'旧描述 '+x.id);
}
for(const x of items){assert(typeof x.base==='number','基础分类型');assert(x.inDraftPool==='否'||x.lifetime==='永久','奖励池存续');}
for(const b of builds){
 assert([...b[9].matchAll(/\d+/g)].reduce((s,m)=>s+ +m[0],0)===16,'样本配比 '+b[0]);
 for(const c of [2,3,4])for(const n of b[c].split('、'))assert(items.some(x=>x.name===n),'物品引用 '+n);
 for(const n of b[5].split('、'))assert(relics.some(x=>x.name===n),'遗物引用 '+n);
 for(const n of b[11].replace(/^先测/,'').split('、'))assert(items.some(x=>x.name===n),'首测引用 '+n);
}
for(const k of ['builds','mappings','examples','loops'])assert(!/孵化器|雏鸟|加热/.test(JSON.stringify(data[k])),'旧依赖 '+k);
const pilots=new Set(builds.flatMap(x=>x[11].replace(/^先测/,'').split('、')));
for(const x of items)x.pilot=x.inDraftPool==='否'?'随来源测试':pilots.has(x.name)||['I122','I123'].includes(x.id)?'首测候选':'扩展';
// 资源收支按事件序列独立复算，避免总数正确但生成/消耗分项错误。
const recipes={cloud:{add:{water:2},cap:1},vine:{take:{water:1},add:{grape:2},cap:1},mouth:{take:{grape:1},cap:2},sponge:{take:{water:1},cap:2},field:{take:{water:1},add:{grain:2},cap:1},hen:{take:{grain:1},add:{egg:2},cap:1},cow:{take:{grain:1},add:{milk:1},cap:1},boiler:{take:{water:1},add:{steam:1},cap:2},condense:{add:{water:1},cap:2},pump:{add:{water:1},cap:2},sheep:{add:{wool:1},cap:1},auction:{take:{wool:1},cap:1},vein:{add:{ore:1},cap:1},pick:{take:{ore:1},add:{sand:2},cap:1},sieve:{take:{sand:1},add:{gem:1},cap:2},copy:{add:{paper:1},cap:2},burn:{take:{paper:1},add:{ghost:1,soulfire:1},cap:2},soul:{take:{ghost:1},cap:2},reward:{add:{reward:1},cap:1}};
const temporary=new Set(['steam','paper','soulfire']);
recipes.portal={add:{ghost:1},cap:1};
function run(steps,initial={}){
 const state={...initial},used={},counts=[0,0,0,0,0,0];
 for(const step of steps){const r=recipes[step];assert(r,'未知配方');assert((used[step]||0)<r.cap,'超过次数 '+step);used[step]=(used[step]||0)+1;
  for(const [id,n]of Object.entries(r.take||{})){assert((state[id]||0)>=n,'缺原料 '+step);state[id]-=n;counts[temporary.has(id)?3:1]+=n;if(id==='water')counts[5]+=n;}
  for(const [id,n]of Object.entries(r.add||{})){state[id]=(state[id]||0)+n;counts[temporary.has(id)?2:0]+=n;if(id==='water')counts[4]+=n;}
 }return{counts,state};
}
const programs=[
 [['cloud','vine','mouth','mouth'],{}],
 [['cloud','vine','mouth','mouth','sponge'],{}],
 [['cloud','field','hen','cow'],{}],
 [['cloud','vine','field'],{}],
 [['boiler','condense','boiler','condense'],{water:1}],
 [['boiler','boiler'],{water:2}],
 [['pump','pump'],{}],
 [['sheep','auction'],{}],
 [['vein','pick','sieve','sieve'],{}],
 [['copy','burn','soul','copy','burn','soul'],{}],
 [[],{egg:1}],
 [['reward'],{}],
 [['portal','soul'],{}],
];
programs.forEach(([s,initial],i)=>assert(JSON.stringify(run(s,initial).counts)===JSON.stringify(balances[i].slice(2,8)),'收支分项 '+i));
// 水泵初始充能及节能齿轮的回用上限。
function pumpModel(initial,refill,external){let charge=initial,water=0,spent=0,refunded=false;const drain=()=>{while(charge>0&&water<2){charge--;water++;spent++;if(refill&&!refunded){refunded=true;charge++;}}};drain();for(const c of external){charge=Math.min(5,charge+c);drain();}return{water,charge,spent};}
assert(pumpModel(1,false,[]).water===1,'泵初始产量');
assert(pumpModel(1,false,[1]).water===2,'泵补能');
assert(pumpModel(1,true,[1,1,1]).water===2,'返充不得突破产量');
assert(pumpModel(5,true,[5,5]).water===2,'高充能不得突破产量');
// 生存次数不等于全局轮数；变形后的8分不能追溯到第三次蛋结算。
function eggStep(progress,{inBottle=true,alive=true,double=false}={}){if(!inBottle||!alive)return{progress,type:'蛋',score:0};const next=progress+1;return{progress:Math.min(next,3),type:next>=3?'雏鸡':'蛋',score:double?5:2};}
assert(eggStep(0).progress===1,'新蛋首轮计次');
assert(eggStep(1,{inBottle:false}).progress===1,'未抽到不计次');
assert(eggStep(2,{alive:false}).progress===2,'消耗不计次');
assert(eggStep(2).type==='雏鸡'&&eggStep(2).score===2,'第三次按蛋结算');
assert(eggStep(2,{double:true}).type==='雏鸡'&&eggStep(2,{double:true}).score===5,'双黄蛋边界');
const results=examples.map(x=>Math.floor((x[1]+x[2])*(1+x[3]))+x[4]);
assert(JSON.stringify(results)==='[7,18,48,9,8,12,19,24,2,12]','结算算例');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(path.join(out,'ShakeHero_物品与遗物设计_V5.xlsx')));
const col=n=>{let a='';for(n++;n;n=Math.floor((n-1)/26))a=String.fromCharCode(65+(n-1)%26)+a;return a;};
const bodyFont={name:'Microsoft YaHei',size:10,color:'#20334D'};
const headerFormat={fill:'#344D6D',font:{...bodyFont,bold:true,color:'#FFFFFF'},rowHeight:40,horizontalAlignment:'center',verticalAlignment:'center',wrapText:true};
function body(s,address,rows,widths,start){s.getRange(address).format={font:bodyFont,verticalAlignment:'center',wrapText:true};rows.forEach((r,i)=>{const lines=Math.max(...r.map((v,j)=>Math.ceil([...String(v??'')].reduce((a,c)=>a+(c.charCodeAt(0)>255?1.7:0.85),0)/(widths[j]-2))));s.getRange(`A${start+i}:${col(widths.length-1)}${start+i}`).format.rowHeight=Math.max(30,lines*14+10);s.getRange(`A${start+i}:${col(widths.length-1)}${start+i}`).format.fill=i%2===0?'#F3F6FA':'#FFFFFF';});}
function edit(name,title,subtitle,rows,widths,tableName,previousRows,{headers,newSheet=false,oldCols=widths.length}={}){
 const s=newSheet?wb.worksheets.add(name):wb.worksheets.getItem(name),end=col(widths.length-1),last=rows.length+5;
 if(newSheet){s.showGridLines=false;s.freezePanes.freezeRows(5);s.freezePanes.freezeColumns(2);}else{s.getRange(`A2:${col(oldCols-1)}2`).unmerge();s.getRange(`A3:${col(oldCols-1)}3`).unmerge();}
 s.getRange(`A2:${end}2`).merge();s.getRange(`A3:${end}3`).merge();
 s.getRange('A2').values=[[title]];s.getRange('A3').values=[[subtitle]];
 s.getRange(`A2:${end}2`).format={font:{...bodyFont,size:16,bold:true},rowHeight:28};
 s.getRange(`A3:${end}3`).format={font:{...bodyFont,color:'#54677E'},rowHeight:34,wrapText:true};
 for(const t of [...s.tables.items])t.delete();
 if(previousRows>rows.length)s.getRange(`A${last+1}:${end}${previousRows+5}`).clear({applyTo:'all'});
 if(headers)s.getRange(`A5:${end}5`).values=[headers];
 s.getRange(`A6:${end}${last}`).values=rows;
 s.tables.add(`A5:${end}${last}`,true,tableName);s.getRange(`A5:${end}5`).format=headerFormat;
 widths.forEach((w,i)=>s.getRange(`${col(i)}1:${col(i)}${last}`).format.columnWidth=w);
 body(s,`A6:${end}${last}`,rows,widths,6);return s;
}
const si=edit('物品总表','物品总表 · V6',`${counts.items}件物品，${counts.permanent}件永久、${counts.temporary}件临时，${counts.draftPool}件进入三选一。蛋按3次存活结算孵化，补充供水、谷物与资源出口。`,items.map(x=>[x.id,x.name,x.quality,x.base,x.acquisition,x.inDraftPool,x.lifetime,x.timing,x.effect,x.limit,x.family,x.tags,x.shape,x.standardShape,x.sourceRef,x.pilot]),[8,17,9,9,53,16,10,16,62,35,10,28,16,13,42,14],'Items',old.items.length);
si.getRange(`D6:D${items.length+5}`).setNumberFormat('0');
si.getRange(`F6:F${items.length+5}`).dataValidation={rule:{type:'list',values:['是','否']}};si.getRange(`G6:G${items.length+5}`).dataValidation={rule:{type:'list',values:['永久','临时']}};
edit('遗物','遗物设计 · V6','61件遗物。孵化不触发生成或成长；冷凝管每回合最多回收2水；其余次数边界保持有限。',relics.map(x=>[x.id,x.name,x.quality,x.timing,x.effect,x.limit,x.family,x.sourceRef]),[8,19,9,18,68,40,11,46],'Relics',old.relics.length);
edit('流派组合','12套组合路线 · V6','区分持续供给、持有增值与有限爆发。路线按来源、出口和同场需求修订；具体收支与抽样估算见循环检查。',builds,[12,28,34,34,25,39,63,47,49,37,62,48],'Builds',old.builds.length);
const sr=edit('规则','规则口径与来源 · V6','三次自身存活结算孵化已确认。供水与其他数值为首测方案，牌库不足16件等边界仍保留待定。',rules,[14,24,120],'Rules',old.rules.length);
rules.forEach((r,i)=>{if(r[0]==='待定')sr.getRange(`A${i+6}:C${i+6}`).format.fill='#FFF2CC';sr.getRange(`A${i+6}`).format.font={color:r[0]==='已确认'?'#3B6B54':'#20334D',bold:r[0]==='已确认'};});
edit('原机制适配','原机制适配 · V6','保留来源引用，更新自身存活计次、有限用电供水与重复接触攻击。',mappings,[22,29,75,51],'Mappings',old.mappings.length);
const se=edit('结算算例','结算算例 · V6','新增第三次蛋结算和低分羊毛出售算例。孵化后分数不追溯，所有示例均为条件成立下的局部计分。',examples.map(x=>[x[0],x[1],x[2],x[3],x[4],null,x[5]]),[31,13,15,15,15,14,58],'ScoreExamples',old.examples.length);
for(let i=0;i<examples.length;i++){const r=i+6;se.getRange(`F${r}`).formulas=[[`=ROUNDDOWN((B${r}+C${r})*(1+D${r}),0)+E${r}`]];}se.getRange(`D6:D${examples.length+5}`).setNumberFormat('0%');
const sa=edit('审查调整','逐项审查 · V4 → V6','保留V4→V5历史231项，追加V5全目录186项及2个新增物品的本轮检查；按版本列筛选。历史效果不代表当前目录。',audit,[9,9,19,10,20,27,64,67,67,15],'ReviewLog',old.audit.length,{oldCols:9,headers:['类别','原ID','原名称','决策','该版本名称／状态','职责合并至','判断依据','修改前效果','该版本效果','版本']});
sa.getRange(`D6:D${audit.length+5}`).conditionalFormats.clear();
for(const [text,fill,color]of [['调整','#DDEBFA','#194F87'],['合并','#FFF2CC','#7D5700'],['移除','#F8DEDE','#9B3636'],['新增','#E1EFE5','#2A663D']])sa.getRange(`D6:D${audit.length+5}`).conditionalFormats.add('containsText',{text,format:{fill,font:{color}}});
const widths=[36,37,13,13,13,13,13,13,14,14,14,66];
const balanceRows=balances.map(x=>[x[0],x[1],...x.slice(2,8),null,null,null,x[8]]);
const sc=edit('循环检查','资源循环与抽样检查 · V6','先检查单次资源收支，再看抽样等待与21条链路。以下是假定组件同场、接触成功、空间足够的条件推演，不是物理实测。',balanceRows,widths,'ResourceBalances',0,{newSheet:true,headers:['条件算例','运行前提','永久新增','永久消耗','临时生成','临时消耗','水珠生成','水珠消耗','永久净变化','临时净新增','水珠净变化','解释与取舍']});
sc.getRange(`C6:K${balances.length+5}`).setNumberFormat('0');
for(let i=0;i<balances.length;i++){const r=i+6;sc.getRange(`I${r}:K${r}`).formulas=[[`=C${r}-D${r}`,`=E${r}-F${r}`,`=G${r}-H${r}`]];}
sc.getRange('A19:L19').merge();sc.getRange('A19').values=[['“永久新增”包括该行列明的生成或奖励入库，不把奖励选择当成生成事件。临时净新增不包含结算后自然清理。']];sc.getRange('A19:L19').format={font:bodyFont,rowHeight:30,wrapText:true};
sc.getRange('A21:L21').merge();sc.getRange('A21').values=[['抽样与孵化等待：每种关键卡各只有1件，牌库规模固定']];sc.getRange('A21:L21').format={font:{...bodyFont,bold:true,size:12},rowHeight:32};
sc.getRange('A23:G23').values=[['固定牌库件数N','每回合抽取件数','单卡入场率','指定2卡同场率','指定3卡同场率','平均孵化发生回合','雏鸡首次计分平均回合']];sc.getRange('A23:G23').format={...headerFormat,rowHeight:68};
sc.getRange('A24:B27').values=[[16,16],[24,16],[32,16],[48,16]];
for(let r=24;r<=27;r++)sc.getRange(`C${r}:G${r}`).formulas=[[`=B${r}/A${r}`,`=B${r}*(B${r}-1)/(A${r}*(A${r}-1))`,`=B${r}*(B${r}-1)*(B${r}-2)/(A${r}*(A${r}-1)*(A${r}-2))`,`=1+2*A${r}/B${r}`,`=1+3*A${r}/B${r}`]];
sc.getRange('A24:G27').format={font:bodyFont,rowHeight:36,horizontalAlignment:'right',verticalAlignment:'center'};sc.getRange('C24:E27').setNumberFormat('0.0%');sc.getRange('F24:G27').setNumberFormat('0.0');
sc.getRange('H23:L27').merge();sc.getRange('H23').values=[['N≥16。假设每回合从固定N件中随机不放回抽16件，跨回合重新抽取。新蛋生成当回合存活已记第1次，标为回合1；之后等两次入场完成孵化，再等一次入场才能按雏鸡计分。假设始终存活、不被消耗。产物与奖励通常让N增长，因此实际等待可能更长；这些公式不是每局完成时间的保证。']];sc.getRange('H23:L27').format={font:bodyFont,wrapText:true,verticalAlignment:'center',fill:'#FFF2CC'};
sc.getRange('A24:A27').dataValidation={rule:{type:'whole',operator:'greaterThanOrEqual',formula1:16}};
sc.getRange('A30:L30').merge();sc.getRange('A30').values=[['全目录循环判断：21条资源链与持有路线，覆盖12个主流派']];sc.getRange('A30:L30').format={font:{...bodyFont,bold:true,size:12},rowHeight:32};
const groups=[['A','A',36],['B','B',37],['C','F',52],['G','I',40],['J','L',94]];
const heads=['链路','循环定位','组件、消耗与产出','触发上限与永久数量变化','可行性判断及本轮调整'];
for(let j=0;j<groups.length;j++){const[a,z]=groups[j];if(a!==z)sc.getRange(`${a}32:${z}32`).merge();sc.getRange(`${a}32`).values=[[heads[j]]];}sc.getRange('A32:L32').format=headerFormat;
loops.forEach((x,i)=>{const r=i+33,values=[`${x[0]} ${x[1]}`,x[2],`组件：${x[3]}。消耗：${x[4]}。产出：${x[5]}。`,`上限：${x[6]}。永久变化：${x[7]}。`,`${x[8]} 本轮：${x[9]}。`];let lines=1;groups.forEach(([a,z,w],j)=>{if(a!==z)sc.getRange(`${a}${r}:${z}${r}`).merge();sc.getRange(`${a}${r}`).values=[[values[j]]];lines=Math.max(lines,Math.ceil([...values[j]].reduce((n,c)=>n+(c.charCodeAt(0)>255?1.7:.85),0)/(w-2)));});sc.getRange(`A${r}:L${r}`).format={font:bodyFont,verticalAlignment:'center',wrapText:true,rowHeight:Math.max(60,lines*14+12),fill:i%2===0?'#F3F6FA':'#FFFFFF'};});
// 改动抽样输入，确认等待与同场公式会响应，然后恢复交付值。
sc.getRange('A25').values=[[40]];wb.recalculate();
const probe=await wb.inspect({kind:'region',sheetId:'循环检查',range:'C25:G25',maxChars:1000,tableMaxRows:1,tableMaxCols:5});
const probeRow=probe.ndjson.split('\n').map(x=>{try{return JSON.parse(x);}catch{return null;}}).find(x=>x?.preview)?.preview[0].map(Number);
assert(probeRow&&Math.abs(probeRow[0]-.4)<1e-9&&probeRow[3]===6&&probeRow[4]===8.5,'抽样公式输入响应');
sc.getRange('A25').values=[[24]];wb.recalculate();
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!|#NULL!',options:{useRegex:true,maxResults:20},maxChars:600})).ndjson);
console.log((await wb.inspect({kind:'region',sheetId:'循环检查',range:'A24:G27',maxChars:1000,tableMaxRows:4,tableMaxCols:7})).ndjson);
await fs.mkdir(path.join(out,'previews-v6'),{recursive:true});
const itemRow=id=>items.findIndex(x=>x.id===id)+6,relRow=id=>relics.findIndex(x=>x.id===id)+6;
const renders=[['物品总表','A2:P9','overview'],['物品总表',`H${itemRow('I122')}:L${itemRow('I123')}`,'new-sources'],['物品总表',`H${itemRow('P008')}:L${itemRow('P011')}`,'hatching'],['遗物',`A${relRow('R011')}:F${relRow('R014')}`,'farm-relics'],['流派组合','G6:L10','builds'],['规则',`A${rules.length}:C${rules.length+5}`,'rules'],['原机制适配','A10:D17','mapping'],['结算算例','A12:G15','examples'],['审查调整','A237:G242','audit'],['循环检查','A5:L9','balances'],['循环检查','A21:L27','sampling'],['循环检查','A32:L37','loop-review']];
for(const [sheetName,range,file]of renders){const b=await wb.render({sheetName,range,scale:1,format:'png'});await fs.writeFile(path.join(out,'previews-v6',file+'.png'),new Uint8Array(await b.arrayBuffer()));}
await(await SpreadsheetFile.exportXlsx(wb)).save(path.join(out,'ShakeHero_物品与遗物设计_V6.xlsx'));
await fs.writeFile(path.join(out,'design-data-v6.json'),JSON.stringify(data,null,2));
const report={...counts,reviewedV5:186,newItems:2,removedIds:['I027'],changedIds,auditRows:audit.length,loopChecks:loops.length,balanceCases:balances.length,acquisitionEdges:edges,formulaResults:results,checks:{sources:true,builds:true,balanceEvents:true,hatchingBoundaries:true,pumpCaps:true,samplingInputResponse:true},playtested:false};
await fs.writeFile(path.join(out,'validation-v6.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({counts,auditRows:audit.length,loopChecks:loops.length,balanceCases:balances.length,checks:report.checks}));
