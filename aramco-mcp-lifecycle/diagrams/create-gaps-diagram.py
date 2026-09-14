#!/usr/bin/env python3
"""Visualize the three security/durability gaps in the Red Hat MCP stack."""

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Circle, Ellipse

fig, ax = plt.subplots(1, 1, figsize=(15, 11))
ax.set_xlim(0, 16)
ax.set_ylim(0, 12)
ax.axis('off')
fig.patch.set_facecolor('white')

WHITE='#FFFFFF'; GRAY='#666666'; TXT='#333333'
GREEN_BG='#E8F5E9'; GREEN='#4CAF50'; OK='#188038'
ORANGE_BG='#FFF3E0'; ORANGE='#FF9800'
RED='#C5221F'; RED_BG='#FDECEA'; YELLOW_BG='#FFF8E1'

def box(x,y,w,h,label,sub=None,bg=WHITE,brd=GRAY,fs=11,bold=True,lw=1.5):
    ax.add_patch(FancyBboxPatch((x,y),w,h,boxstyle="round,pad=0.1",fc=bg,ec=brd,lw=lw))
    wt='bold' if bold else 'normal'
    if sub:
        ax.text(x+w/2,y+h/2+0.2,label,ha='center',va='center',fontsize=fs,fontweight=wt,color=TXT)
        ax.text(x+w/2,y+h/2-0.24,sub,ha='center',va='center',fontsize=fs-2.5,color=GRAY)
    else:
        ax.text(x+w/2,y+h/2,label,ha='center',va='center',fontsize=fs,fontweight=wt,color=TXT)

def arrow(x1,y1,x2,y2,color=TXT,ls='-',lw=1.8,label=None,loff=(0,0),la='center'):
    ax.annotate('',xy=(x2,y2),xytext=(x1,y1),
                arrowprops=dict(arrowstyle='-|>',color=color,lw=lw,linestyle=ls))
    if label:
        ax.text((x1+x2)/2+loff[0],(y1+y2)/2+loff[1],label,fontsize=8.5,color=color,
                ha=la,fontstyle='italic')

def gap_badge(x,y,n):
    ax.add_patch(Circle((x,y),0.34,fc=RED,ec='white',lw=2,zorder=20))
    ax.text(x,y,str(n),ha='center',va='center',fontsize=13,fontweight='bold',color='white',zorder=21)

# ---- Title ----
ax.text(8,11.65,'The three gaps — all in the Red Hat MCP stack, not MemPalace',
        ha='center',fontsize=15,fontweight='bold',color=TXT)

# ================= DATA PATH (upper region, y>=4.6) =================
# Client
box(0.4,7.9,2.3,1.3,'MCP Client','AI agent',bg=WHITE,brd=GRAY,fs=11)

# Gateway container
box(3.6,5.9,5.4,4.6,'',bg=GREEN_BG,brd=GREEN,lw=2)
ax.text(3.6+2.7,10.5-0.3,'MCP Gateway  (Kuadrant / RHCL — Tech Preview)',
        ha='center',va='top',fontsize=10.5,fontweight='bold',color=TXT)
box(3.9,8.55,4.8,1.05,'Envoy edge  :8443','plain HTTP — no JWT required today',bg=RED_BG,brd=RED,fs=10)
box(3.9,6.25,2.3,1.4,'ext_proc','rewrites :authority',bg=WHITE,brd=GREEN,fs=9)
box(6.4,6.25,2.3,1.4,'broker','tools/list, discover',bg=WHITE,brd=GREEN,fs=9)

# Backend pod
box(10.0,7.9,3.2,1.6,'MemPalace pod',':8000  (in-cluster Service)',bg=GREEN_BG,brd=GREEN,fs=11)

# Storage cylinder to the RIGHT of backend
sx,sy=13.7,7.9; sw=1.5; sh=1.1
ax.add_patch(Ellipse((sx+sw/2,sy+sh),sw,0.35,fc=RED_BG,ec=RED,lw=1.8,zorder=3))
ax.add_patch(FancyBboxPatch((sx,sy),sw,sh,boxstyle="square,pad=0",fc=RED_BG,ec=RED,lw=1.8,zorder=2))
ax.add_patch(Ellipse((sx+sw/2,sy),sw,0.35,fc=RED_BG,ec=RED,lw=1.8,zorder=2))
ax.text(sx+sw/2,sy+sh*0.62,'EmptyDir',ha='center',va='center',fontsize=9.5,fontweight='bold',color=TXT)
ax.text(sx+sw/2,sy+sh*0.22,'ephemeral',ha='center',va='center',fontsize=8,color=RED)

