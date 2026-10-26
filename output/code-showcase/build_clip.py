from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import re, subprocess, json
ROOT=Path('/Users/mitchellliu/Downloads/woundscope'); OUT=ROOT/'output/code-showcase'
W,H=1920,1080
FONT='/System/Library/Fonts/Supplemental/Arial.ttf'; BOLD='/System/Library/Fonts/Supplemental/Arial Bold.ttf'; MONO='/System/Library/Fonts/Menlo.ttc'
def font(n,b=False,mono=False): return ImageFont.truetype(MONO if mono else BOLD if b else FONT,n)
BG='#08131c'; PANEL='#101f2b'; EDGE='#263b49'; WHITE='#edf5f7'; MUTED='#9bb1be'; MINT='#6ce4c0'; GOLD='#f2ce83'
def text(d,xy,s,n=24,c=WHITE,b=False,mono=False): d.text(xy,s,font=font(n,b,mono),fill=c)
def rr(d,box,fill,r=22,outline=None): d.rounded_rectangle(box,r,fill=fill,outline=outline,width=1)
base=ROOT/'LiDARDepth/Model/Code/Codes'
def lines(file,start,end):
 a=(base/file).read_text().splitlines(); selected=a[start-1:end]; trim=min(len(x)-len(x.lstrip()) for x in selected if x.strip()); return [(start+i,s[trim:]) for i,s in enumerate(selected)]
contract='WoundSemantic/WoundModelContract.swift'
scenes=[dict(title='Nine classes. One confidence threshold.',file='WoundModelContract.swift',tag='01 / DEFINE',note='Includes normal control • uncertainty threshold: 0.36',blocks=[lines(contract,3,12),lines(contract,49,49)+lines(contract,54,54)+lines(contract,61,61)],highlight=[54],caption='Nine classification categories, including normal control. Confidence below 0.36 is flagged as uncertain.'),dict(title='Uncertain? Stop before further analysis.',file='ARCameraTabView.swift',tag='02 / GATE',note='Engineering decision: uncertainty exits the analysis path.',blocks=[lines('ARCameraTabView.swift',275,279)],highlight=[275,278],caption='An early return prevents uncertain classifier results from continuing to the optional vision-language model.'),dict(title='Run the selected model on-device.',file='ARCameraTabView.swift',tag='03 / ANALYZE',note='Qwen3.5-4B • local model + vision projector + prompt',blocks=[lines('ARCameraTabView.swift',350,358)],highlight=[355,356,357,358],caption='When checks pass and on-device analysis is selected, the app sends the image and prompt to the local model.')]
shot=Image.open(OUT/'app-demo.png').convert('RGB')
# Crop to the actual result UI; no app content is reconstructed.
shot=shot.crop((0,735,1206,2622)); shot.thumbnail((448,701),Image.Resampling.LANCZOS)
pattern=re.compile(r'("(?:[^"\\]|\\.)*"|\b(?:enum|case|static|let|guard|else|return|if|try|await|nil)\b|\b\d+(?:[._]\d+)*\b|//.*$)')
def code_line(d,x,y,line,size=23):
 pos=x
 for seg in pattern.split(line):
  if not seg: continue
  col=WHITE
  if seg.startswith('"'): col='#b9df9b'
  elif seg.startswith('//'): col=MUTED
  elif re.fullmatch(r'\d+(?:[._]\d+)*',seg): col=GOLD
  elif seg in ['enum','case','static','let','guard','else','return','if','try','await','nil']: col='#c3a6ff'
  elif any(v in seg for v in ['confidenceThreshold','isClassificationUncertain','ggufBridge.analyze']): col=MINT
  text(d,(pos,y),seg,size,col,mono=True); pos+=d.textlength(seg,font=font(size,mono=True))
def wrap(s,maxlen):
 if len(s)<=maxlen:return [s]
 # Presentation-only soft wrapping. Source characters are retained.
 parts=[]
 while len(s)>maxlen:
  ix=max(s.rfind(' ',0,maxlen),s.rfind(':',0,maxlen)+1,s.rfind('.',0,maxlen),s.rfind('(',0,maxlen)+1)
  if ix<maxlen//2: ix=maxlen
  parts.append(s[:ix]); s='    '+s[ix:].lstrip()
 parts.append(s);return parts
