extends RefCounted
## Decorative geometry shares the board transform; never changes the 8x8 grid.
static func draw_frame(canvas: CanvasItem, origin: Vector2, side: float, theme: String, accent: Color):
    var frame = Rect2(origin-Vector2(18,18),Vector2.ONE*(side+36))
    canvas.draw_rect(frame,Color("101821"))
    canvas.draw_rect(frame,accent.darkened(0.5),false,8)
    canvas.draw_rect(frame.grow(-5),accent,false,2)
    canvas.draw_rect(frame.grow(-12),accent.darkened(0.25),false,2)
    var corners = [frame.position,Vector2(frame.end.x,frame.position.y),frame.end,Vector2(frame.position.x,frame.end.y)]
    for point in corners:
        if theme in ["esmeralda","diamante","challenger"]:
            var radius = 13.0 if theme == "challenger" else 10.0
            var gem = PackedVector2Array([point+Vector2(0,-radius),point+Vector2(radius,0),point+Vector2(0,radius),point+Vector2(-radius,0)])
            canvas.draw_colored_polygon(gem,accent)
            canvas.draw_line(point+Vector2(0,-radius),point+Vector2(0,radius),Color.WHITE,1)
        else:
            canvas.draw_rect(Rect2(point-Vector2(9,9),Vector2(18,18)),accent)
            canvas.draw_rect(Rect2(point-Vector2(5,5),Vector2(10,10)),accent.darkened(0.65))
    for i in range(8):
        var offset = (i+0.5)*side/8.0
        for point in [origin+Vector2(offset,-12),origin+Vector2(offset,side+12)]:
            if theme == "mestre":
                canvas.draw_line(point-Vector2(5,3),point+Vector2(0,2),accent,2)
                canvas.draw_line(point+Vector2(0,2),point+Vector2(5,-3),accent,2)
            elif theme == "grande_mestre":
                canvas.draw_polyline(PackedVector2Array([point+Vector2(-5,3),point+Vector2(-5,-3),point,point+Vector2(0,-5),point+Vector2(5,-3),point+Vector2(5,3)]),accent,2)
            elif theme == "esmeralda":
                canvas.draw_circle(point,3,accent)
            elif theme == "challenger":
                canvas.draw_line(point-Vector2(5,0),point+Vector2(5,0),accent,2)
                canvas.draw_line(point-Vector2(0,5),point+Vector2(0,5),accent,2)
            else:
                canvas.draw_rect(Rect2(point-Vector2(3,2),Vector2(6,4)),accent)