# Rogue pod BELOW backend
box(10.0,5.35,3.2,1.05,'Any in-cluster pod','no NetworkPolicy in place',bg=YELLOW_BG,brd=ORANGE,fs=9.5)

# ---- Path arrows ----
arrow(2.7,8.55,3.6,8.55)                                   # client -> gateway
arrow(9.0,8.7,10.0,8.7,label='tools/call',loff=(0,0.28))   # gateway -> backend
arrow(13.2,8.5,13.7,8.5,color=GRAY,lw=1.4,label='mounts',loff=(0,0.28)) # backend -> storage
arrow(11.6,6.4,11.6,7.9,color=RED,ls=(0,(4,3)),lw=2.2)     # rogue -> backend (bypass)
ax.text(11.95,7.15,'bypasses\ngateway + auth',fontsize=8.5,color=RED,ha='left',va='center',fontstyle='italic')

# ---- Gap badges ----
gap_badge(3.9,9.07,1)     # left border of Envoy edge box
gap_badge(10.15,6.4,2)    # top-left of rogue pod
gap_badge(13.75,8.95,3)   # top-left of storage

# ---- "good news" note between path and table ----
ax.text(8,4.05,
        'The gateway design itself is sound: once AuthPolicy is applied, ext_proc runs BEFORE Authorino, so tools/call is NOT bypassed at the edge. '
        'Gaps 1–2 are "not yet configured," not design flaws.',
        fontsize=9,color=GRAY,fontstyle='italic',ha='center')

# ================= CLASSIFICATION TABLE (lower region, y 0.3..3.6) =================
tx,ty,tw,th=0.4,0.3,15.2,3.3
ax.add_patch(FancyBboxPatch((tx,ty),tw,th,boxstyle="round,pad=0.05",fc='#FAFAFA',ec='#DDDDDD',lw=1))
cols=[0.7,4.3,8.4,11.4]
for cx,htxt in zip(cols,['Gap','Where it lives (layer)','Stack-level?','Fix']):
    ax.text(cx,ty+th-0.35,htxt,fontsize=10,fontweight='bold',color=TXT)
ax.plot([tx+0.2,tx+tw-0.2],[ty+th-0.55,ty+th-0.55],color='#DDDDDD',lw=1)

rows=[
 ('1','OIDC auth not deployed\nat the gateway edge','MCP Gateway (Kuadrant)',
  'YES — every\nfederated server','Apply Kuadrant AuthPolicy\n(OIDC via Keycloak / RHBK)'),
 ('2','Backend reachable directly,\nskipping the gateway','Any in-cluster backend',
  'YES — every backend','Add NetworkPolicy: only the\ngateway ns may reach :8000'),
 ('3','No durable storage —\ndata lost on pod restart','MCPServer CRD (no PVC type)',
  'YES limitation;\nseverity ∝ statefulness','StatefulSet + PVC outside the\noperator  +  upstream FR'),
]
row_y=[ty+th-1.25, ty+th-2.05, ty+th-2.85]
for (n,gap,layer,stack,fix),ry in zip(rows,row_y):
    ax.add_patch(Circle((cols[0]+0.02,ry),0.23,fc=RED,ec='white',lw=1.5))
    ax.text(cols[0]+0.02,ry,n,ha='center',va='center',fontsize=10,fontweight='bold',color='white')
    ax.text(cols[0]+0.42,ry,gap,fontsize=8.7,color=TXT,va='center')
    ax.text(cols[1],ry,layer,fontsize=8.7,color=TXT,va='center')
    ax.text(cols[2],ry,stack,fontsize=8.7,color=RED,va='center',fontweight='bold')
    ax.text(cols[3],ry,fix,fontsize=8.7,color=OK,va='center')

plt.tight_layout(pad=0.4)
plt.savefig('/tmp/blog-format/mcp_gaps.png',dpi=190,bbox_inches='tight',facecolor='white')
import os
print(f"saved: {os.path.getsize('/tmp/blog-format/mcp_gaps.png')} bytes")
