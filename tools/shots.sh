#!/bin/sh
# Screenshots of every screen (needs a display or xvfb-run). Usage: GODOT=path/to/godot tools/shots.sh out_dir
G=${GODOT:-godot}; O=${1:-shots}; mkdir -p "$O"
run() { xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path . --rendering-driver opengl3 --resolution 1280x720 -- "$@"; }
for s in title characters stages clauses options awards credits; do run --screen=$s --shot="$O/menu_$s.png"; done
for st in bosque_de_la_cabana pueblo_polvoriento estacion_orbital_zeta ciudad_noir templo_de_la_selva broadway_en_llamas metropolis_kaiju autocine_abandonado instituto_de_medianoche galeon_maldito mansion_victoriana laboratorio_del_doctor_loco archivo_de_cine_mudo coliseo_de_peplum carretera_del_fin dojo_de_la_montana expreso_de_medianoche plato_de_telenovela; do
  run --demo --stage=$st --skip=600 --shot="$O/run_$st.png" --wait=2
done
run --demo --skip=240 --panel=levelup --shot="$O/panel_levelup.png"
run --demo --skip=240 --panel=pause --shot="$O/panel_pause.png"
run --demo --skip=240 --panel=results --shot="$O/panel_results.png"
