"""Builds data/*.json from the design catalogue (tools/data/catalogo.txt, exported from the Claude Doc).
Run: python3 tools/data/build_data.py   (from the project root)."""
import json, re, os, unicodedata
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
L = open(os.path.join(ROOT, 'tools/data/catalogo.txt'), encoding='utf-8').read().split('\n')

def slug(s):
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().lower()
    return re.sub(r'[^a-z0-9]+', '_', s).strip('_')

def table(header_start, stop_when=None):
    """Rows (lists of cells) of the table whose header line starts with header_start."""
    i = next(k for k, l in enumerate(L) if l.startswith(header_start))
    rows = []
    for l in L[i+1:]:
        if ' | ' not in l: break
        rows.append([c.strip() for c in l.split(' | ')])
    return rows

def pct(text):
    m = re.search(r'([+−-])\s*([\d,]+)\s*%', text)
    return (float(m.group(2).replace(',', '.')) / 100) * (-1 if m.group(1) in '−-' else 1) if m else None

def num(text):
    m = re.search(r'([+−-])\s*([\d,]+)', text)
    return float(m.group(2).replace(',', '.')) * (-1 if m.group(1) in '−-' else 1) if m else None

out = {}
# ---------------- passives (stat effects per level)
PASSIVE_STAT = {
 'Ego de Estrella':('power','pct'), 'Chaleco de Especialista':('armor','num'), 'Batido de Proteínas':('max_hp','pct'), 'Mantequilla':('regen','num'),
 'Café Solo':('cooldown','pct'), 'Lente Gran Angular':('area','pct'), 'Zapatillas de Claqué':('speed','pct'), 'Guion Anotado':('duration','pct'),
 'Copia de Seguridad':('amount','num'), 'Micrófono Inalámbrico':('magnet','pct'), 'Galleta de la Suerte':('luck','pct'), 'Contrato de Estrella':('growth','pct'),
 'Gafas de Productor':('greed','pct'), 'Mala Crítica':('curse','pct'), 'Cámara Rápida':('proj_speed','pct'), 'Doble de Cuerpo':('revival','num'),
 'Maquillaje':('lifesteal','pct'), 'Filtro Sepia':('freeze_time','pct'), 'Filtro Infrarrojo':('crit','pct'), 'Cartel de Estreno':('shield','special'),
 'Pase de Prensa':('rerolls_skips','special'), 'Gafas de Sol':('union_part','special'), 'Collar de Diva':('union_part','special'),
 'Botón Rec':('max_hp_per_level','special'), 'Botón Play':('regen_per_level','special'), 'Caja de Atrezo Maldita':('all_then_curse','special')}
passives = []
for n, name, eff, lv in table('# | Pasivo'):
    stat, kind = PASSIVE_STAT[name]
    v = pct(eff) if kind == 'pct' else num(eff) if kind == 'num' else None
    passives.append({'id': slug(name), 'name': name, 'desc': eff, 'max_level': int(lv), 'stat': stat, 'per_level': v})
out['passives'] = passives
PID = {p['name']: p['id'] for p in passives}

