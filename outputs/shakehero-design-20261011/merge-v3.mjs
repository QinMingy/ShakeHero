import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const out=path.dirname(fileURLToPath(import.meta.url));
const data=JSON.parse(await fs.readFile(path.join(out,'design-data-v2.json'),'utf8'));
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(path.join(out,'ShakeHero_物品与遗物设计_V2.xlsx')));
const s=wb.worksheets.getItem('物品');
const pilot=new Set(data.builds.flatMap(x=>x[11].replace('先测','').split('、')));
const productTiming={P002:'被消耗',P004:'结算加分',P012:'接触',P014:'生成时',P019:'常驻属性',P021:'生成时',P022:'被消耗',P026:'结算加分',P029:'常驻属性'};
const productLimit={P002:'同一实例每回合1次',P004:'每回合1次',P012:'每目标1次；每回合最多3件',P021:'生成基础分上限12',P022:'同一实例每回合1次',P026:'每回合1次'};
const items=data.items.map(x=>({...x,acquisition:x.id==='I097'?'三选一；生成：遗物备用钥匙圈':'三选一',inDraftPool:'是',lifetime:'永久',pilot:pilot.has(x.name)?'首测候选':'扩展'}));
for(const x of data.products){
 let acquisition;
 if(['P004','P012','P026'].includes(x.id))acquisition='变形：'+x.origin;
 else if(x.id==='P029')acquisition='生成替换：遗物双黄蛋谱将普通蛋改为双黄蛋';
 else acquisition=(x.lifetime==='临时'?'临时生成：':'生成：')+x.origin;
 if(x.tags.split('、').includes('商品'))acquisition+='；黄玉可追加生成';
 items.push({...x,acquisition,inDraftPool:'否',timing:productTiming[x.id]??'—',limit:productLimit[x.id]??'—',pilot:'随来源测试'});
}
if(items.length!==152||new Set(items.map(x=>x.id)).size!==152)throw Error('物品数量或ID不符');
if(items.filter(x=>x.inDraftPool==='是').length!==120||items.filter(x=>x.lifetime==='临时').length!==7)throw Error('奖励池或存续不符');
const headers=['ID','名称','品质','基础分','获取方式','是否进入三选一','存续','触发时机','效果','次数与边界','主流派','标签','外观形状','标准形状','原表参考','测试批次'];
const widths=[8,17,9,9,53,16,10,16,62,35,10,28,16,13,42,14];
const rows=items.map(x=>[x.id,x.name,x.quality,x.base,x.acquisition,x.inDraftPool,x.lifetime,x.timing,x.effect,x.limit,x.family,x.tags,x.shape,x.standardShape,x.sourceRef,x.pilot]);
const col=n=>{let a='';for(n++;n;n=Math.floor((n-1)/26))a=String.fromCharCode(65+(n-1)%26)+a;return a;};
// The user authorized merging these two tables. Keep all original object IDs and fields.
for(const t of [...s.tables.items])t.delete();
s.getRange('A5:P157').conditionalFormats.clear();
s.getRange('A5:P157').clear({applyTo:'all'});
s.getRange('A2').values=[['物品总表 · V3']];
s.getRange('A3').values=[['152件物品，145件永久、7件临时。三选一池120件；生成和变形专属32件。原ID保留。']];
s.getRange('A4:P4').format.borders={bottom:{style:'thin',color:'#D7DFE8'}};
s.getRange('A5:P157').format={font:{name:'Microsoft YaHei',size:10,color:'#20334D'},verticalAlignment:'center',wrapText:true};
s.getRange('A5:P5').values=[headers];
s.getRange('A6:P157').values=rows;
s.tables.add('A5:P157',true,'Items');
s.getRange('A5:P5').format={fill:'#344D6D',font:{name:'Microsoft YaHei',size:10,bold:true,color:'#FFFFFF'},rowHeight:32,horizontalAlignment:'center',verticalAlignment:'center',wrapText:true};
widths.forEach((w,i)=>s.getRange(`${col(i)}1:${col(i)}157`).format.columnWidth=w);
rows.forEach((r,i)=>{
 const lines=Math.max(...r.map((v,j)=>Math.ceil([...String(v??'')].reduce((n,c)=>n+(c.charCodeAt(0)>255?1.7:0.85),0)/(widths[j]-2))));
 const row=i+6;
 s.getRange(`A${row}:P${row}`).format.rowHeight=Math.max(30,lines*14+10);
 s.getRange(`A${row}:P${row}`).format.fill=row%2===0?'#F3F6FA':'#FFFFFF';
});
s.getRange('D6:D157').setNumberFormat('0');
s.getRange('F6:G157').format.horizontalAlignment='center';
for(const [text,fill,color]of [['优秀','#E1EFE5','#2A663D'],['稀有','#DDEBFA','#194F87'],['史诗','#EADFF4','#68408D']])s.getRange('C6:C157').conditionalFormats.add('containsText',{text,format:{fill,font:{color}}});
s.getRange('G6:G157').conditionalFormats.add('containsText',{text:'临时',format:{fill:'#FFF2CC',font:{color:'#7D5700'}}});
s.getRange('F6:F157').dataValidation={rule:{type:'list',values:['是','否']}};
s.getRange('G6:G157').dataValidation={rule:{type:'list',values:['永久','临时']}};
s.freezePanes.freezeRows(5);s.freezePanes.freezeColumns(2);
const rules=structuredClone(data.rules);
rules[15]=['设计约定','物品总表与奖励池','全部152件统一列在物品总表，145件永久、7件临时。获取方式可有多个来源；是否进入三选一独立控制奖励池。120件进入三选一，22件永久生成、3件永久进阶及7件临时物品仅由对应来源获得。永久生成物品可在以后回合抽取，不因此进入三选一；钥匙同时支持三选一和遗物生成。'];
rules[18][2]=rules[18][2].replace('按产物表或','按物品总表或');
rules[31]=['来源','借鉴边界与版本','沿用用户飞书参考表及原单元格引用。V3在V2效果基础上合并物品与产物，增加获取方式、是否进入三选一、存续字段。I/P前缀仅保留原ID，不决定获取资格。参考列表示设计灵感而非原版翻译；未核验原作最新版本。'];
const rs=wb.worksheets.getItem('规则');
rs.getRange('A2').values=[['规则口径与来源 · V3']];
for(const index of [15,18,31]){
 const row=index+6;
 rs.getRange(`A${row}:C${row}`).values=[rules[index]];
 const n=Math.max(...rules[index].map((v,j)=>Math.ceil([...v].reduce((a,c)=>a+(c.charCodeAt(0)>255?1.7:0.85),0)/([14,24,120][j]-2))));
 rs.getRange(`A${row}:C${row}`).format.rowHeight=Math.max(30,n*14+10);
}
wb.recalculate();
console.log((await wb.inspect({kind:'region',sheetId:'物品',range:'A123:H130',maxChars:2000,tableMaxRows:8,tableMaxCols:8})).ndjson);
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!|#NULL!',options:{useRegex:true,maxResults:20},maxChars:700})).ndjson);
await fs.mkdir(path.join(out,'previews-v3'),{recursive:true});
for(const [sheetName,range,file]of [
 ['物品','A2:H10','opening'],['物品','A123:H132','merge-boundary'],['物品','A138:H147','temporary'],
 ['物品','I125:P132','effects'],['物品','A100:H104','key'],['规则','A20:C24','rules']
]){
 const blob=await wb.render({sheetName,range,scale:1,format:'png'});
 await fs.writeFile(path.join(out,'previews-v3',`${file}.png`),new Uint8Array(await blob.arrayBuffer()));
}
await (await SpreadsheetFile.exportXlsx(wb)).save(path.join(out,'.merge-v3-authored.xlsx'));
await fs.writeFile(path.join(out,'design-data-v3.json'),JSON.stringify({items,relics:data.relics,builds:data.builds,rules,mappings:data.mappings,examples:data.examples},null,2),'utf8');
console.log(JSON.stringify({items:items.length,permanent:items.filter(x=>x.lifetime==='永久').length,temporary:7,inDraftPool:120,generatedOrTransformedOnly:32}));
