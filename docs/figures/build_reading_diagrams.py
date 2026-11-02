"""Exact, editable teaching diagrams: shared vector scene -> SVG and PNG.

Run with Python + Pillow. Existing raster illustrations are not edited.
The default Korean font is Malgun Gothic; override FONT_REG/FONT_BOLD on other OSes.
"""
import os, math, json, html
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT=Path(__file__).resolve().parent/'reading-v1';OUT.mkdir(parents=True,exist_ok=True)
REG=os.environ.get('FONT_REG','C:/Windows/Fonts/malgun.ttf')
BOLD=os.environ.get('FONT_BOLD','C:/Windows/Fonts/malgunbd.ttf')
INK='#18314b';BLUE='#245eaa';TEAL='#087b78';ORANGE='#b95818';BG='#f5f8fc';GRAY='#586a7d'
manifest={}
class Fig:
 def __init__(self,key,title,sub,h=780):
  self.key=key;self.h=h;self.im=Image.new('RGB',(1600,h),BG);self.d=ImageDraw.Draw(self.im)
  self.svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="{h}" viewBox="0 0 1600 {h}" role="img" aria-labelledby="title desc">',f'<title id="title">{html.escape(title)}</title>',f'<desc id="desc">{html.escape(sub)}</desc>',f'<rect width="1600" height="{h}" fill="{BG}"/>'];self.labels=[]
  self.text(55,36,title,43,INK,True);self.text(55,102,sub,27,GRAY)
 def text(self,x,y,s,size=30,color=INK,bold=False):
  f=ImageFont.truetype(BOLD if bold else REG,size)
  w=self.d.textlength(s,font=f)
  assert x>=0 and x+w<=1560,(self.key,s,x,w)
  assert y+size+12<=self.h,(self.key,s,y)
  self.d.text((x,y),s,font=f,fill=color,anchor='lt')
  self.svg.append(f'<text x="{x}" y="{y}" dominant-baseline="hanging" font-family="Malgun Gothic, Noto Sans CJK KR, sans-serif" font-size="{size}" font-weight="{700 if bold else 400}" fill="{color}">{html.escape(s)}</text>');self.labels.append(s)
 def rect(self,x,y,w,h,fill='white',stroke=BLUE,r=15):
  self.d.rounded_rectangle((x,y,x+w,y+h),r,fill=fill,outline=stroke,width=3)
  self.svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="3"/>')
 def line(self,pts,color=TEAL,width=5):
  self.d.line(pts,fill=color,width=width);self.svg.append(f'<polyline points="'+ ' '.join(f'{x},{y}' for x,y in pts)+f'" fill="none" stroke="{color}" stroke-width="{width}" stroke-linejoin="round"/>')
 def arrow(self,pts,color=TEAL):
  self.line(pts,color);(x0,y0),(x,y)=pts[-2:];a=math.atan2(y-y0,x-x0)
  points=[(x,y),(x-17*math.cos(a)+9*math.sin(a),y-17*math.sin(a)-9*math.cos(a)),(x-17*math.cos(a)-9*math.sin(a),y-17*math.sin(a)+9*math.cos(a))]
  self.d.polygon(points,fill=color);self.svg.append('<polygon points="'+' '.join(f'{xx},{yy}' for xx,yy in points)+f'" fill="{color}"/>')
 def box(self,x,y,w,h,title,lines=(),color=BLUE):
  self.rect(x,y,w,h,stroke=color);self.text(x+20,y+20,title,32,color,True)
  for n,s in enumerate(lines):
   assert self.d.textlength(s,font=ImageFont.truetype(REG,28))<=w-40,(self.key,s,w)
   self.text(x+20,y+78+n*43,s,28)
 def grid(self,x,y,values,size=58,highlight=None):
  for row,vs in enumerate(values):
   for col,v in enumerate(vs):
    fill='#d4eeeb' if highlight and highlight(row,col) else 'white'
    self.rect(x+col*size,y+row*size,size-3,size-3,fill=fill,stroke='#a5b4c5',r=2)
    self.text(x+col*size+14,y+row*size+12,str(v),30,bold=True)
 def finish(self,caption):
  self.text(55,self.h-61,caption,25,GRAY)
  self.im.save(OUT/(self.key+'.png'));(OUT/(self.key+'.svg')).write_text('\n'.join(self.svg+['</svg>']),encoding='utf-8')
  manifest[self.key]={'title':self.labels[0],'caption':caption,'labels':self.labels,'png':self.key+'.png','svg':self.key+'.svg','size':[1600,self.h]}