# ---------------- weapons: behaviour archetypes + base numbers (balance lives here, not in code)
A = {  # name: (archetype, params)
 'Claqueta': ('arc', {'damage':12,'cooldown':1.1,'area':95,'amount':1,'knockback':160}),
 'Rollo de Película': ('orbit', {'damage':8,'cooldown':0.3,'area':95,'amount':1,'duration':3.5,'pause':2.5,'speed':3.2,'size':18}),
 'Foco': ('beam', {'damage':16,'cooldown':1.3,'area':360,'amount':1,'width':10}),
 'Palomitas': ('projectile', {'mode':'radial','damage':7,'cooldown':1.9,'amount':8,'speed':420,'range':300,'size':8}),
 'Pértiga de Sonido': ('arc', {'damage':14,'cooldown':1.4,'area':150,'amount':2,'shape':'horizontal','knockback':80}),
 'Estatuilla Dorada': ('projectile', {'mode':'nearest','boomerang':True,'damage':14,'cooldown':1.6,'amount':1,'speed':380,'range':330,'pierce':99,'size':14}),
 'Cámara de Flash': ('screen', {'damage':10,'cooldown':5.5,'stun':1.0}),
 'Bobina Rota': ('zone', {'place':'under_player','damage':9,'cooldown':2.4,'area':40,'duration':6,'tick':0.5,'amount':1}),
 'Megáfono del Director': ('cone', {'damage':11,'cooldown':1.8,'area':170,'angle':0.8,'knockback':120}),
 'Revólver de Atrezo': ('projectile', {'mode':'nearest','damage':10,'cooldown':0.9,'amount':1,'speed':700,'range':520,'size':5,'burst_gap':0.08}),
 'Látigo del Explorador': ('arc', {'damage':13,'cooldown':1.2,'area':170,'amount':1,'shape':'horizontal','knockback':60}),
 'Motosierra de Atrezo': ('aura', {'damage':5,'cooldown':0.25,'area':58,'knockback':20}),
 'Pistola de Rayos': ('projectile', {'mode':'facing','damage':12,'cooldown':1.2,'amount':1,'speed':900,'range':700,'pierce':5,'size':4}),
 'Sable de Neón': ('arc', {'damage':9,'cooldown':0.7,'area':80,'amount':2,'shape':'cross'}),
 'Crucifijo de Utilería': ('projectile', {'mode':'facing','boomerang':True,'damage':12,'cooldown':1.5,'amount':1,'speed':420,'range':300,'pierce':99,'size':12,'undead_bonus':0.5}),
 'Tarta de Crema': ('projectile', {'mode':'nearest','damage':10,'cooldown':1.4,'amount':1,'speed':360,'range':400,'splash':60,'size':12}),
 'Piel de Plátano': ('zone', {'place':'random_near','damage':4,'cooldown':2.0,'area':34,'duration':8,'tick':0.6,'amount':2,'slow':0.6}),
 'Yunque de Dibujos': ('zone', {'place':'nearest_enemy','damage':28,'cooldown':2.2,'area':55,'duration':0.25,'tick':1,'amount':1,'delay':0.5}),
 'Dinamita de Mecha': ('zone', {'place':'random_near','damage':26,'cooldown':2.6,'area':80,'duration':0.25,'tick':1,'amount':1,'delay':1.2}),
 'Lazo del Vaquero': ('cone', {'damage':6,'cooldown':2.2,'area':220,'angle':0.35,'pull':260}),
 'Máquina de Humo': ('aura', {'damage':3,'cooldown':0.5,'area':90,'slow':0.15}),
 'Rayo de Efectos Especiales': ('zone', {'place':'random_enemy','damage':18,'cooldown':1.6,'area':30,'duration':0.2,'tick':1,'amount':2}),
 'Ventilador Gigante': ('cone', {'damage':3,'cooldown':1.0,'area':200,'angle':0.6,'knockback':340}),
 'Sangre Falsa': ('zone', {'place':'random_near','damage':5,'cooldown':2.2,'area':50,'duration':4,'tick':0.5,'amount':1}),
 'Tijeras de Montaje': ('projectile', {'mode':'facing','damage':9,'cooldown':0.55,'amount':1,'speed':650,'range':480,'pierce':1,'size':8}),
 'Guion Volador': ('projectile', {'mode':'homing','damage':11,'cooldown':1.5,'amount':1,'speed':330,'range':800,'size':9}),
 'Confeti de Estreno': ('projectile', {'mode':'random','damage':6,'cooldown':0.6,'amount':2,'speed':450,'range':380,'size':5}),
 'Proyector Portátil': ('cone', {'damage':4,'cooldown':0.3,'area':190,'angle':0.45,'rotate':1.6}),
 'Grúa de Cámara': ('arc', {'damage':30,'cooldown':2.6,'area':130,'amount':1,'shape':'slam','knockback':200}),
 'Celuloide en Llamas': ('zone', {'place':'trail','damage':4,'cooldown':0.35,'area':26,'duration':2.5,'tick':0.5,'amount':1}),
 'Dron de Rodaje': ('companion', {'damage':8,'cooldown':0.9,'amount':1,'speed':600,'range':450,'size':5}),
 'Nunchakus de Goma': ('aura', {'damage':8,'cooldown':0.45,'area':70,'knockback':140}),
 'Coche de Persecución': ('car', {'damage':30,'cooldown':4.0,'amount':1,'speed':900,'size':40}),
 'Paraguas de Musical': ('orbit', {'damage':5,'cooldown':0.3,'area':60,'amount':1,'duration':99,'pause':0,'speed':2.4,'size':22,'block':True}),
 'Bastón de Claqué': ('aura', {'damage':9,'cooldown':1.2,'area':110,'pulse':True}),
 'Ovación del Público': ('aura', {'damage':7,'cooldown':1.6,'area':80,'pulse':True,'grow_on_kill':0.002}),
 'Cabello Maldito': ('arc', {'damage':12,'cooldown':1.3,'area':200,'amount':1,'shape':'horizontal','slow':0.3}),
 'Talismán de Papel': ('orbit', {'damage':7,'cooldown':0.3,'area':110,'amount':2,'duration':4,'pause':2,'speed':2.6,'size':14,'stun':0.4}),
 'Cinta de Vídeo Maldita': ('mark', {'damage':60,'cooldown':2.5,'amount':2,'delay':7}),
 'Dardos Tranquilizantes': ('projectile', {'mode':'nearest','damage':6,'cooldown':0.9,'amount':2,'speed':600,'range':500,'size':5,'stun':0.8}),
 'Rayo de Tormenta': ('beam', {'damage':14,'cooldown':1.5,'area':420,'amount':1,'width':16,'direction':'facing'}),
 'Taladro de Perforación': ('projectile', {'mode':'facing','damage':10,'cooldown':1.8,'amount':1,'speed':300,'range':600,'pierce':99,'size':16}),
 'Granadas': ('zone', {'place':'nearest_enemy','damage':22,'cooldown':2.0,'area':70,'duration':0.25,'tick':1,'amount':1,'delay':0.8}),
 'Rifle de Mira': ('projectile', {'mode':'nearest','damage':45,'cooldown':2.4,'amount':1,'speed':1400,'range':900,'pierce':3,'size':4}),
 'Llamada de Artillería': ('zone', {'place':'random_enemy','damage':30,'cooldown':3.0,'area':90,'duration':0.25,'tick':1,'amount':2,'delay':1.5}),
 'Hacha Doble': ('arc', {'damage':16,'cooldown':1.6,'area':100,'amount':1,'shape':'spin','knockback':120}),
 'Arco Largo': ('projectile', {'mode':'nearest','damage':12,'cooldown':1.0,'amount':1,'speed':800,'range':650,'pierce':3,'size':5}),
 'Báculo del Peregrino': ('aura', {'damage':4,'cooldown':0.6,'area':100,'knockback':220}),
 'Bola de Arcilla': ('projectile', {'mode':'nearest','damage':12,'cooldown':1.6,'amount':1,'speed':380,'range':900,'bounce':4,'size':12}),
 'Agujas de Costura': ('projectile', {'mode':'random','damage':7,'cooldown':0.7,'amount':3,'speed':700,'range':400,'pierce':2,'size':4,'stun':0.3}),
 'Calabaza': ('projectile', {'mode':'nearest','damage':14,'cooldown':2.0,'amount':1,'speed':300,'range':300,'splash':70,'size':14,'shards':6}),
 'Murciélagos': ('projectile', {'mode':'homing','damage':5,'cooldown':1.0,'amount':3,'speed':380,'range':700,'size':6}),
 'Ballesta de Estacas': ('projectile', {'mode':'facing','damage':15,'cooldown':1.3,'amount':1,'speed':850,'range':700,'pierce':4,'size':6,'undead_bonus':0.5}),
 'Copa de Vino': ('aura', {'damage':4,'cooldown':0.6,'area':85,'lifesteal':0.15}),
}
# level-up table per archetype: what each level 2..8 adds (generic, like the genre)
UP = {
 'arc':       [{'damage':4},{'amount':1},{'area':0.1},{'damage':4},{'amount':1},{'area':0.1},{'damage':6}],
 'orbit':     [{'amount':1},{'area':0.15},{'damage':4},{'amount':1},{'duration':0.5},{'amount':1},{'damage':6}],
 'projectile':[{'amount':1},{'damage':4},{'cooldown':-0.1},{'amount':1},{'damage':5},{'pierce':1},{'amount':1}],
 'beam':      [{'amount':1},{'damage':5},{'cooldown':-0.1},{'amount':1},{'damage':6},{'area':0.15},{'damage':8}],
 'screen':    [{'damage':5},{'cooldown':-0.1},{'stun':0.3},{'damage':6},{'cooldown':-0.1},{'stun':0.3},{'damage':10}],
 'zone':      [{'amount':1},{'damage':4},{'area':0.15},{'amount':1},{'duration':0.2},{'damage':5},{'amount':1}],
 'cone':      [{'damage':3},{'area':0.15},{'cooldown':-0.1},{'damage':4},{'area':0.15},{'cooldown':-0.1},{'damage':6}],
 'aura':      [{'damage':2},{'area':0.15},{'cooldown':-0.08},{'damage':3},{'area':0.15},{'cooldown':-0.08},{'damage':4}],
 'companion': [{'damage':3},{'amount':1},{'cooldown':-0.1},{'damage':4},{'amount':1},{'cooldown':-0.1},{'damage':6}],
 'car':       [{'damage':10},{'amount':1},{'cooldown':-0.1},{'damage':10},{'amount':1},{'size':0.2},{'damage':15}],
 'mark':      [{'amount':1},{'damage':20},{'cooldown':-0.1},{'amount':1},{'damage':25},{'amount':1},{'damage':40}],
}
# evolution flags: what the "montaje final" adds on top of a strong numeric boost
EVO_FLAGS = {
 'Toma Final':{'heal_on_kill':1,'area':2.5,'damage':1.6}, 'Cine Circular':{'duration_inf':True,'amount_add':2}, 'Alfombra Roja':{'chain':4,'cooldown':0.5},
 'Cubo XXL':{'slow':0.4,'splash':50}, 'Sonido Envolvente':{'shape':'spin','magnet_pulse':True}, 'Premio a Toda una Carrera':{'mode':'rain','amount_add':4},
 'Exposición Total':{'freeze':3.0,'damage':2.0}, 'Bobina del Destino':{'multiply':True,'amount_add':2}, '¡Corten y Acción!':{'echo':True,'damage':1.5},
 'Duelo al Amanecer':{'burst':6,'crit':1.0}, 'Látigo del Ídolo de Oro':{'lifesteal':0.08,'damage':1.5}, 'Motor Sin Fin':{'area':2.0,'fear':True},
 'Desintegrador':{'pierce':999,'execute':0.15}, 'Sable del Maestro':{'reflect':True,'amount_add':2}, 'Reliquia Sagrada del Plató':{'execute_undead':0.3},
 'Guerra de Tartas':{'chain':3,'greed_on_hit':1}, 'Resbalón Infinito':{'topple':True,'amount_add':3}, 'Piano de Cola':{'area':3.0,'damage':2.0},
 'Barril de Pólvora Animado':{'chain':5,'amount_add':2}, 'Rodeo Imparable':{'pull':2.0,'damage':2.0}, 'Niebla del Terror':{'area':2.2,'slow':0.3},
 'Tormenta de Pantalla Verde':{'cooldown':0.4,'amount_add':3}, 'Huracán de Plató':{'tornado':True,'damage':2.0}, 'Baño de Serie B':{'follow':True,'area':1.6},
 'Corte Final':{'cooldown':0.15}, 'Guion Ganador':{'amount_add':4}, 'Fuegos del Estreno':{'splash':70,'damage':1.6}, 'Sesión Doble':{'double':True,'duration_inf':True},
 'Plano Cenital':{'area':2.5,'damage':1.5}, 'Incendio del Nitrato':{'spread':True,'duration':2.0}, 'Escuadrón de Drones':{'amount_add':3},
 'Puño de las Mil Palmas':{'cooldown':0.4,'knockback':2.0}, 'Persecución Sin Frenos':{'amount_add':3,'splash':90}, 'Tormenta Musical':{'block_all':True,'area':1.8},
 'Número Final':{'double':True,'move_bonus':0.5}, 'Ovación de Pie':{'grow_forever':True},
}
def evo_default(): return {'damage':1.8,'amount_add':1}
weapons, evolutions = [], []
def add_weapon(name, how, passive, evo, evo_desc, source):
    arch, p = A[name]
    wid = slug(name)
    weapons.append({'id':wid,'name':name,'desc':how,'archetype':arch,'base':p,'levels':UP[arch],'max_level':8,
                    'evolution':{'id':slug(evo),'name':evo,'desc':evo_desc,'requires':PID[passive],'mods':EVO_FLAGS.get(evo, evo_default())},'source':source})
