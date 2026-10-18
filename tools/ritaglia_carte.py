import os,glob,json
from PIL import Image
import numpy as np
Image.MAX_IMAGE_PIXELS=None
src='/mnt/user-data/uploads/Rebellion/carte italiano'
out='/home/claude/work/crops'
def runs(prof,thr,minlen):
    on=prof>thr; segs=[];s=None
    for i,v in enumerate(on):
        if v and s is None: s=i
        if not v and s is not None:
            if i-s>=minlen: segs.append((s,i))
            s=None
    if s is not None and len(on)-s>=minlen: segs.append((s,len(on)))
    return segs
res={}
for f in sorted(glob.glob(src+'/*.png')):
    im=Image.open(f).convert('RGB')
    a=np.asarray(im).astype(np.int16)
    m=(a.min(axis=2)<200)
    rows=runs(m.mean(axis=1),0.03,200)
    boxes=[]
    for (y0,y1) in rows:
        cols=runs(m[y0:y1].mean(axis=0),0.03,200)
        for (x0,x1) in cols:
            # refine vertical within column
            sub=m[y0:y1,x0:x1]
            r2=runs(sub.mean(axis=1),0.05,200)
            for (a0,a1) in r2:
                boxes.append((x0,y0+a0,x1,y0+a1))
    base=os.path.basename(f)[:-4].strip()
    names=[]
    for k,b in enumerate(boxes):
        nm='%s_%02d.png'%(base.replace(' ','_'),k)
        im.crop(b).save(os.path.join(out,nm)); names.append((nm,(b[2]-b[0],b[3]-b[1])))
    res[base]=names
    print(base,len(boxes),[s for _,s in names])
json.dump(res,open('crops.json','w'),indent=1)
