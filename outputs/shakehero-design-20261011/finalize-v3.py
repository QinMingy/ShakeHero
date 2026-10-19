"""Use ZIP/XML only for sheet rename/removal, absent from the exposed artifact API.
Cell content, formats, tables, validation and formulas are authored by artifact-tool.
"""
from pathlib import Path, PurePosixPath
from zipfile import ZipFile, ZIP_DEFLATED
import posixpath
import xml.etree.ElementTree as ET

root=Path(__file__).resolve().parent
ns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
    'r':'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
    'p':'http://schemas.openxmlformats.org/package/2006/relationships',
    'c':'http://schemas.openxmlformats.org/package/2006/content-types'}
ET.register_namespace('',ns['s']); ET.register_namespace('r',ns['r'])
with ZipFile(root/'.merge-v3-authored.xlsx') as z:
    parts={n:z.read(n) for n in z.namelist()}
w=ET.fromstring(parts['xl/workbook.xml'])
rels=ET.fromstring(parts['xl/_rels/workbook.xml.rels'])
sheets=w.find('s:sheets',ns)
gone=next(s for s in sheets if s.attrib['name']=='产物与进阶')
gone_index=list(sheets).index(gone)
rid=gone.attrib['{'+ns['r']+'}id']
relationship=next(r for r in rels if r.attrib['Id']==rid)
def resolve(base,target):
    return posixpath.normpath(target.lstrip('/') if target.startswith('/') else posixpath.join(posixpath.dirname(base),target))
target=resolve('xl/workbook.xml',relationship.attrib['Target'])
removed={target}
sheet_rels=str(PurePosixPath(target).parent/'_rels'/(PurePosixPath(target).name+'.rels'))
if sheet_rels in parts:
    removed.add(sheet_rels)
    for r in ET.fromstring(parts[sheet_rels]):
        if r.attrib.get('TargetMode')=='External':continue
        # This catalog sheet has one native Table and no drawings or shared assets.
        assert r.attrib['Type'].endswith('/table'),r.attrib
        removed.add(resolve(target,r.attrib['Target']))
sheets.remove(gone); rels.remove(relationship)
next(s for s in sheets if s.attrib['name']=='物品').set('name','物品总表')
defined=w.find('s:definedNames',ns)
if defined is not None:
    for name in list(defined):
        idx=name.attrib.get('localSheetId')
        if idx is not None:
            if int(idx)==gone_index:defined.remove(name); continue
            if int(idx)>gone_index:name.set('localSheetId',str(int(idx)-1))
        if name.text:name.text=name.text.replace("'物品'!","'物品总表'!")
types=ET.fromstring(parts['[Content_Types].xml'])
for entry in list(types):
    if entry.attrib.get('PartName','').lstrip('/') in removed:types.remove(entry)
parts['xl/workbook.xml']=ET.tostring(w,encoding='utf-8',xml_declaration=True)
ET.register_namespace('',ns['p'])
parts['xl/_rels/workbook.xml.rels']=ET.tostring(rels,encoding='utf-8',xml_declaration=True)
ET.register_namespace('',ns['c'])
parts['[Content_Types].xml']=ET.tostring(types,encoding='utf-8',xml_declaration=True)
# Keep package extended metadata aligned with the visible worksheets when present.
app='docProps/app.xml'
if app in parts:
    a=ET.fromstring(parts[app])
    ans={'e':'http://schemas.openxmlformats.org/officeDocument/2006/extended-properties',
         'v':'http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes'}
    titles=a.find('e:TitlesOfParts/v:vector',ans)
    if titles is not None:
        for t in list(titles):
            if t.text=='产物与进阶':titles.remove(t)
            elif t.text=='物品':t.text='物品总表'
        titles.set('size',str(len(titles)))
    heading=a.find('e:HeadingPairs/v:vector',ans)
    if heading is not None:
        variants=list(heading)
        for i,v in enumerate(variants[:-1]):
            label=v.find('v:lpstr',ans)
            if label is not None and label.text in ('Worksheets','工作表'):
                value=variants[i+1].find('v:i4',ans)
                if value is not None:value.text=str(len(sheets))
    parts[app]=ET.tostring(a,encoding='utf-8',xml_declaration=True)
output=root/'ShakeHero_物品与遗物设计_V3.xlsx'
with ZipFile(output,'w',ZIP_DEFLATED) as z:
    for name,body in parts.items():
        if name not in removed:z.writestr(name,body)
print(output)