# A0: two routes, no future optimization vocabulary.
f=Fig('A0','학습에서는 고치고, 추론에서는 사용합니다','두 줄을 따로 읽으세요. 아래의 새 사진에는 정답을 넣지 않습니다.')
f.text(55,184,'학습',32,BLUE,True)
for x,t,ls in [(220,'사진과 정답',['연습할 예제']), (660,'예측하고 비교',['어디가 틀렸는지 확인']), (1100,'계산에 쓰는 숫자 수정',['반복하며 더 잘 맞히기'])]:f.box(x,175,400,175,t,ls)
f.arrow([(625,263),(645,263)]);f.arrow([(1065,263),(1085,263)])
f.arrow([(1300,355),(1300,390),(420,390),(420,355)],BLUE)
f.text(55,450,'추론',32,TEAL,True)
for x,t,ls in [(220,'새 사진',['정답 없이 입력']), (660,'배운 숫자로 계산',['학습한 값을 사용']), (1100,'예측',['고양이 또는 자동차'])]:f.box(x,440,400,175,t,ls,TEAL)
f.arrow([(625,528),(645,528)]);f.arrow([(1065,528),(1085,528)])
f.finish('학습한 숫자는 같아도, 새 사진을 넣으면 중간 계산과 예측은 달라집니다.')

f=Fig('A1','사진 한 점에는 색 값이 세 개 있습니다','아래 색 값은 읽는 방법을 보여 주는 예시입니다. 실제 사진을 분해한 측정값은 아닙니다.')
for x,title,val,c in [(70,'빨강 R','120','#af3937'),(575,'초록 G','80','#307b48'),(1080,'파랑 B','40','#245eaa')]:f.box(x,180,450,175,title,[f'한 점의 값: {val}'],c)
f.text(70,407,'사진 묶음의 크기 [1, 3, 32, 32] 읽기',32,INK,True)
for n,(val,label) in enumerate([('1','사진 수'),('3','색별 묶음 수'),('32','세로 칸 수'),('32','가로 칸 수')]):
 x=70+n*380;f.box(x,468,335,155,val,[label],TEAL)
f.finish('사진 1장 × 색 3종류 × 세로 32칸 × 가로 32칸 = 숫자 3,072개')

f=Fig('A2','곱해서 더하기 → 기본값 더하기 → ReLU','본문의 밝기 예제: 왼쪽 8, 오른쪽 2. 왼쪽이 얼마나 더 밝은지 계산합니다.')
f.box(60,200,440,260,'1. Weight로 곱하기',['왼쪽: 8 × (+1) = 8','오른쪽: 2 × (-1) = -2','합: 8 + (-2) = 6'])
f.box(580,200,440,260,'2. Bias 더하기',['기본값은 -3','6 + (-3) = 3'],TEAL)
f.box(1100,200,440,260,'3. ReLU 적용',['음수는 0으로','양수 3은 그대로 3'],ORANGE)
f.arrow([(505,320),(565,320)]);f.arrow([(1025,320),(1085,320)])
f.text(70,535,'같은 규칙으로 -2를 ReLU에 넣으면 0이 됩니다.',32,INK,True)
f.finish('Weight는 곱하는 값, Bias는 합에 더하는 기본값입니다. 양수 Weight가 더 중요하다는 뜻은 아닙니다.')

f=Fig('A3','앞 결과가 다음 입력이 됩니다','본문과 같은 두 단계 계산입니다. 화살표는 숫자가 전달되는 방향입니다.',650)
items=[(55,200,'입력','2'),(355,270,'첫 계산','2 × 3 - 1 = 5'),(725,230,'다음 입력','5'),(1055,460,'두 번째 계산','5 × 2 = 10')]
for x,w,title,s in items:f.box(x,230,w,185,title,[s],BLUE if title!='다음 입력' else TEAL)
for x1,x2 in [(260,340),(630,710),(960,1040)]:f.arrow([(x1,322),(x2,322)])
f.finish('첫 계산의 출력 5를 그대로 받아 다음 계산의 입력으로 씁니다.')

