--!strict
local Math={}
function Math.sample(time: number,progress: number,step: number,phase: number): any
    local emphasis=math.clamp(progress,0,1)
    local trace=(time*.12)%1
    local heat=math.max(0,1-math.abs(trace-step)*5)
    local reveal=math.clamp((emphasis-step)/.18,0,1)
    return {heatAlpha=math.clamp(.94-heat*.20-reveal*.52,0,1),
        coreAlpha=.85-(math.sin(time*.85)+1)*.035-emphasis*.08,
        emberAlpha=1-math.max(0,math.sin(time*.72+phase))^8*(.30+emphasis*.20),
        emberRise=((time*.055+phase*.11)%1)*.10,
        glintAlpha=1-math.max(0,math.sin(time*.46+phase))^16*.46,
        rays=time*1.6}
end
function Math.layout(width: number,height: number,phone: boolean?): any
    local small=width<430;local short=height<230;local inset=if phone then 12 else 20
    local art=if phone then 64 elseif small then math.clamp(width*.26,68,112) else math.clamp(height*.56,112,190)
    art=math.min(art,math.max(48,height-86))
    return {inset=inset,art=art,artTop=if phone then 30 else 14,
        titleY=if phone then 6 else 10,titleHeight=if phone then 26 else 34,titleSize=if phone then 20 elseif small then 24 else 28,
        bonusY=if phone then 32 else 47,profileY=if phone then 55 else 76,
        profileWidth=math.max(110,math.min(242,width-art-inset-16)),profileHeight=if short then 40 else 48,
        contentsY=if phone then 100 else height-(if short then 84 else 92),cell=if phone then 18 elseif short then 20 else 26}
end
return Math
