param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.Text.RegularExpressions;
public static class GoIconRender {
  public static GraphicsPath Path(string data) {
    var ts=Regex.Matches(data,@"[MCZ]|-?\d+(?:\.\d+)?"); var p=new GraphicsPath(FillMode.Winding); int i=0; float x=0,y=0;
    while(i<ts.Count) { string t=ts[i++].Value; if(t=="M") {x=float.Parse(ts[i++].Value,CultureInfo.InvariantCulture); y=float.Parse(ts[i++].Value,CultureInfo.InvariantCulture);p.StartFigure();}
      else if(t=="C") {var a=new float[6];for(int j=0;j<6;j++)a[j]=float.Parse(ts[i++].Value,CultureInfo.InvariantCulture);p.AddBezier(x,y,a[0],a[1],a[2],a[3],a[4],a[5]);x=a[4];y=a[5];}
      else if(t=="Z") p.CloseFigure(); else throw new Exception("Unknown path token "+t); }
    return p;
  }
  public static Bitmap Draw(string[] paths,string[] starts,string[] ends,int size,string background,bool foreground,bool circle) {
    int ss=4;var large=new Bitmap(size*ss,size*ss,PixelFormat.Format32bppArgb);
    using(var g=Graphics.FromImage(large)) {g.Clear(Color.Transparent);g.SmoothingMode=SmoothingMode.AntiAlias;g.ScaleTransform(size*ss/108f,size*ss/108f);
      if(!foreground) {using(var brush=new SolidBrush(ColorTranslator.FromHtml(background))) {
        if(circle)g.FillEllipse(brush,3,3,102,102);else using(var tile=Path("M31 6 C18 6 6 18 6 31 C6 31 6 77 6 77 C6 90 18 102 31 102 C31 102 77 102 77 102 C90 102 102 90 102 77 C102 77 102 31 102 31 C102 18 90 6 77 6 C77 6 31 6 31 6 Z"))g.FillPath(brush,tile);
      }}
      for(int j=0;j<paths.Length;j++)using(var p=Path(paths[j]))using(var brush=new LinearGradientBrush(new PointF(30,35),new PointF(80,77),ColorTranslator.FromHtml(starts[j]),ColorTranslator.FromHtml(ends[j])))g.FillPath(brush,p);
    }
    var result=new Bitmap(size,size,PixelFormat.Format32bppArgb);using(var g=Graphics.FromImage(result)){g.CompositingQuality=CompositingQuality.HighQuality;g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.PixelOffsetMode=PixelOffsetMode.HighQuality;g.DrawImage(large,0,0,size,size);}large.Dispose();return result;
  }
}
'@
$art=Get-Content -LiteralPath (Join-Path $Root 'artwork.json') -Raw | ConvertFrom-Json
$names=@('body','fin','belly','bubble')
$paths=[string[]]@($names | ForEach-Object {$art.parts.$_})
function Save-Icon([string]$Rel,[int]$Size,[string]$Mode,[string]$Bg,[bool]$Foreground=$false,[bool]$Circle=$false) {
  $start=[string[]]@($names | ForEach-Object {$art.palettes.$Mode.$_[0]})
  $end=[string[]]@($names | ForEach-Object {$art.palettes.$Mode.$_[1]})
  $bitmap=[GoIconRender]::Draw($paths,$start,$end,$Size,$Bg,$Foreground,$Circle)
  $target=Join-Path $Root $Rel
  New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
  try {$bitmap.Save($target,[System.Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
}
Save-Icon 'icon-1024.png' 1024 'light' '#F7F9FD'
Save-Icon 'icon-512.png' 512 'light' '#F7F9FD'
Save-Icon 'icon-dark-512.png' 512 'dark' '#18243D'
Save-Icon 'mark-512.png' 512 'light' '#F7F9FD' $true
$res='app/android/app/src/main/res'
foreach($variant in $art.variants) {
  foreach($density in $art.densities.PSObject.Properties) {
    $prefix="$res/mipmap-$($density.Name)/ic_launcher$($variant.suffix)"
    Save-Icon "$prefix.png" ([int]$density.Value[0]) $variant.mode $variant.bg
    Save-Icon "${prefix}_round.png" ([int]$density.Value[0]) $variant.mode $variant.bg $false $true
    Save-Icon "${prefix}_foreground.png" ([int]$density.Value[1]) $variant.mode $variant.bg $true
  }
}
$sheet=New-Object System.Drawing.Bitmap 1280,760
$g=[System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.ColorTranslator]::FromHtml('#EFF3FA'))
$g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$font=New-Object System.Drawing.Font 'Segoe UI',30,([System.Drawing.FontStyle]::Bold)
$small=New-Object System.Drawing.Font 'Segoe UI',16
$ink=New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#22324C'))
$g.DrawString('DS Bot Go',$font,$ink,52,30)
$g.DrawString('Original app icon / Blue Bot in motion',$small,$ink,54,90)
foreach($job in @(@('icon-512.png',64,146),@('icon-dark-512.png',440,146),@('app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png',816,146))) {
  $im=[System.Drawing.Image]::FromFile((Join-Path $Root $job[0]));$g.DrawImage($im,[int]$job[1],[int]$job[2],320,320);$im.Dispose()
}
$g.DrawString('Light / 1024 master',$small,$ink,86,494)
$g.DrawString('Dark / alternate launcher',$small,$ink,454,494)
$g.DrawString('Circular mask',$small,$ink,876,494)
$xx=76
foreach($size in @(24,32,48,64,96)) {
  $bm=[GoIconRender]::Draw($paths,([string[]]@($names|ForEach-Object{$art.palettes.light.$_[0]})),([string[]]@($names|ForEach-Object{$art.palettes.light.$_[1]})),$size,'#F7F9FD',$false,$false)
  $g.DrawImage($bm,$xx,580,$size,$size);$bm.Dispose();$g.DrawString("${size}px",$small,$ink,$xx,688);$xx+=180
}
$g.Dispose();$font.Dispose();$small.Dispose();$ink.Dispose()
$sheet.Save((Join-Path $Root 'preview.png'),[System.Drawing.Imaging.ImageFormat]::Png);$sheet.Dispose()
Write-Output 'Rendered original icon, 60 density PNGs and preview.'
