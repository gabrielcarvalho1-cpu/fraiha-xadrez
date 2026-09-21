class_name FraihaRank
extends RefCounted

const LEAGUES := ["MADEIRA","FERRO","BRONZE","PRATA","OURO","PLATINA","ESMERALDA","DIAMANTE","MESTRE","GRANDE MESTRE","CHALLENGER"]
var rank_index := 0
var league_points := 0
var wins := 0
var losses := 0
var matches_played := 0

func league_name() -> String:
    return LEAGUES[clampi(rank_index,0,LEAGUES.size()-1)]

func progress_text() -> String:
    return "%s  •  %d / 100 PL" % [league_name(),league_points]

func set_progress(new_rank: int, points: int):
    rank_index=clampi(new_rank,0,LEAGUES.size()-1)
    league_points=clampi(points,0,100)