for r in table('# | Arma'):
    add_weapon(r[1], r[2], r[3], r[4], r[5], 'base')
for fest, name, how, passive, evo in table('Festival | Arma'):
    add_weapon(name, how, passive, evo, '', 'Festival ' + fest)
out['weapons'] = weapons
WID = {w['name']: w['id'] for w in weapons}
unions = []
for name, ing, eff in table('Unión | Ingredientes'):
    parts = [x.strip() for x in ing.split('+')]
    unions.append({'id':slug(name),'name':name,'desc':eff,'weapons':[WID[x] for x in parts if x in WID],'passives':[PID[x] for x in parts if x in PID]})
out['unions'] = unions

# ---------------- clauses (permanent upgrades)
CL = {'Poder':'power','Armadura':'armor','Vida máxima':'max_hp','Recuperación':'regen','Enfriamiento':'cooldown','Área':'area','Velocidad de proyectil':'proj_speed',
      'Duración':'duration','Cantidad':'amount','Velocidad de movimiento':'speed','Atracción':'magnet','Suerte':'luck','Crecimiento':'growth','Codicia':'greed',
      'Maldición':'curse','Revivir':'revival','Rehacer':'rerolls','Saltar':'skips','Desterrar':'banishes','Encanto (más enemigos)':'charm','Enemigos inofensivos':'harmless','Sellar':'seals'}
