$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$studyDir = $PSScriptRoot
$sourceCode = @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
public static class CornerStudy {
 static string dir;
 static Color[] palette={Color.FromArgb(21,29,24),Color.FromArgb(43,58,49),Color.FromArgb(70,85,72),Color.FromArgb(104,117,96),Color.FromArgb(160,170,136)};
 static Color[] amber={Color.FromArgb(21,29,24),Color.FromArgb(156,116,57),Color.FromArgb(223,184,92),Color.FromArgb(244,223,160)};
 static Dictionary<string,Bitmap> sprites=new Dictionary<string,Bitmap>();
 static string[] names={"plate","frame","ornament","screw","lamp-off","lamp-on","button","glass"};
 public static List<string> report=new List<string>();
 static Bitmap Blank(int w,int h){return new Bitmap(w,h,PixelFormat.Format32bppArgb);}
 static Graphics G(Bitmap b){var g=Graphics.FromImage(b);g.InterpolationMode=InterpolationMode.NearestNeighbor;g.PixelOffsetMode=PixelOffsetMode.Half;g.SmoothingMode=SmoothingMode.None;return g;}
 static void Save(Bitmap b,string file){b.Save(Path.Combine(dir,file),ImageFormat.Png);}
 static void Blit(Bitmap dst,Bitmap src,int x,int y){using(var g=G(dst))g.DrawImageUnscaled(src,x,y);}
 static Bitmap Scale(Bitmap src,int w,int h){var b=Blank(w,h);using(var g=G(b))g.DrawImage(src,new Rectangle(0,0,w,h),new Rectangle(0,0,src.Width,src.Height),GraphicsUnit.Pixel);return b;}
 static void Rect(Bitmap dst,int x,int y,int w,int h,Color c){using(var g=G(dst))using(var br=new SolidBrush(c))g.FillRectangle(br,x,y,w,h);}
 static Color Nearest(Color c,Color[] pal){int best=int.MaxValue;Color result=pal[0];foreach(var p in pal){int dr=c.R-p.R,dg=c.G-p.G,db=c.B-p.B;int d=dr*dr+dg*dg+db*db;if(d<best){best=d;result=p;}}return result;}
 static Bitmap Extract(Bitmap sheet,int index){
  int cw=sheet.Width/4,ch=sheet.Height/2;using(var cell=sheet.Clone(new Rectangle(index%4*cw,index/4*ch,cw,ch),PixelFormat.Format32bppArgb))using(var small=Scale(cell,32,32)){
   int left=32,top=32,right=-1,bottom=-1;
   for(int y=0;y<32;y++)for(int x=0;x<32;x++){Color c=small.GetPixel(x,y);if(c.A>=128){small.SetPixel(x,y,Nearest(c,index==5?amber:palette));left=Math.Min(left,x);top=Math.Min(top,y);right=Math.Max(right,x);bottom=Math.Max(bottom,y);}else small.SetPixel(x,y,Color.Transparent);}
   if(right<left)throw new Exception("Empty sprite "+index);
   var output=small.Clone(new Rectangle(left,top,right-left+1,bottom-top+1),PixelFormat.Format32bppArgb);
   if(index==3){var compact=Scale(output,4,4);output.Dispose();output=compact;}
   if(index==7){for(int y=0;y<output.Height;y++)for(int x=0;x<output.Width;x++){var c=output.GetPixel(x,y);if(c.A>0)output.SetPixel(x,y,Color.FromArgb(40,c.R,c.G,c.B));}}
   var unique=new HashSet<int>();for(int y=0;y<output.Height;y++)for(int x=0;x<output.Width;x++)if(output.GetPixel(x,y).A>0)unique.Add(output.GetPixel(x,y).ToArgb());
   report.Add(names[index]+" "+output.Width+"x"+output.Height+" opaque/tinted colors="+unique.Count);return output;
  }
 }
 static Bitmap Nine(Bitmap s,int w,int h,int edge){
  var d=Blank(w,h);int e=Math.Min(edge,Math.Min(s.Width,s.Height)/2-1);int[] sx={0,e,s.Width-e,s.Width},sy={0,e,s.Height-e,s.Height};int[] dx={0,e,w-e,w},dy={0,e,h-e,h};
  using(var g=G(d))for(int j=0;j<3;j++)for(int i=0;i<3;i++)g.DrawImage(s,new Rectangle(dx[i],dy[j],dx[i+1]-dx[i],dy[j+1]-dy[j]),new Rectangle(sx[i],sy[j],sx[i+1]-sx[i],sy[j+1]-sy[j]),GraphicsUnit.Pixel);return d;
 }
 static Bitmap Shadow(Bitmap s,int dx,int dy){var b=Blank(s.Width,s.Height);for(int y=0;y<s.Height;y++)for(int x=0;x<s.Width;x++)if(s.GetPixel(x,y).A>127&&x+dx>=0&&x+dx<b.Width&&y+dy>=0&&y+dy<b.Height)b.SetPixel(x+dx,y+dy,Color.FromArgb(150,5,11,8));return b;}
 static Bitmap Lighting(Bitmap s){var b=(Bitmap)s.Clone();for(int y=0;y<b.Height;y++)for(int x=0;x<b.Width;x++){var c=b.GetPixel(x,y);if(c.A==0)continue;double lx=(x-34)/85.0,ly=(y-10)/95.0;double light=Math.Exp(-(lx*lx+ly*ly)*1.3);double f=.67+.37*light;b.SetPixel(x,y,Color.FromArgb(c.A,Math.Min(255,(int)(c.R*f+11*light)),Math.Min(255,(int)(c.G*f+5*light)),Math.Min(255,(int)(c.B*f))));}return b;}
 static void Stamp(Bitmap b,Bitmap motif,int x,int y,bool mirror){using(var s=(Bitmap)motif.Clone()){if(mirror)s.RotateFlip(RotateFlipType.RotateNoneFlipX);Blit(b,s,x,y);}}
 static void Text(Graphics g,string text,int x,int y,int size,bool bold,Color c){using(var f=new Font("Microsoft YaHei UI",size,bold?FontStyle.Bold:FontStyle.Regular,GraphicsUnit.Pixel))using(var b=new SolidBrush(c))g.DrawString(text,f,b,x,y);}
 public static void Build(string path,string screenshot){
  dir=path;using(var sheet=new Bitmap(Path.Combine(dir,"generated/sprite-kit-flat.png")))for(int i=0;i<8;i++){var s=Extract(sheet,i);sprites[names[i]]=s;Save(s,"sprites/"+names[i]+".png");}
  using(var source=new Bitmap(screenshot))using(var crop=source.Clone(new Rectangle(26,31,406,811),PixelFormat.Format32bppArgb))using(var scaled=Scale(crop,402,803)){
   var baseline=Blank(402,874);Rect(baseline,0,0,402,874,Color.FromArgb(10,15,13));Blit(baseline,scaled,0,35);Save(baseline,"baseline-phone-402x874.png");
   var foundation=Blank(104,84);using(var plate=Nine(sprites["plate"],104,84,3))Blit(foundation,plate,0,0);
   // Only replace hardware: preserve screen content from the same baseline.
   for(int y=21;y<84;y++)for(int x=18;x<104;x++)foundation.SetPixel(x,y,Color.Transparent);
   var recess=Blank(104,84);Rect(recess,12,17,92,4,palette[0]);Rect(recess,12,20,6,64,palette[0]);
   var frame=Blank(104,84);using(var full=Nine(sprites["frame"],175,180,4))Blit(frame,full,12,16);
   var button=Blank(104,84);using(var face=Nine(sprites["button"],48,12,3))Blit(button,face,19,21);
   var screws=Blank(104,84);Blit(screws,sprites["screw"],3,17);Blit(screws,sprites["screw"],3,77);
   var sockets=Blank(104,84);var cores=Blank(104,84);
   using(var core=(Bitmap)sprites["lamp-on"].Clone()){
    for(int y=0;y<core.Height;y++)for(int x=0;x<core.Width;x++)if(core.GetPixel(x,y).R<100)core.SetPixel(x,y,Color.Transparent);
    for(int i=0;i<12;i++){int cx=21+i*7;Blit(sockets,sprites["lamp-off"],cx,3);if(i<6)Blit(cores,core,cx,3);}
   }
   var layers=new Dictionary<string,Bitmap>{{"01-base-plate",foundation},{"02-recess",recess},{"03-frame",frame},{"05-screws",screws},{"06-lamp-sockets",sockets},{"07-lamp-cores",cores},{"08-button",button}};
   foreach(var item in layers)Save(item.Value,"layers/"+item.Key+"-104x84.png");
   var phones=new List<Bitmap>();var flats=new List<Bitmap>();var lights=new List<Bitmap>();
   var motif=sprites["ornament"].Clone(new Rectangle(0,0,6,6),PixelFormat.Format32bppArgb);
   int[,] positions={{3,29},{3,63},{3,46},{3,8},{32,12},{63,12},{86,12},{60,25},{22,25},{3,38},{3,55},{3,70},{45,12},{75,12},{94,12},{34,25},{47,25},{3,22}};
   string[] variants={"A-low","B-medium","C-high"};int[] counts={2,9,18};
   for(int v=0;v<3;v++){
    var decor=Blank(104,84);for(int k=0;k<counts[v];k++)Stamp(decor,motif,positions[k,0],positions[k,1],k%2==1);
    // Stamp only on board surfaces and button; keep outlines, lamps and text invariant.
    for(int y=0;y<84;y++)for(int x=0;x<104;x++)if(!((x<10&&y>7)||(y>=12&&y<16)||(x>=21&&x<65&&y>=24&&y<30)))decor.SetPixel(x,y,Color.Transparent);
    Save(decor,"layers/04-decoration-"+variants[v]+"-104x84.png");
    int board=0,detail=0;for(int y=0;y<84;y++)for(int x=0;x<104;x++)if(foundation.GetPixel(x,y).A>0||button.GetPixel(x,y).A>0){board++;if(decor.GetPixel(x,y).A>0)detail++;}
    report.Add(variants[v]+" decoration="+detail+"/"+board+" quiet="+(100.0*(board-detail)/board).ToString("F2")+"%");
    var flat=Blank(104,84);Blit(flat,foundation,0,0);Blit(flat,recess,0,0);Blit(flat,frame,0,0);Blit(flat,button,0,0);Blit(flat,decor,0,0);Blit(flat,screws,0,0);Blit(flat,sockets,0,0);Blit(flat,cores,0,0);Save(flat,variants[v]+"-hardware-flat-104x84.png");
    var lit=Blank(104,84);using(var b=Lighting(foundation))Blit(lit,b,0,0);Blit(lit,recess,0,0);
    using(var s=Shadow(frame,1,1))Blit(lit,s,0,0);using(var f=Lighting(frame))Blit(lit,f,0,0);
    using(var s=Shadow(button,1,1))Blit(lit,s,0,0);using(var b=Lighting(button))Blit(lit,b,0,0);using(var d=Lighting(decor))Blit(lit,d,0,0);
    using(var s=Shadow(screws,1,1))Blit(lit,s,0,0);using(var s=Lighting(screws))Blit(lit,s,0,0);using(var s=Lighting(sockets))Blit(lit,s,0,0);Blit(lit,cores,0,0);Save(lit,variants[v]+"-hardware-lit-104x84.png");
    var patchBase=baseline.Clone(new Rectangle(20,226,208,168),PixelFormat.Format32bppArgb);
    var patchFlat=(Bitmap)patchBase.Clone();var patchLit=(Bitmap)patchBase.Clone();using(var up=Scale(flat,208,168))Blit(patchFlat,up,0,0);using(var up=Scale(lit,208,168))Blit(patchLit,up,0,0);
    // Exact shared screenshot label, no generated or re-typeset Chinese.
    var label=baseline.Clone(new Rectangle(73,271,41,12),PixelFormat.Format32bppArgb);Blit(patchFlat,label,53,45);Blit(patchLit,label,53,45);label.Dispose();
    var phoneFlat=(Bitmap)baseline.Clone();var phoneLit=(Bitmap)baseline.Clone();Blit(phoneFlat,patchFlat,20,226);Blit(phoneLit,patchLit,20,226);
    Save(phoneFlat,variants[v]+"-flat-phone-402x874.png");Save(phoneLit,variants[v]+"-lit-phone-402x874.png");Save(patchFlat,variants[v]+"-flat-corner-208x168.png");Save(patchLit,variants[v]+"-lit-corner-208x168.png");
    using(var large=Scale(patchLit,832,672))Save(large,variants[v]+"-lit-corner-4x.png");
    flats.Add(patchFlat);lights.Add(patchLit);phones.Add(phoneLit);flat.Dispose();lit.Dispose();phoneFlat.Dispose();patchBase.Dispose();decor.Dispose();
   }
   var comparison=Blank(1294,1370);Rect(comparison,0,0,1294,1370,Color.FromArgb(16,23,20));using(var g=G(comparison)){
    Text(g,"02 / 像素分件 · 薄层叠压",22,16,25,true,Color.FromArgb(222,229,208));Text(g,"同一结构与光照，只改变装饰实例数量。局部静态拼接，非运行截图。",22,52,15,false,Color.FromArgb(144,163,145));
    string[] title={"A  低密度","B  中密度","C  高密度"};
    for(int i=0;i<3;i++){int x=20+i*426;Text(g,title[i],x,87,21,true,Color.FromArgb(222,229,208));g.DrawImageUnscaled(phones[i],x,125);using(var pen=new Pen(Color.FromArgb(160,180,120))){pen.DashStyle=DashStyle.Dash;g.DrawRectangle(pen,x+20,351,208,168);}Text(g,"同一区域 / 约2倍查看",x,1012,14,false,Color.FromArgb(144,163,145));using(var big=Scale(lights[i],402,325))g.DrawImageUnscaled(big,x,1040);}
   }Save(comparison,"comparison.png");comparison.Dispose();
   var lighting=Blank(1050,820);Rect(lighting,0,0,1050,820,Color.FromArgb(16,23,20));using(var g=G(lighting)){
    Text(g,"B / 平光结构与加光对照",22,16,25,true,Color.FromArgb(222,229,208));Text(g,"左：新增结构不加氛围光    右：独立投影与局部暖光    原截图内的CRT光效保持不变",22,52,14,false,Color.FromArgb(144,163,145));
    using(var l=Scale(flats[1],499,403))g.DrawImageUnscaled(l,20,100);using(var r=Scale(lights[1],499,403))g.DrawImageUnscaled(r,531,100);
    Text(g,"8个母版资产 / 最近邻放大 / 灰绿5色，灯芯独立色板",22,535,18,true,Color.FromArgb(222,229,208));
    for(int i=0;i<8;i++){int x=24+i*128;using(var s=Scale(sprites[names[i]],sprites[names[i]].Width*4,sprites[names[i]].Height*4))g.DrawImageUnscaled(s,x,585);Text(g,names[i],x,699,13,false,Color.FromArgb(192,204,183));Text(g,sprites[names[i]].Width+"x"+sprites[names[i]].Height,x,721,12,false,Color.FromArgb(144,163,145));}
    Text(g,"原始生图经过网格与色板规范化。玻璃母版暂不覆盖玩法内容。",22,772,14,false,Color.FromArgb(144,163,145));
   }Save(lighting,"lighting-and-sprites.png");lighting.Dispose();
   var explode=Blank(1050,780);Rect(explode,0,0,1050,780,Color.FromArgb(16,23,20));using(var g=G(explode)){
    Text(g,"B / 独立层拆解",22,16,25,true,Color.FromArgb(222,229,208));Text(g,"每层104x84源像素，可独立替换。下列图片是分件展示，不是三维渲染。",22,52,14,false,Color.FromArgb(144,163,145));
    int n=0;foreach(var item in layers){int x=20+(n%4)*258,y=112+(n/4)*300;using(var big=Scale(item.Value,208,168))g.DrawImageUnscaled(big,x,y);Text(g,item.Key,x,y+182,14,false,Color.FromArgb(192,204,183));n++;}
    using(var d=new Bitmap(Path.Combine(dir,"layers/04-decoration-B-medium-104x84.png")))using(var big=Scale(d,208,168))g.DrawImageUnscaled(big,794,412);Text(g,"04-decoration",794,594,14,false,Color.FromArgb(192,204,183));
   }Save(explode,"layers-breakdown.png");explode.Dispose();
   int changes=0,outside=0;for(int y=0;y<874;y++)for(int x=0;x<402;x++)if(phones[0].GetPixel(x,y)!=phones[2].GetPixel(x,y)){changes++;if(x<20||x>=228||y<226||y>=394)outside++;}if(outside>0)throw new Exception("Variant leaked outside patch");report.Add("A-C changed="+changes+" outside patch="+outside);
   foreach(var p in phones)p.Dispose();foreach(var p in flats)p.Dispose();foreach(var p in lights)p.Dispose();foreach(var p in layers.Values)p.Dispose();baseline.Dispose();motif.Dispose();
  }
  foreach(var s in sprites.Values)s.Dispose();File.WriteAllLines(Path.Combine(dir,"validation.txt"),report);
 }
}
'@
Add-Type -TypeDefinition $sourceCode -ReferencedAssemblies System.Drawing.Common,System.Drawing.Primitives,System.Collections,System.Private.Windows.GdiPlus,System.Private.Windows.Core -CompilerOptions '/nowarn:CA1416'
[CornerStudy]::Build($studyDir,(Join-Path $studyDir 'references/previous-runtime.jpg'))
[CornerStudy]::report