frames=[]
for idx,s in enumerate(scenes):
 im=Image.new('RGB',(W,H),BG); d=ImageDraw.Draw(im)
 text(d,(64,78),'Confidence gates the next step.',52,WHITE,True)
 text(d,(66,152),'Real Swift source, paired with a captured app demo.',25,MUTED)
 rr(d,(64,214,584,948),PANEL,26,EDGE)
 text(d,(91,235),'APP PREVIEW',18,MINT,True)
 text(d,(91,265),'iPhone simulator · demo fixture',18,MUTED)
 # Visible UI viewport keeps original pixels and source text intact.
 view=shot.resize((448,701),Image.Resampling.LANCZOS)
 mask=Image.new('L',view.size,0); ImageDraw.Draw(mask).rounded_rectangle((0,0,447,700),16,fill=255)
 # fit screenshot into viewport, clipping only the lower continuation
 view=view.crop((0,0,448,597)); mask=mask.crop((0,0,448,597)); im.paste(view,(100,313),mask)
 rr(d,(612,214,1856,948),PANEL,26,EDGE)
 for j,col in enumerate(['#f58f86','#edc46e','#6fc8a3']):d.ellipse((640+j*23,240,652+j*23,252),fill=col)
 text(d,(735,233),s['file'],21,MUTED,mono=True)
 text(d,(1674,235),s['tag'],18,MINT,True)
 d.line((613,278,1855,278),fill=EDGE,width=1)
 text(d,(648,303),s['title'],34,WHITE,True)
 text(d,(648,351),s['note'],22,MUTED)
 y=408 if idx!=1 else 446
 for block_i,block in enumerate(s['blocks']):
  if block_i: y+=15; text(d,(710,y),'// ...',20,MUTED); y+=28
  for no,line in block:
   parts=wrap(line,73)
   for pi,part in enumerate(parts):
    if no in s['highlight']:
     rr(d,(632,y-3,1834,y+30),'#183c37',5)
     d.rectangle((633,y-3,636,y+30),fill=MINT)
    if pi==0:text(d,(650,y+2),str(no),18,'#6f8999',mono=True)
    code_line(d,710,y,part,23);y+=33
 if idx==1:
  rr(d,(650,698,1815,839),'#142e32',18)
  text(d,(680,721),'LOW CONFIDENCE',18,MINT,True)
  text(d,(680,758),'Flag uncertainty  →  return  →  withhold further analysis',27,WHITE,True)
 text(d,(648,907),'Source excerpts · original line numbers · long lines wrap',17,MUTED)
 # Persistent honest footage label.
 text(d,(87,922),'Captured UI • not a live Qwen inference',16,MUTED)
 text(d,(65,981),s['caption'],25,WHITE)
 text(d,(65,1026),'PHOTO CHECK',17,MINT,True)
 text(d,(286,1026),'CONFIDENCE GATE',17,MINT if idx>=1 else MUTED,True)
 text(d,(568,1026),'OPTIONAL LOCAL ANALYSIS',17,MINT if idx>=2 else MUTED,True)
 im.save(OUT/f'scene-{idx+1}.png'); frames.append(im)
ff='/Applications/Badlion Client.app/Contents/ffmpeg'
proc=subprocess.Popen([ff,'-y','-f','rawvideo','-vcodec','rawvideo','-pix_fmt','rgb24','-s','1920x1080','-r','30','-i','-','-an','-c:v','libx264','-preset','fast','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT/'WoundCorder-code-showcase-25s.mp4')],stdin=subprocess.PIPE,stderr=open(OUT/'render.log','w'))
for f in range(750):
 t=f/30; i=0 if t<7 else 1 if t<15 else 2; im=frames[i].copy()
 boundary=7 if i==1 else 15
 if i and t-boundary<0.45: im=Image.blend(frames[i-1],im,(t-boundary)/0.45)
 d=ImageDraw.Draw(im);d.rectangle((0,1073,int(W*(f+1)/750),1079),fill=MINT)
 proc.stdin.write(im.tobytes())
proc.stdin.close(); assert proc.wait()==0
(OUT/'narration.txt').write_text('The classifier scores nine categories and flags confidence below zero point three six as uncertain. That uncertainty triggers an early return before further analysis. When checks pass and on-device analysis is selected, Qwen processes the image and health context locally.\n\nApp imagery: actual iPhone simulator screenshot of WoundReviewHarness; fixed demo result, not live Qwen inference.\nSource code excerpts preserve original line numbers; long lines wrap for presentation.\n')
(OUT/'index.html').write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>WoundCorder · Code showcase</title><style>body{margin:0;background:#08131c;color:#edf5f7;font:18px system-ui;padding:4vw}h1{font-size:30px}p{color:#9bb1be}video{width:100%;max-height:80vh;border-radius:18px}a{color:#6ce4c0}</style><h1>WoundCorder · Confidence gates the next step</h1><video src="WoundCorder-code-showcase-25s.mp4" controls autoplay muted playsinline poster="scene-2.png"></video><p>25 seconds · 1920 × 1080 · Real Swift excerpts + captured iPhone simulator demo UI.</p><a href="WoundCorder-code-showcase-25s.mp4" download>Download MP4</a> · <a href="narration.txt">Narration and capture notes</a></html>''')
print('Rendered 25-second 1080p MP4')