clauses = []
for n, name, eq, eff, lv in table('# | Cláusula'):
    stat = CL[eq]
    v = pct(eff) if '%' in eff and stat not in ('charm',) else num(eff)
    if stat == 'regen': v = 0.1
    clauses.append({'id':slug(name),'name':name,'stat':stat,'desc':eff,'per_level':v,'max_level':int(lv),'base_price':[200,600,300,200,900,300,300,300,5000,300,300,600,900,200,1666,10000,500,300,500,500,1000,500][int(n)-1]})
out['clauses'] = clauses

# ---------------- characters
chars = []
def wref(text):
    for nm, i in WID.items():
        if nm.lower() in text.lower(): return i
    return None
for r in table('# | Personaje | Arquetipo'):
    chars.append({'id':slug(r[1]),'num':int(r[0]),'name':r[1],'title':r[2],'weapon':wref(r[3]),'bonus':r[4],'unlock':r[5],'group':'base'})
for r in table('# | Personaje | Qué es'):
    chars.append({'id':slug(r[1]),'num':int(r[0]),'name':r[1],'title':r[2],'weapon':wref(r[3]),'bonus':r[4],'unlock':r[5],'group':'secreto'})
n = 49
for fest, people in table('Festival | Personajes'):
    for p in people.split(' · '):
        m = re.match(r'(.+?) \((.+)\)', p); nm, rest = m.group(1), m.group(2)
        title, _, wpn = rest.rpartition(', ') if ', ' in rest else ('', '', rest)
        chars.append({'id':slug(nm),'num':n,'name':nm,'title':title,'weapon':wref(wpn),'weapon_name':wpn,'bonus':'','unlock':fest,'group':fest}); n += 1
