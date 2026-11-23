# Equilibrio (fase Q1)

Simulamos partidas completas con el piloto automático, sin trucos de vida. Para repetirlo:

```
tools/balance/run_all.sh /tmp/out.txt "bosque_de_la_cabana ciudad_noir" "max_rios vera_lys dolly_ray" "0 max"
python3 tools/balance/report.py /tmp/out.txt
```

`0` significa una partida sin Cláusulas compradas; `max` significa todas al máximo. Con `--trace`, `sim.tscn` imprime el estado cada dos minutos.

## El piloto automático

Antes elegía las mejoras al azar y no esquivaba disparos ni fuegos. Por eso moría hacia el minuto 5 y no medía bien el juego.

Ahora:
- Elige como un jugador sensato: sube lo que ya tiene, busca los objetos que piden sus armas para evolucionar y llena cuatro armas pronto.
- Esquiva los disparos enemigos, los fuegos y los barriles encendidos.
- Recoge entradas hasta 560 px.

Juega como un jugador bastante hábil.

## Hallazgos y cambios

| Hallazgo | Cambio |
|---|---|
| La Exposición Total (evolución de la Cámara de Flash) podía congelar la horda para siempre si su enfriamiento era menor que la congelación: no salían enemigos y la partida se quedaba parada. | Hay 8 s de juego normal entre dos congelaciones (`WeaponSystem.FREEZE_GAP`). |
| Todos los escenarios eran igual de difíciles: el tipo de escenario no contaba. | `Director.stage_k()`: los escenarios base suben un 4 % cada uno; bonus ×1,2, desafío ×1,4, Sala de Casting ×0,9, Sala de Montaje ×1,5 y festivales ×1,3. Multiplica la vida de los enemigos, y su raíz cuadrada, la cantidad de enemigos. |
| Con todas las Cláusulas, la partida acababa en el nivel 160–235. | A partir del nivel 80, cada nivel cuesta 40 de experiencia más que el anterior. Ahora se acaba en el nivel 105–175. |
| La Taquilla iba deprisa en las partidas largas, pero en las cortas casi no se ganaba nada. | Ahora se pagan 8 por minuto sobrevivido. Las monedas de los enemigos salen un tercio menos y las latas dan 20 por objeto en vez de 30. |

## Resultados (120 partidas)

| | Sin Cláusulas | Todas las Cláusulas |
|---|---|---|
| Escenarios base 1–5 | Termina 12 de 15; unos 9.500 de Taquilla | Termina 15 de 15; nivel 120–175 |
| Bonus y desafíos | Termina 10 de 15; los desafíos, 5 de 9 | Termina 15 de 15 |

Todas las Cláusulas cuestan 188.250 en total. Hacen falta unas 15–25 partidas buenas para comprarlas. Un jugador humano esquivará peor que el piloto automático, así que tardará algo más.
