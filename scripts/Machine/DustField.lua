-- Port of the verified ambient ParticleSystem settings, level0:5372.
-- Unity's internal noise seed/solver is unavailable: use a continuous 2D
-- Perlin curl field (the documented NoiseModule mechanism), not sine motion.
---@type any
local Dust={};Dust.__index=Dust
local colors={{.858,.717,.737},{.802,.798,.586},{.588,.717,.551},{.646,.830,.815},{.708,.673,.887}}
local function fade(t) return t*t*t*(t*(t*6-15)+10) end
local function mix(a,b,t) return a+(b-a)*t end
local function grad(x,y,dx,dy)
    local h=((x*374761393+y*668265263)~(x*1274126177))&7
    if h<4 then return (h&1==0 and dx or -dx)+(h&2==0 and dy or -dy) end
    return h<6 and (h==4 and dx or -dx) or (h==6 and dy or -dy)
end
local function noise(x,y)
    local ix,iy=math.floor(x),math.floor(y);local dx,dy=x-ix,y-iy
    return mix(mix(grad(ix,iy,dx,dy),grad(ix+1,iy,dx-1,dy),fade(dx)),
        mix(grad(ix,iy+1,dx,dy-1),grad(ix+1,iy+1,dx-1,dy-1),fade(dx)),fade(dy))
end
function Dust.New(scene,cookieTexture)
    local self=setmetatable({particles={},seed=43013,time=0},Dust)
    local node=scene:CreateChild("AmbientDust_LitBillboards")
    self.node=node
    -- Runtime SurfaceShader BILLBOARD variation omits a_normal (verified shader
    -- compiler error). Supply the same camera-facing quads and normals explicitly.
    local set=node:CreateComponent("CustomGeometry")
    set.dynamic=true
    set.castShadows=false
    local material=Material:new()
    assert(material:SetSurfaceShader("Shaders/BLGL/LayeredDust.shader"))
    assert(material:SetSurfaceTexture("cookie_map",cookieTexture))
    set.material=material;self.set=set;self.material=material
    self.normal=Vector3(0,0,-1)
    self.uvs={Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)}
    self.quad={}
    for i=1,6 do self.quad[i]=Vector3.ZERO end
    for i=1,500 do self:Spawn(i,(i-1)/50) end
    self:Tick(0)
    return self
end
function Dust:Random()
    self.seed=(self.seed*48271)%2147483647
    return self.seed/2147483647
end
function Dust:Spawn(i,age)
    local stationary=i%4==0
    local p={x=(self:Random()-.5)*20,y=(self:Random()-.5)*20,
        z=-.6-self:Random()*1.5,age=age,speed=.05+self:Random()*.45,
        seed=self:Random()*200,color=colors[1+math.floor(self:Random()*#colors)],
        stationary=stationary,lifetime=10,size=.035}
    if stationary then
        -- 四分之一为原地显隐的微尘；不新增粒子、材质或玩法随机数。
        p.x=(self:Random()-.5)*4.4;p.y=(self:Random()-.5)*9
        p.lifetime=6+self:Random()*3;p.age=age%p.lifetime
        p.size=.025+self:Random()*.015
    end
    self.particles[i]=p
end
function Dust:Tick(dt,cookieTime)
    self.time=self.time+dt
    -- 粒子可暂停，光纹始终接续机台的绝对时间。
    self.material:SetShaderParameter("cookie_time",Variant(cookieTime or self.time))
    self.set:BeginGeometry(0,TRIANGLE_LIST)
    for i,p in ipairs(self.particles) do
        p.age=p.age+dt
        if p.age>=p.lifetime then self:Spawn(i,p.age%p.lifetime);p=self.particles[i] end
        if not p.stationary then
            local x,y=p.x*.15+p.seed,p.y*.15+self.time*.5
            local dx=(noise(x,y+.01)-noise(x,y-.01))/.02
            local dy=-(noise(x+.01,y)-noise(x-.01,y))/.02
            p.x=p.x+(-p.speed+dx*.15)*dt;p.y=p.y+dy*.15*dt
        end
        local life=p.age/p.lifetime
        local alpha=math.min(1,life/.21765,(1-life)/.21471)
        if p.stationary then
            local envelope=math.max(0,math.min(1,life/.30,(1-life)/.35))
            alpha=envelope*envelope*(3-2*envelope)*.65
        end
        if math.abs(p.x)<2.3 and math.abs(p.y)<4.7 then
            local color=Color(p.color[1],p.color[2],p.color[3],math.max(0,alpha))
            for j,uv in ipairs(self.uvs) do
                local vertex=self.quad[j]
                vertex.x,vertex.y,vertex.z=p.x+(uv.x-.5)*p.size,p.y+(uv.y-.5)*p.size,p.z
                self.set:DefineVertex(vertex)
                self.set:DefineNormal(self.normal)
                self.set:DefineColor(color)
                self.set:DefineTexCoord(uv)
            end
        end
    end
    self.set:Commit()
end
return Dust
