# Original DS Bot Go geometry and this renderer: MIT, see dsbot-art/LICENSE.
# The legacy asset identifiers and animation metadata remain compatible with saved preferences.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference = 'Stop'
$appRoot = Split-Path $PSScriptRoot -Parent
$art = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'dsbot-art/artwork.json') -Encoding UTF8 -Raw | ConvertFrom-Json
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.Text.RegularExpressions;
public static class DsBotArt {
  static GraphicsPath Shape(string data) {
    var tokens=Regex.Matches(data,@"[MCZ]|-?\d+(?:\.\d+)?");
    var p=new GraphicsPath(FillMode.Winding);int i=0;float x=0,y=0;
    while(i<tokens.Count) {
      var t=tokens[i++].Value;
      if(t=="M") {x=float.Parse(tokens[i++].Value,CultureInfo.InvariantCulture);y=float.Parse(tokens[i++].Value,CultureInfo.InvariantCulture);p.StartFigure();}
      else if(t=="C") {var a=new float[6];for(int j=0;j<6;j++)a[j]=float.Parse(tokens[i++].Value,CultureInfo.InvariantCulture);p.AddBezier(x,y,a[0],a[1],a[2],a[3],a[4],a[5]);x=a[4];y=a[5];}
      else if(t=="Z")p.CloseFigure();else throw new Exception("Invalid vector command");
    }
    return p;
  }
  public static Bitmap Frame(string[] shapes,string[] colors,int w,int h,int index,int count,string pose,bool mask) {
    const int ss=2;
    using(var large=new Bitmap(w*ss,h*ss,PixelFormat.Format32bppArgb)) {
      using(var g=Graphics.FromImage(large)) {
        g.Clear(Color.Transparent);g.SmoothingMode=SmoothingMode.AntiAlias;
        double phase=count<2?0:index*2*Math.PI/count;
        float amount=pose.Contains("happy")||pose.Contains("hop")?4f:1.5f;
        float tilt=pose.Contains("react-left")?-8f:pose.Contains("react-right")?8f:pose.Contains("drag")?12f:pose.Contains("sleep")?0:2f*(float)Math.Sin(phase);
        float fit=Math.Min(w/72f,h/66f)*0.87f;
        g.TranslateTransform(w*ss/2f,(h*0.53f+amount*(float)Math.Sin(phase))*ss);
        g.RotateTransform(tilt);g.ScaleTransform(fit*ss,fit*ss);g.TranslateTransform(-54,-50);
        using(var body=Shape(shapes[0])) {
          if(mask) {
            using(var eyes=Shape(shapes[3]))using(var ink=new Region(body))using(var b=new SolidBrush(Color.White)) {ink.Exclude(eyes);g.FillRegion(b,ink);}
          } else {
            for(int j=0;j<shapes.Length;j++)using(var p=Shape(shapes[j])) {
              if(j==3 && (pose.Contains("sleep") || (count>3 && index==count-2))) {
                using(var m=new Matrix()) {m.Translate(0,54);m.Scale(1,0.12f);m.Translate(0,-54);p.Transform(m);}
              }
              var saved=g.Save();
              if(j==1 || j==2)g.SetClip(body,CombineMode.Intersect);
              using(var b=new SolidBrush(ColorTranslator.FromHtml(colors[j])))g.FillPath(b,p);
              g.Restore(saved);
            }
            if(pose.Contains("error"))using(var b=new SolidBrush(Color.FromArgb(240,98,88)))g.FillEllipse(b,76,28,8,8);
            if(pose.Contains("thinking") || pose.Contains("typing")) {
              using(var b=new SolidBrush(ColorTranslator.FromHtml(colors[1])))for(int k=0;k<3;k++)g.FillEllipse(b,67+k*5,23-(index+k)%3,3,3);
            }
          }
        }
      }
      var result=new Bitmap(w,h,PixelFormat.Format32bppArgb);
      using(var g=Graphics.FromImage(result)){g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.DrawImage(large,0,0,w,h);}
      return result;
    }
  }
  public static void Sheet(string[] shapes,string[] colors,int w,int h,int cols,int frames,string pose,bool mask,int pixelScale,string file) {
    using(var sheet=new Bitmap(w*cols,h*((frames+cols-1)/cols),PixelFormat.Format32bppArgb)) {
      using(var g=Graphics.FromImage(sheet)) {
        g.Clear(Color.Transparent);
        for(int i=0;i<frames;i++)using(var frame=Frame(shapes,colors,w/pixelScale,h/pixelScale,i,frames,pose,mask)) {
          if(pixelScale==1)g.DrawImageUnscaled(frame,(i%cols)*w,(i/cols)*h);
          else for(int y=0;y<frame.Height;y++)for(int x=0;x<frame.Width;x++)using(var b=new SolidBrush(frame.GetPixel(x,y)))g.FillRectangle(b,(i%cols)*w+x*pixelScale,(i/cols)*h+y*pixelScale,pixelScale,pixelScale);
        }
      }
      sheet.Save(file,ImageFormat.Png);
    }
  }
}
'@
$shapes = @('body','fin','belly','bubble') | ForEach-Object { [string]$art.parts.$_ }
$records = @()
foreach ($entry in @(@('deepy-whale','DS Bot','light'), @('whale-girl','DS Bot Night','dark'))) {
  $id,$displayName,$mode = $entry
  $pack = Get-Content -LiteralPath (Join-Path $appRoot "assets/pets/$id/pack.json") -Encoding UTF8 -Raw | ConvertFrom-Json
  $pack.name = $displayName
  $pack.author = 'DS Bot Go contributors'
  $pack.license = 'MIT artwork; AGPL-3.0 animation metadata'
  $pack.source = 'DS Bot Go original Bot artwork; legacy state mappings retained for compatibility'
  $pack.pixelArt = $true
  $dir = Join-Path $OutputRoot "assets/pets/$id"
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $colors = @('body','fin','belly','bubble') | ForEach-Object { [string]$art.palettes.$mode.$_[0] }
  foreach ($a in $pack.animations.PSObject.Properties) {
    $animation = $a.Value
    $frameCount = 1 + ($animation.frames | Measure-Object -Property i -Maximum).Maximum
    $destination = Join-Path $dir $animation.sheet
    [DsBotArt]::Sheet($shapes,$colors,$animation.frameW,$animation.frameH,$animation.cols,$frameCount,$a.Name,$false,$pack.scale,$destination)
    $records += [pscustomobject]@{path="assets/pets/$id/$($animation.sheet)";frames=$frameCount;pose=$a.Name}
  }
  [IO.File]::WriteAllText((Join-Path $dir 'pack.json'), ($pack | ConvertTo-Json -Depth 60), [Text.UTF8Encoding]::new($false))
}
$activity = Get-Content -LiteralPath (Join-Path $appRoot 'assets/whale/whale.json') -Encoding UTF8 -Raw | ConvertFrom-Json
$activityDir = Join-Path $OutputRoot 'assets/whale'
New-Item -ItemType Directory -Path $activityDir -Force | Out-Null
foreach ($level in $activity.levels) {
  [DsBotArt]::Sheet($shapes,@('#FFFFFF','#FFFFFF','#FFFFFF','#FFFFFF'),$activity.frameWidth,$activity.frameHeight,$activity.columns,$level.frames,'activity',$true,1,(Join-Path $activityDir $level.image))
  $level.source = 'DS Bot Go original Bot geometry'
}
[IO.File]::WriteAllText((Join-Path $activityDir 'whale.json'), ($activity | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
$starDir = Join-Path $OutputRoot 'assets/star'
New-Item -ItemType Directory -Path $starDir -Force | Out-Null
$colors = @('body','fin','belly','bubble') | ForEach-Object { [string]$art.palettes.light.$_[0] }
$star = [DsBotArt]::Frame($shapes,$colors,576,576,0,1,'happy',$false)
$star.Save((Join-Path $starDir 'star_bot.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$star.Dispose()
[IO.File]::WriteAllText((Join-Path $OutputRoot 'animation-manifest.json'), ($records | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
Write-Output "Generated $($records.Count) original Bot animation sheets, activity indicators and star picture."