f=Fig('A4','Loss는 확률 자체가 아니라 채점한 벌점입니다','정답이 고양이인 사진에 준 확률을 비교합니다. 채점 규칙은 본문의 교차 엔트로피입니다.',820)
for x,p,loss in [(60,.9,-math.log(.9)),(575,.5,-math.log(.5)),(1090,.1,-math.log(.1))]:
 f.box(x,180,450,280,f'고양이 확률 {p:.0%}',[f'벌점 약 {loss:.2f}'],TEAL if p==.9 else BLUE)
 f.rect(x+20,360,405*loss/2.4,42,fill=ORANGE,stroke=ORANGE,r=3)
f.text(65,485,'주황 막대는 벌점입니다. 세 막대는 같은 눈금으로 그렸습니다.',26,GRAY)
f.box(60,555,1480,150,'별도 예제: 계산에 쓰는 값 한 번 고치기',['Weight 0.5, 기울기 -2, 학습률 0.1 → 새 Weight = 0.5 - 0.1 × (-2) = 0.7'],TEAL)
f.finish('정답에 준 확률이 낮을수록 벌점은 커집니다. 값을 고친 뒤에는 다시 예측하고 채점합니다.')

f=Fig('A5','연습·설정 점검·최종 시험은 나눕니다','같은 문제를 반복해서 잘 푸는 것만으로 새 문제의 실력을 알 수는 없습니다.')
for x,t,ls,c in [(60,'Train · 연습문제',['계산에 쓰는 숫자를 학습','배우는 동안 반복 사용'],BLUE),(575,'Validation · 점검 문제',['공부 방법과 설정 선택','후보를 비교할 때 사용'],TEAL),(1090,'Test · 최종 시험',['선택을 마친 뒤 평가','결과를 보고 계속 고치지 않기'],ORANGE)]:f.box(x,190,450,245,t,ls,c)
f.text(70,500,'정확도: 10문제 중 9문제를 맞혔다면 90%',32,INK,True)
for n in range(10):f.rect(70+n*120,565,92,64,fill=TEAL if n<9 else 'white',stroke=TEAL)
f.text(1310,582,'9 ÷ 10',32,TEAL,True)
f.finish('문제 묶음은 역할에 따라 나눕니다. 그림은 개념 예시이며 실제 프로젝트 평가 결과가 아닙니다.')

X=[[5,4,1,0],[4,3,1,0],[3,2,0,0],[2,1,0,0]];K=[[1,0,-1]]*3
Y=[[sum(X[y+r][x+c]*K[r][c] for r in range(3) for c in range(3)) for x in range(2)] for y in range(2)]
assert Y==[[10,9],[8,6]]
f=Fig('B1','입력과 필터는 계산에 함께 들어갑니다','한 칸씩 이동 · 가장자리 추가 없음 · Bias 0 · 입력 채널과 출력 채널 각각 1개',860)
f.text(70,170,'입력 4×4',30,BLUE,True);f.grid(70,225,X,67,lambda r,c:r<3 and c<3)
f.text(450,170,'같은 필터 3×3',30,TEAL,True);f.grid(450,225,K,67)
f.box(820,230,320,215,'같은 위치끼리',['곱한 뒤','모두 더하기'],TEAL)
f.arrow([(343,425),(380,425),(380,510),(770,510),(770,400),(805,400)]);f.arrow([(655,280),(745,280),(805,280)])
f.text(1230,170,'출력 2×2',30,BLUE,True);f.grid(1230,245,Y,85,lambda r,c:r==0 and c==0);f.arrow([(1145,335),(1215,335)])
f.text(70,570,'첫 출력: (5 + 4 + 3) - (1 + 1 + 0) = 10',36,INK,True)
f.text(70,640,'같은 필터를 네 위치에서 사용 → 9번씩 곱해 더하기 × 4곳 = 36 MAC',29)
f.finish('숫자 9개짜리 필터는 사람이 정한 예제입니다. 입력 사진에서 필터가 생성되는 그림이 아닙니다.')