# parse bonus text into stat mods (best effort; unknown text stays as description)
BON = {'vida máx':'max_hp','armadura':'armor','enfriamiento':'cooldown','duración':'duration','área':'area','daño a jefes':'boss_damage','suerte':'luck','vida/s':'regen',
       'velocidad de proyectil':'proj_speed','velocidad de movimiento':'speed','velocidad':'speed','vida':'max_hp','Taquilla':'greed','experiencia':'growth','atracción':'magnet','poder':'power','cantidad':'amount','revivir':'revival','crecimiento':'growth'}
for c in chars:
    mods = {}
    for part in re.split(r' y |, ', c['bonus']):
        for key, stat in BON.items():
            if key in part:
                v = pct(part) if '%' in part else num(part)
                if v is not None and stat not in mods: mods[stat] = v
                break
    c['mods'] = mods
# characters whose starting weapon is an exclusive version: use their festival's weapons in turn; secrets get 'random'
FEST_W = {}
for w in weapons:
    if w['source'].startswith('Festival '): FEST_W.setdefault(w['source'][9:], []).append(w['id'])
k = 0
for c in chars:
    if c['weapon']: continue
    fw = next((v for f, v in FEST_W.items() if f in c['group']), None)
    if fw: c['weapon'] = fw[k % len(fw)]; c['weapon_exclusive'] = True; k += 1
    else: c['weapon'] = 'random'
