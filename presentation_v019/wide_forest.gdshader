shader_type canvas_item;
render_mode unshaded;
// Independent material masks keep motion outside the playable terrain.
float torch_mask(vec2 uv, vec2 center) {
    return (1.0-smoothstep(0.010,0.027,length((uv-center)*vec2(1.5,1.0))));
}
float organic(float t) {
    float i=floor(t); float f=fract(t); f=f*f*(3.0-2.0*f);
    return mix(fract(sin(i*127.1)*43758.5453),fract(sin((i+1.0)*127.1)*43758.5453),f);
}
void fragment() {
    vec2 uv=UV;
    vec4 source=texture(TEXTURE,uv);
    float board=step(0.312,uv.x)*step(uv.x,0.648)*step(0.180,uv.y)*step(uv.y,0.765);
    float water=step(source.r*1.4,source.b)*step(source.g*0.95,source.b)*step(uv.x,0.34)*step(0.45,uv.y);
    vec2 motion=vec2(sin(uv.y*180.0+TIME*1.1),cos(uv.x*130.0+TIME*0.8))*0.00065*water;
    float leaves=step(source.r*1.35,source.g)*step(source.b*1.2,source.g)*(1.0-board);
    motion.x+=sin(TIME*0.55+uv.y*32.0)*0.00038*leaves;
    vec2 t1=vec2(0.288,0.042); vec2 t2=vec2(0.276,0.551);
    vec2 t3=vec2(0.693,0.426); vec2 t4=vec2(0.697,0.835);
    float flame=max(max(torch_mask(uv,t1),torch_mask(uv,t2)),max(torch_mask(uv,t3),torch_mask(uv,t4)));
    float luminous=smoothstep(0.72,0.98,source.r)*smoothstep(0.30,0.70,source.g)*flame;
    float drift=organic(TIME*2.3+uv.x*79.0+uv.y*23.0)-0.5;
    motion *= 1.0-flame;
    motion.x += drift*TEXTURE_PIXEL_SIZE.x*0.65*luminous;
    motion.y -= (organic(TIME*3.1+uv.x*31.0)-0.5)*TEXTURE_PIXEL_SIZE.y*0.45*luminous;
    vec4 col=texture(TEXTURE,uv+motion);
    float glow=exp(-length(uv-t1)*75.0)+exp(-length(uv-t2)*75.0)+exp(-length(uv-t3)*75.0)+exp(-length(uv-t4)*75.0);
    col.rgb+=vec3(1.0,0.40,0.055)*glow*(0.040+0.003*(organic(TIME*1.7)-0.5))*(1.0-board);
    COLOR=col;
}