f=Fig('B2','입력 채널 세 개의 결과를 합쳐 출력 한 칸을 만듭니다','Bias 0인 예제입니다. R·G·B마다 자기 필터로 계산하고 세 결과를 더합니다.')
for y,title,result,c in [(180,'R 계산',2,'#af3937'),(350,'G 계산',3,'#307b48'),(520,'B 계산',-1,BLUE)]:
 f.box(65,y,550,135,title,[f'이 색의 입력 × 이 색에 쓸 필터 → {result}'],c);f.arrow([(620,y+68),(800,y+68),(800,418),(955,418)])
f.box(970,305,550,230,'한 출력에 더하기',['2 + 3 + (-1) = 4','출력 한 칸 = 4'],TEAL)
f.finish('필터가 3×3이고 입력 채널이 3개이면, 출력 한 칸에 3×3×3 = 27번 곱해서 더합니다.')

f=Fig('B3','채널별 평균을 낸 뒤 후보별 점수를 계산합니다','두 채널과 두 후보만 둔 작은 예제입니다. 실제 CIFAR-10 모델은 후보가 10개입니다.',820)
f.text(65,174,'채널 1',28,BLUE,True);f.grid(65,220,[[1,3],[1,3]],67)
f.text(65,405,'채널 2',28,TEAL,True);f.grid(65,450,[[2,4],[2,4]],67)
f.box(390,230,350,330,'전체 평균 · GAP',['채널 1: 8 ÷ 4 = 2','채널 2: 12 ÷ 4 = 3','요약값 [2, 3]'])
f.arrow([(207,287),(300,287),(375,317)]);f.arrow([(207,517),(300,517),(375,467)])
f.box(900,230,620,330,'후보별 점수 · FC',['고양이: 2×1 + 3×1 = 5','강아지: 2×1 + 3×0 = 2','가장 큰 점수 5 → 고양이 선택'],TEAL);f.arrow([(745,395),(885,395)])
f.finish('예제 Weight와 Bias 0은 설명용입니다. 점수 5는 확률 500%라는 뜻이 아닙니다.')

f=Fig('A7','평균을 빼면 값의 중심이 옮겨집니다','배치 정규화 전체가 아니라 본문의 ‘평균 빼기’ 한 단계만 보여 줍니다.')
for x,title,ls in [(65,'원래 값',['[2, 4, 6]','평균: (2+4+6)÷3 = 4']),(575,'각 값에서 평균 빼기',['[2-4, 4-4, 6-4]']),(1085,'중심을 옮긴 값',['[-2, 0, 2]','평균은 0'])]:f.box(x,215,450,240,title,ls,TEAL)
f.arrow([(520,335),(560,335)]);f.arrow([(1030,335),(1070,335)])
f.text(70,535,'전체 BN에서는 값이 퍼진 정도와 학습한 곱셈값·덧셈값도 사용합니다.',29)
f.finish('추론할 때는 학습 중 저장한 평균 등을 사용합니다. 이 그림은 BN 전체 계산의 출력 예제가 아닙니다.')

f=Fig('B4','원래 값과 계산한 변화를 따로 보내 마지막에 더합니다','본문의 작은 예: 원래 값 3, 계산한 변화 -1. 두 화살표가 만나는 곳에서 더합니다.',820)
f.box(65,300,240,160,'입력 X',['3'])
f.box(490,170,420,180,'계산하는 길 · Main',['Conv1 → ReLU → Conv2','계산한 변화: -1'])
f.box(490,455,420,160,'원래 값을 보내는 길',['X = 3 그대로 보관'],TEAL)
f.arrow([(310,380),(380,380),(380,260),(475,260)]);f.arrow([(380,380),(380,535),(475,535)],TEAL)
f.box(1100,300,425,230,'더하기 → ReLU',['3 + (-1) = 2','ReLU 뒤에도 2'],ORANGE)
f.arrow([(915,260),(1000,260),(1000,355),(1085,355)]);f.arrow([(915,535),(1000,535),(1000,470),(1085,470)],TEAL)
f.finish('더하기 전에 -1을 0으로 바꾸면 3이 되어 결과가 달라집니다. 원래 X도 더하기까지 보관합니다.')