out['characters'] = chars

# ---------------- stages
stages = []
for r in table('# | Escenario | Género | Mecánica'):
    stages.append({'num':int(r[0]),'name':r[1],'genre':r[2],'mechanic':r[3],'enemies':r[4],'boss':r[5],'unlock':r[6],'kind':'normal'})
k = 0
for r in table('# | Escenario | Género | Mecánica'):
    pass
idx = [i for i, l in enumerate(L) if l.startswith('# | Escenario | Género | Mecánica')]
for r in [ [c.strip() for c in l.split(' | ')] for l in L[idx[1]+1:] if ' | ' in l][:7]:
    stages.append({'num':int(r[0]),'name':r[1],'genre':r[2],'mechanic':r[3],'enemies':r[4],'boss':r[5],'unlock':r[6],'kind':'bonus','minutes':20})
for r in table('# | Escenario | Género | Regla'):
    stages.append({'num':int(r[0]),'name':r[1],'genre':r[2],'mechanic':r[3],'enemies':r[4],'boss':r[5],'unlock':r[6],'kind':'desafio'})
# special stages have no boss in the catalogue; these are the ones their art was drawn for
SPECIAL_BOSS = {22: 'El Crítico Implacable', 23: 'El Director de Casting'}
for r in table('# | Escenario | Tipo'):
    stages.append({'num':int(r[0]),'name':r[1],'genre':r[2],'mechanic':r[3],'enemies':'','boss':SPECIAL_BOSS.get(int(r[0]),''),'unlock':r[4],'kind':'especial'})
for r in table('# | Escenario | Descripción'):
    stages.append({'num':int(r[0]),'name':r[1],'genre':'Oculto','mechanic':r[2],'enemies':'','boss':'El Montador','unlock':r[3],'kind':'oculto'})
for r in table('# | Escenario | Festival'):
    stages.append({'num':int(r[0]),'name':r[1],'genre':r[3],'mechanic':r[4],'enemies':'','boss':r[5],'unlock':r[2],'kind':'festival'})
for s in stages:
    s['id'] = slug(s['name']); s.setdefault('minutes', 30)
# art sets that exist today (from the web prototype); others fall back to the forest set
ART = {1:'forest',2:'west',3:'station',4:'noir',5:'jungle',6:'broadway',7:'kaiju',8:'drivein',9:'school',10:'galleon',11:'mansion',12:'lab',13:'silent',14:'colosseum',15:'wasteland',16:'dojo',17:'train',18:'telenovela',19:'toon',20:'bunker',21:'neon',22:'carpet',23:'casting',24:'montage',25:'spirit',26:'hotel',27:'dino',28:'doom',29:'beach',30:'heli',31:'dragon',32:'tower',33:'clay',34:'count'}
for s in stages: s['art'] = ART.get(s['num'], 'forest')
out['stages'] = stages

# ---------------- relics, guiones, modifiers
relics = []
for r in table('# | Reliquia'):
    if r[0] == '16–22':
        for i in range(7): relics.append({'id':'bobina_perdida_%d' % (i+1),'num':str(16+i),'name':'Bobina Perdida %d' % (i+1),'unlocks':r[2],'where':'Escenario de desafío %d' % (13+i)})
    else: relics.append({'id':slug(r[1]),'num':r[0],'name':r[1],'unlocks':r[2],'where':r[3]})
out['relics'] = relics
out['guiones'] = [{'id':'g_'+slug(r[0]),'num':r[0],'name':r[1],'desc':r[2],'cursed':False} for r in table('N.º | Guion | Efecto')] + \
                 [{'id':'gm_'+slug(r[0]),'num':r[0],'name':r[1],'desc':r[2],'how':r[3],'cursed':True} for r in table('N.º | Guion Maldito')]
