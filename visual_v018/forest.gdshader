shader_type canvas_item;
render_mode unshaded;
// Independent material masks keep motion outside the playable terrain.
float torch_mask(vec2 uv, vec2 center) {
    return (1.0-smoothstep(0.010,0.027,length((uv-center)*vec2(1.5,1.0))));
}
void fragment() {
    vec2 uv=UV;
    vec4 source=texture(TEXTURE,uv);
    float board=step(0.202,uv.x)*step(uv.x,0.798)*step(0.180,uv.y)*step(uv.y,0.762);
    float water=step(source.r*1.4,source.b)*step(source.g*0.95,source.b)*step(uv.x,0.29)*step(0.69,uv.y);
    vec2 motion=vec2(sin(uv.y*180.0+TIME*1.1),cos(uv.x*130.0+TIME*0.8))*0.00065*water;
    float leaves=step(source.r*1.35,source.g)*step(source.b*1.2,source.g)*(1.0-board);
    motion.x+=sin(TIME*0.55+uv.y*32.0)*0.00038*leaves;
    vec2 t1=vec2(0.164,0.042); vec2 t2=vec2(0.141,0.548);
    vec2 t3=vec2(0.873,0.416); vec2 t4=vec2(0.879,0.824);
    float flame=max(max(torch_mask(uv,t1),torch_mask(uv,t2)),max(torch_mask(uv,t3),torch_mask(uv,t4)));
    motion.x+=sin(TIME*8.0+uv.y*320.0)*0.0015*flame;
    motion.y+=sin(TIME*11.0+uv.x*260.0)*0.0014*flame;
    vec4 col=texture(TEXTURE,uv+motion);
    float glow=exp(-length(uv-t1)*75.0)+exp(-length(uv-t2)*75.0)+exp(-length(uv-t3)*75.0)+exp(-length(uv-t4)*75.0);
    col.rgb+=vec3(1.0,0.40,0.055)*glow*(0.045+0.012*sin(TIME*5.3))*(1.0-board);
    COLOR=col;
}