f=Fig('B5','사진 크기의 변화를 한 줄씩 따라갑니다','사진 1장 기준 · 숫자 순서는 채널 수 × 세로 × 가로 · 화살표 순서로 읽습니다.',860)
nodes=[(60,190,'1. 입력','3 × 32 × 32'),(575,190,'2. 첫 Conv · Stem','16 × 32 × 32'),(1090,190,'3. 블록 묶음 1','16 × 32 × 32'),(1090,480,'4. 블록 묶음 2','32 × 16 × 16'),(575,480,'5. 블록 묶음 3','64 × 8 × 8'),(60,480,'6. 평균 → 점수','64개 → 10개')]
for x,y,t,s in nodes:f.box(x,y,450,200,t,[s],TEAL if y==480 else BLUE)
f.arrow([(515,290),(560,290)]);f.arrow([(1030,290),(1075,290)]);f.arrow([(1315,395),(1315,465)]);f.arrow([(1085,580),(1040,580)]);f.arrow([(570,580),(525,580)])
f.text(70,735,'각 블록 묶음(Stage)은 블록 3개입니다. 가로·세로가 줄어드는 곳을 찾아보세요.',28)
f.finish('같은 크기에서 반복하는 블록과 크기를 바꾸는 블록을 연결합니다. 회로 작업 수는 상세 실행표에서 봅니다.')

f=Fig('A6','정수에 눈금을 곱해야 실제 값이 됩니다','이 그림에서는 실제 0을 정수 0으로 저장합니다. 두 줄은 실제 값이 같지만 저장한 정수가 다릅니다.',850)
for y,label,q,scale in [(185,'첫 번째 값',8,'1/8'),(375,'두 번째 값',4,'1/4')]:
 f.box(60,y,440,145,label,[f'저장한 정수 {q}'],BLUE)
 f.box(580,y,440,145,'눈금 적용',[f'{q} × {scale} = 1'],TEAL)
 f.box(1100,y,440,145,'실제 값',['1'],TEAL)
 f.arrow([(505,y+73),(565,y+73)]);f.arrow([(1025,y+73),(1085,y+73)])
f.box(60,580,1480,145,'두 값을 더하면 실제 값은 2',['출력 눈금 1/8에 맞춰 저장 → 2 ÷ (1/8) = 정수 16'],ORANGE)
f.finish('8+4=12로 바로 더하면 눈금이 섞입니다. 두 값을 같은 눈금으로 맞춘 뒤 더합니다.')

f=Fig('D1','중간 합은 넓게 담고, 반올림 규칙을 맞춥니다','윗줄은 저장 범위, 아랫줄은 반올림 예입니다. 두 예는 별개로 읽습니다.',820)
f.box(60,180,450,180,'입력과 Weight',['100과 100은 각각','INT8에 담을 수 있음'])
f.box(575,180,450,180,'곱한 결과',['100 × 100 = 10,000','INT8 범위를 넘음'],ORANGE)
f.box(1090,180,450,180,'넓은 중간 합',['INT32로 더한 뒤','출력 눈금으로 바꾸기'],TEAL)
f.arrow([(515,270),(560,270)]);f.arrow([(1030,270),(1075,270)])
f.text(65,428,'RNE: 정확히 중간이면 짝수를 선택합니다.',32,INK,True)
for n,(val,out) in enumerate([('2.5','2'),('3.5','4'),('-2.5','-2'),('-3.5','-4')]):f.box(60+n*385,500,325,165,val,[f'반올림 → {out}'],TEAL)
f.finish('반올림한 값이 허용 범위를 넘으면 끝값에 붙입니다. 소프트웨어와 회로가 같은 약속을 사용합니다.')