out['modifiers'] = [{'id':slug(r[0]),'name':r[0],'desc':r[2],'reward':r[3],'relic':r[4]} for r in table('Modificador | Equivale')]
# Maratón needs the Director's Cut mode, not built yet: until then the Silla del Director (which opens that mode) unlocks it
for m in out['modifiers']:
    if m['id'] == 'maraton': m['relic'] = 'Silla del Director'

# ---------------- achievements ("Premios de la Academia del Juego"): one per unlock rule + general ones
SBYNUM = {s['num']: s for s in stages}
def stage_ref(t):
    m = re.search(r'\b(?:en el|el|al) (\d+)\b', t)
    if m and int(m.group(1)) in SBYNUM: return SBYNUM[int(m.group(1))]['id']
    for st in sorted(stages, key=lambda x: -len(x['name'])):
        if st['name'].lower() in t.lower(): return st['id']
    m = re.search(r'(?:Completar|Llegar a|Llegar al|Llegar a la) (?:el |la |al )?(.+)$', t)
    if m:
        for st in stages:
            if st['name'].lower().startswith(m.group(1).lower()): return st['id']
    return None
def cond(t):
    t0 = t.replace('.', '')
    if t in ('Inicial',): return {'type':'initial'}
    m = re.match(r'(?:Sobrevivir )?(\d+) min(?: en (?:el|la) .+| en el \d+)?', t0)
    if m and (' en ' in t0): return {'type':'survive','minutes':int(m.group(1)),'stage':stage_ref(t)}
    if m: return {'type':'survive','minutes':int(m.group(1)),'stage':None}
    if (m := re.match(r'Llegar a nivel (\d+)', t0)): return {'type':'level','value':int(m.group(1))}
    if re.match(r'Evolucionar (cualquier|un) arma', t0): return {'type':'evolutions','value':1}
    if (m := re.match(r'Evolucionar (\d+) armas', t0)): return {'type':'evolutions','value':int(m.group(1))}
    if (m := re.match(r'Evolucionar (?:el|la) (.+)', t)):
        w = next((x['id'] for x in weapons if x['name'].lower() == m.group(1).lower()), None)
        w = w or next((x['id'] for x in weapons if x['name'].lower().startswith(m.group(1).lower())), None)
        if w: return {'type':'evolve','weapon':w}
    if (m := re.match(r'Derrotar (\d+) enemigos', t0)): return {'type':'kills','value':int(m.group(1))}
    if (m := re.match(r'Derrotar (?:a )?(\d+) jefes', t0)): return {'type':'bosses','value':int(m.group(1))}
    if (m := re.match(r'Morir (\d+) veces', t0)): return {'type':'deaths','value':int(m.group(1))}
    if (m := re.match(r'Recoger (\d+) cofres', t0)): return {'type':'chests','value':int(m.group(1))}
    if (m := re.match(r'Recoger (\d+) monedas', t0)): return {'type':'coins','value':int(m.group(1))}
    if (m := re.match(r'Abrir (\d+) latas', t0)): return {'type':'chests','value':int(m.group(1))}
    if (m := re.match(r'Acumular (\d+) de Taquilla', t0)): return {'type':'taquilla_total','value':int(m.group(1))}
    if (m := re.match(r'Comer (\d+) donuts', t0)): return {'type':'food','value':int(m.group(1))}
    if t.startswith('Derrotarlo al minuto 31'): return {'type':'productor'}
    if (m := re.match(r'Completar (?:el |la )?(.+?)( sin .+| en modo .+)?$', t)) and stage_ref(t):
        return {'type':'complete','stage':stage_ref(t)} if not m.group(2) else {'type':'manual','text':t}
    if (m := re.match(r'(?:Llegar (?:al|a la|a)) (.+)', t)) and stage_ref(t): return {'type':'play','stage':stage_ref(t)}
    if t.startswith('Desbloquear 20 armas'): return {'type':'weapons_unlocked','value':20}
    return {'type':'manual','text':t}
