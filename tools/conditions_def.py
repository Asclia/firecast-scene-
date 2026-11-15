# -*- coding: utf-8 -*-
"""Definição das condições/status do plugin de Condições.

Cada entrada: (id, nome PT, nome original EN, grupo, categoria, ícone game-icons)
Os nomes em português seguem a tradução brasileira de Pathfinder 1e.
Ícones: https://game-icons.net (CC BY 3.0) - ver CREDITS.md
"""

GROUPS = [
    ("pf", "Condições - Pathfinder 1e"),
    ("buff", "Magias e efeitos comuns"),
    ("ff", "Status - Final Fantasy d20"),
]

# Cores por categoria (fundo do ícone no token)
CATEGORY_COLORS = {
    "mental": "#7B1FA2",    # medo, confusão, encantamento
    "physical": "#C62828",  # dano, sangramento, náusea
    "move": "#6D4C41",      # agarrado, caído, enredado
    "senses": "#455A64",    # cego, surdo, ofuscado
    "death": "#212121",     # morrendo, morto, inconsciente
    "buff": "#2E7D32",      # benefícios
    "magic": "#1565C0",     # efeitos mágicos neutros
    "element": "#E65100",   # queimando, congelado, eletrizado
    "fate": "#4A148C",      # maldição, doom
}