f=Fig('D2','같은 계산기를 두 번 써도 합을 만들 수 있습니다','본문의 예: 2×3을 더하고, 이어 4×1을 더합니다. 이 그림은 실제 클록 수를 나타내지 않습니다.')
for x,t,ls in [(65,'시작',['중간 합 = 0']),(575,'첫 계산',['0 + 2×3 = 6','중간 합 = 6']),(1085,'두 번째 계산',['6 + 4×1 = 10','중간 합 = 10'])]:f.box(x,210,450,240,t,ls,TEAL)
f.arrow([(520,330),(560,330)]);f.arrow([(1030,330),(1070,330)])
f.box(65,520,1470,140,'계산 횟수와 계산기 개수는 다릅니다',['곱해서 더하기는 두 번입니다. 한 계산기를 순서대로 재사용할 수 있습니다.'])
f.finish('입력이 아직 준비되지 않았다면 기다립니다. 전달 시점과 대기 규칙은 D5에서 이어집니다.')

f=Fig('D3','같은 필터를 가까이 두고 다시 씁니다','B1의 필터 숫자 9개를 네 출력 위치에 재사용하는 개념도입니다.')
f.box(65,190,450,215,'큰 저장소',['필터 숫자 9개 보관'])
f.box(575,190,450,215,'계산기 옆 작은 저장소',['필터 숫자 9개를 가져옴','버리지 않고 보관'],TEAL)
f.box(1085,190,450,215,'계산기',['위치 1 → 2 → 3 → 4','같은 필터로 계산'])
f.arrow([(520,295),(560,295)]);f.arrow([(1030,295),(1070,295)])
f.text(575,450,'다음 위치에서도 보관한 같은 필터를 읽습니다.',30,TEAL)
for x,t,ls in [(65,'얼마나 담나?',['용량 · Capacity']),(575,'얼마나 빨리 옮기나?',['대역폭 · Bandwidth']),(1085,'얼마나 기다리나?',['응답 시간 · Latency'])]:f.box(x,535,450,130,t,ls)
f.finish('재사용하면 멀리서 반복해서 가져오는 횟수를 줄일 수 있습니다. 실제 저장 위치는 설계마다 다릅니다.')

f=Fig('D5','준비됐다는 표시와 실제 전달은 다릅니다','각 열은 클록이 0에서 1로 바뀌는 순간입니다. 같은 값 A를 보내는 세 순간만 봅니다.')
for n,(edge,ready,result) in enumerate([('첫 순간',0,'대기'),('둘째 순간',0,'대기'),('셋째 순간',1,'A를 한 번 전달')]):
 x=65+n*510;f.box(x,190,450,335,edge,['보낼 값: A','Valid = 1',f'Ready = {ready}',result],TEAL if ready else BLUE)
f.text(70,585,'두 번 기다리는 동안에도 값 A를 그대로 유지합니다.',32,INK,True)
f.finish('Valid와 Ready가 모두 1인 상승 에지에서만 전달합니다. A가 보이는 횟수 3번과 전달 1번은 다릅니다.')

# Replacement for an unrelated S6 roadmap: board steps use already explained terms.
f=Fig('S6','보드에서는 시작·완료·네 결과를 확인합니다','아래는 실행 순서 안내입니다. 실제 보드 실행 결과나 통과 증거를 나타내는 그림은 아닙니다.')
for x,t,ls in [(65,'1. 초기화 후 시작',['Reset: 1 → 0','Start: 0 → 1 → 0']),(575,'2. 완료 기다리기',['동작 중이면 새 시작 금지','busy=0, completed=1 확인']),(1085,'3. 저장한 결과 읽기',['10, 9, 8, 6 비교','네 저장 표시: 1111'])]:f.box(x,220,450,255,t,ls,TEAL)
f.arrow([(520,345),(560,345)]);f.arrow([(1030,345),(1070,345)])
f.text(70,550,'같은 빌드의 회로 설정(.bit)과 신호 정보(.ltx)를 사용합니다.',30)
f.finish('출력 비교와 신호 시간 검사(Timing)를 함께 확인합니다. 읽기만 했으면 실행 완료로 기록하지 않습니다.')

(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'Created {len(manifest)} diagrams as editable SVG and PNG')
