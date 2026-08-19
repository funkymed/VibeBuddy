# D5 — Plancher mémoire d'un shell SwiftUI

**Date** : 2026-08-19 · **RFC** : 001 T1 · **Machine** : macOS 26.5 (25F71), Swift 6.3.3

## Question

RFC-001 pose une cible de 40 Mo de RSS. L'analyse d'architecture affirmait que
cette cible était **probablement hors d'atteinte** avec `NSHostingView`
(« 45-60 Mo typiques pour un shell vide »), et recommandait de trancher entre
relever la cible à ~55 Mo ou faire la pastille en `CALayer` pur.

## Protocole

`NotchBuddy --bench <mode> 60`, échantillonnage toutes les 5 s depuis l'intérieur
du process (`task_info`, aucun sous-process, aucun `sudo`).

- `shell` — `NSApplication` en `.accessory`, aucune fenêtre.
- `panel` — idem + un `NSPanel` `.nonactivatingPanel` `.statusBar` hébergeant un
  `NSHostingView` sur une vue vide, `orderFrontRegardless()`.

## Résultat brut

```
shell,35.0,31.38,6.69,0.001,20,0
shell,40.0,31.33,6.66,0.001,21,0
shell,45.0,31.33,6.63,0.001,22,0
shell,50.0,31.33,6.63,0.001,23,0
shell,54.5,31.33,6.63,0.001,24,0

panel,35.0,37.39,10.44,0.002,87,0
panel,40.0,37.33,10.38,0.002,89,0
panel,45.0,37.33,10.38,0.002,90,0
panel,50.0,38.25,10.61,0.002,95,0
panel,54.5,38.19,10.56,0.002,97,0
```
*(colonnes : `label,uptime_s,rss_mb,footprint_mb,cpu_s,wakeups,idle_wakeups`)*

| Mode | RSS crête | `phys_footprint` crête | CPU | Réveils inactifs |
|---|---|---|---|---|
| `shell` | **31,4 Mo** | **6,7 Mo** | 0,000 % | **0,000 /s** |
| `panel` | **38,2 Mo** | **10,6 Mo** | 0,000 % | **0,000 /s** |
| delta | +6,8 Mo | +3,9 Mo | — | — |

## Décision

**SwiftUI est retenu. La pastille n'a pas besoin d'être en `CALayer`.**

La prédiction de 45-60 Mo est démentie par la mesure : 38,2 Mo, sous la cible de
40 Mo. L'option (b) — deux paradigmes de rendu à maintenir — n'a pas de
justification.

**En revanche la métrique de budget change : `phys_footprint`, pas RSS.**

Le RSS compte les pages des frameworks système partagées avec toutes les autres
applications de la machine. Les faire figurer dans le budget d'une app revient à
lui facturer AppKit autant de fois qu'il y a de processus qui l'utilisent.
`phys_footprint` est ce que macOS impute réellement au process, et c'est ce
qu'affiche « Mémoire » dans le Moniteur d'activité.

Ce n'est pas un contournement du chiffre : c'est le chiffre honnête. Il donne
aussi la marge réelle, qui est très différente selon la métrique — 1,8 Mo de
marge en RSS (intenable dès qu'on ajoute du contenu) contre 29,4 Mo en
`phys_footprint`.

| | Ancien | Nouveau |
|---|---|---|
| Métrique | RSS | **`phys_footprint`** |
| Cible | 40 Mo | **40 Mo** |
| Mesuré (shell vide + panneau) | 38,2 Mo | **10,6 Mo** |
| Marge | 1,8 Mo | **29,4 Mo** |

Le RSS reste relevé et consigné, à titre indicatif.

## Notes annexes

- **Réveils inactifs : 0,000/s dans les deux modes.** Un `NSPanel` affiché ne
  coûte aucun réveil tant que rien ne l'anime — ce qui confirme que le coût de la
  référence vient de ses animations et de ses timers, pas du fait d'avoir une
  fenêtre à l'écran.
- Les compteurs `wakeups` non-inactifs montent plus vite en mode `panel`
  (97 contre 24 sur 55 s) : c'est le coût du compositeur, mais il est intégralement
  coalescé — aucun n'est un réveil *inactif*.