CONDITIONS = [
    # ---------------- Pathfinder 1e (Core Rulebook, apêndice de condições)
    ("bleed", "Sangrando", "Bleed", "pf", "physical", "lorc/bleeding-wound"),
    ("blinded", "Cego", "Blinded", "pf", "senses", "delapouite/blindfold"),
    ("broken", "Quebrado", "Broken", "pf", "senses", "lorc/broken-shield"),
    ("confused", "Confuso", "Confused", "pf", "mental", "lorc/brainstorm"),
    ("cowering", "Encolhido", "Cowering", "pf", "mental", "lorc/despair"),
    ("dazed", "Pasmo", "Dazed", "pf", "mental", "delapouite/knocked-out-stars"),
    ("dazzled", "Ofuscado", "Dazzled", "pf", "senses", "lorc/sunbeams"),
    ("deafened", "Surdo", "Deafened", "pf", "senses", "skoll/hearing-disabled"),
    ("disabled", "Incapacitado", "Disabled", "pf", "death", "lorc/broken-bone"),
    ("dying", "Morrendo", "Dying", "pf", "death", "delapouite/half-dead"),
    ("dead", "Morto", "Dead", "pf", "death", "sbed/death-skull"),
    ("drained", "Dreno de Energia", "Energy Drained", "pf", "death", "lorc/marrow-drain"),
    ("entangled", "Enredado", "Entangled", "pf", "move", "lorc/spider-web"),
    ("fatigued", "Fatigado", "Fatigued", "pf", "physical", "delapouite/tired-eye"),
    ("exhausted", "Exausto", "Exhausted", "pf", "physical", "delapouite/kneeling"),
    ("fascinated", "Fascinado", "Fascinated", "pf", "mental", "lorc/oily-spiral"),
    ("flatfooted", "Desprevenido", "Flat-Footed", "pf", "senses", "lorc/foot-trip"),
    ("shaken", "Abalado", "Shaken", "pf", "mental", "delapouite/shaking-hands"),
    ("frightened", "Amedrontado", "Frightened", "pf", "mental", "lorc/screaming"),
    ("panicked", "Em Pânico", "Panicked", "pf", "mental", "lorc/run"),
    ("grappled", "Agarrado", "Grappled", "pf", "move", "lorc/grab"),
    ("pinned", "Imobilizado", "Pinned", "pf", "move", "delapouite/pin"),
    ("helpless", "Indefeso", "Helpless", "pf", "move", "delapouite/handcuffed"),
    ("incorporeal", "Incorpóreo", "Incorporeal", "pf", "magic", "lorc/ghost"),
    ("invisible", "Invisível", "Invisible", "pf", "magic", "delapouite/invisible"),
    ("nauseated", "Nauseado", "Nauseated", "pf", "physical", "lorc/vomiting"),
    ("sickened", "Enjoado", "Sickened", "pf", "physical", "sbed/health-decrease"),
    ("paralyzed", "Paralisado", "Paralyzed", "pf", "move", "lorc/imprisoned"),
    ("petrified", "Petrificado", "Petrified", "pf", "move", "delapouite/stone-bust"),
    ("prone", "Caído", "Prone", "pf", "move", "sbed/falling"),
    ("stable", "Estável", "Stable", "pf", "buff", "zeromancer/heart-plus"),
    ("staggered", "Vacilante", "Staggered", "pf", "physical", "delapouite/brute"),
    ("stunned", "Atordoado", "Stunned", "pf", "mental", "lorc/star-swirl"),
    ("unconscious", "Inconsciente", "Unconscious", "pf", "death", "skoll/knockout"),
    ("asleep", "Dormindo", "Asleep", "pf", "death", "lorc/sleepy"),
    ("poisoned", "Envenenado", "Poisoned", "pf", "physical", "lorc/poison-bottle"),
    ("diseased", "Doente", "Diseased", "pf", "physical", "lorc/virus"),
    ("burning", "Em Chamas", "On Fire", "pf", "element", "lorc/fluffy-flame"),
    ("charmed", "Enfeitiçado", "Charmed", "pf", "mental", "lorc/charm"),
    ("dominated", "Dominado", "Dominated", "pf", "mental", "lorc/puppet"),
    ("marked", "Marcado (alvo)", "Marked", "pf", "senses", "sbed/targeted"),
    # ---------------- Magias / efeitos comuns de PF1e
    ("haste", "Velocidade", "Haste", "buff", "buff", "lorc/sprint"),
    ("slow", "Lentidão", "Slow", "buff", "magic", "lorc/snail"),
    ("bless", "Bênção", "Bless", "buff", "buff", "lorc/holy-symbol"),
    ("bane", "Perdição", "Bane", "buff", "fate", "lorc/cursed-star"),
    ("shield", "Escudo Arcano", "Shield", "buff", "buff", "lorc/checked-shield"),
    ("magearmor", "Armadura Arcana", "Mage Armor", "buff", "buff", "lorc/magic-shield"),
    ("barkskin", "Pele de Árvore", "Barkskin", "buff", "buff", "lorc/oak"),
    ("protevil", "Proteção contra o Mal", "Prot. from Evil", "buff", "buff", "lorc/aura"),
    ("enlarged", "Aumentado", "Enlarge Person", "buff", "magic", "delapouite/growth"),
    ("reduced", "Reduzido", "Reduce Person", "buff", "magic", "lorc/magnifying-glass"),
    ("flying", "Voando", "Fly", "buff", "magic", "lorc/feathered-wing"),
    ("raging", "Em Fúria", "Rage", "buff", "physical", "delapouite/enrage"),
    ("concentrating", "Concentrando", "Concentrating", "buff", "magic", "lorc/brain"),
    ("mirrorimage", "Imagem Espelhada", "Mirror Image", "buff", "magic", "lorc/mirror-mirror"),
    ("hidden", "Escondido", "Hidden / Stealth", "buff", "senses", "lorc/hood"),
    ("heroism", "Heroísmo", "Heroism", "buff", "buff", "delapouite/upgrade"),
    ("strength", "Força do Touro", "Bull's Strength", "buff", "buff", "lorc/muscle-up"),
    ("inspired", "Inspirado (bardo)", "Inspire Courage", "buff", "buff", "lorc/lyre"),
    ("regenerating", "Cura Acelerada", "Fast Healing", "buff", "buff", "sbed/regeneration"),
    # ---------------- Final Fantasy d20 (status específicos do FFd20)
    ("ff_antagonized", "Antagonized", "Antagonized", "ff", "mental", "delapouite/human-target"),
    ("ff_berserk", "Berserk", "Berserk", "ff", "physical", "delapouite/angry-eyes"),
    ("ff_cursed", "Cursed", "Cursed", "ff", "fate", "lorc/cursed-star"),
    ("ff_dimmed", "Dimmed", "Dimmed", "ff", "senses", "lorc/eclipse"),
    ("ff_deprotect", "Deprotect", "Deprotect", "ff", "physical", "lorc/cracked-shield"),
    ("ff_deshell", "Deshell", "Deshell", "ff", "magic", "lorc/broken-shield"),
    ("ff_doom", "Doom", "Doom", "ff", "fate", "lorc/death-note"),
    ("ff_drenched", "Drenched", "Drenched", "ff", "element", "sbed/water-drop"),
    ("ff_frog", "Frog", "Frog", "ff", "magic", "lorc/frog"),
    ("ff_frozen", "Frozen", "Frozen", "ff", "element", "lorc/frozen-block"),
    ("ff_immobilize", "Immobilize", "Immobilize", "ff", "move", "lorc/manacles"),
    ("ff_imperil", "Imperil", "Imperil", "ff", "element", "lorc/target-dummy"),
    ("ff_mini", "Mini", "Mini", "ff", "magic", "lorc/magnifying-glass"),
    ("ff_sapped", "Sapped", "Sapped", "ff", "physical", "lorc/drop"),
    ("ff_silenced", "Silenced", "Silenced", "ff", "magic", "delapouite/silenced"),
    ("ff_squalled", "Squalled", "Squalled", "ff", "element", "lorc/tornado"),
    ("ff_static", "Static", "Static", "ff", "element", "sbed/electric"),
    ("ff_stop", "Stop", "Stop", "ff", "magic", "lorc/stopwatch"),
    ("ff_weighted", "Weighted", "Weighted", "ff", "move", "lorc/anchor"),
    ("ff_zombie", "Zombie", "Zombie", "ff", "death", "delapouite/shambling-zombie"),
    ("ff_float", "Float", "Float", "ff", "buff", "lorc/feather"),
    ("ff_protect", "Protect", "Protect", "ff", "buff", "lorc/checked-shield"),
    ("ff_shell", "Shell", "Shell", "ff", "buff", "lorc/magic-shield"),
    ("ff_reflect", "Reflect", "Reflect", "ff", "buff", "lorc/shield-reflect"),
    ("ff_regen", "Regen", "Regen", "ff", "buff", "sbed/regeneration"),
    ("ff_reraise", "Reraise", "Reraise", "ff", "buff", "lorc/angel-wings"),
    ("ff_haste", "Haste", "Haste", "ff", "buff", "lorc/sprint"),
    ("ff_slow", "Slow", "Slow", "ff", "magic", "lorc/snail"),
]

# Ícone usado para condições personalizadas
CUSTOM_ICON = "lorc/rune-stone"