# ---------------- Modo Saga rewards (not in the catalogue tables): 4 characters, a weapon and a passive
SAGA_CHARS = [
    ('la_ultima_chica', 'La Última Chica', 'La Superviviente', 'foco', '+1 revivir y +10 % velocidad', 'Completar la saga La Trilogía del Enmascarado', {'revival': 1.0, 'speed': 0.1}),
    ('el_vigilante_enmascarado', 'El Vigilante Enmascarado', 'El Héroe del Barrio', 'paraguas_de_musical', '+20 % área y +10 % poder', 'Completar la saga Liga de Héroes de Barrio', {'area': 0.2, 'power': 0.1}),
    ('el_agente_con_esmoquin', 'El Agente con Esmoquin', 'El Espía', 'dardos_tranquilizantes', '+25 % suerte y +10 % velocidad de proyectil', 'Completar la saga Agente 00-Nadie', {'luck': 0.25, 'proj_speed': 0.1}),
    ('el_director_fantasma', 'El Director Fantasma', 'El Autor', 'megafono_del_director', '+1 proyectil, +10 % poder y +10 % área', 'Completar la saga Retrospectiva del Director', {'amount': 1.0, 'power': 0.1, 'area': 0.1}),
]
for k, (cid, name, title, weapon, bonus, unlock, mods) in enumerate(SAGA_CHARS):
    chars.append({'id': cid, 'num': 97 + k, 'name': name, 'title': title, 'weapon': weapon, 'bonus': bonus, 'unlock': unlock, 'group': 'saga', 'mods': mods})
weapons.append({'id': 'espada_de_plasma', 'name': 'Espada de Plasma', 'desc': 'Un tajo de luz que barre todo a tu alrededor', 'archetype': 'arc',
    'base': {'damage': 16, 'cooldown': 1.1, 'area': 120, 'amount': 1, 'shape': 'spin'},
    'levels': [{'damage': 5}, {'area': 0.15}, {'cooldown': -0.1}, {'damage': 6}, {'amount': 1}, {'area': 0.15}, {'damage': 8}],
    'max_level': 8,
    'evolution': {'id': 'espada_del_ultimo_remake', 'name': 'Espada del Último Remake', 'desc': 'Dos tajos y lanza ondas de luz', 'requires': 'turbo', 'mods': {'amount_add': 1, 'area': 1.3, 'damage': 1.5}},
    'source': 'saga'})
passives.append({'id': 'turbo', 'name': 'Turbo', 'desc': '+8 % velocidad y −4 % enfriamiento', 'max_level': 5, 'stat': 'turbo', 'per_level': 0.08, 'saga': True})

ach = []
for c in chars:
    if c['group'] in ('base', 'secreto'):
        ach.append({'id':'unlock_' + c['id'], 'name':'Fichaje: ' + c['name'], 'desc':c['unlock'], 'cond':cond(c['unlock']), 'reward':{'character':c['id']}})
for st in stages:
    if st['kind'] != 'festival':
        ach.append({'id':'unlock_' + st['id'], 'name':'Estreno: ' + st['name'], 'desc':st['unlock'], 'cond':cond(st['unlock']), 'reward':{'stage':st['id']}})
for v in (100, 1000, 10000, 100000): ach.append({'id':'kills_%d' % v, 'name':'Figurantes caídos: %d' % v, 'desc':'Derrotar %d enemigos' % v, 'cond':{'type':'kills','value':v}, 'reward':{}})
for v in (1, 10, 30): ach.append({'id':'evo_%d' % v, 'name':'Montaje final ×%d' % v, 'desc':'Evolucionar %d armas' % v, 'cond':{'type':'evolutions','value':v}, 'reward':{}})
for w in weapons: ach.append({'id':'evolve_' + w['id'], 'name':w['evolution']['name'], 'desc':'Evolucionar ' + w['name'], 'cond':{'type':'evolve','weapon':w['id']}, 'reward':{}})
ach.append({'id':'productor', 'name':'Película cancelada', 'desc':'Derrotar al Productor Ejecutivo', 'cond':{'type':'productor'}, 'reward':{'character':'el_productor_ejecutivo'}})
out['achievements'] = ach
os.makedirs(os.path.join(ROOT, 'data'), exist_ok=True)
for k, v in out.items():
    json.dump(v, open(os.path.join(ROOT, 'data', k + '.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print({k: len(v) for k, v in out.items()})
print('chars without weapon:', [c['name'] for c in chars if not c['weapon']][:60])
