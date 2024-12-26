;; nosi-val lo fijo para que solo un % de la prob de wlakers pueda generar POIs
;; cuando llegan a su 'poi-mark' se detienen y si t-slow N(115,10) > POI-DI (poi-di-max)
;; generan un POI nuevo
;; -> Simulaciones 1: "visits-per-event" recoge las visitas recividas por cada EVENTO
;;    (no POI). Es una lista que, cuando el evento muere, guarda las visitas recibidas
;; -> Simulaciones 2: "poi-detection-ratio" recoge los POIs detectados por POI born;
;; es una lista de números. El cálculo se hace 'poi-visited-count' / 'we-poi-decl'.
extensions [ gis table rnd ]

globals [ edges-dataset nodes-dataset building-dataset e-ids we-first-t visits-per-event ev-died
  poi-born poi-die poi-detection-ratio ]

breed [ events event]
breed [ nodes node ]     ;;  agent set of nodes
breed [ walkers walker ] ;; agent set of tourists

links-own [ popularity efitness-now ] ; popularity  el num of TABLE (popularity of each Event in th
walkers-own [ speed t-slow to-node cur-link fw-path we-tfound we-interest we-num seguir we-ttot vuelta
  we-ticks poi-mark poi-di-count posible-poi nosy-val poi-visited-count we-poi-decl ] ; eve-int is a LIST
;; fw-path: son los links almacenados mientras probabilisticamente busco eventos
;; eve-ids pasa a we-tfound: es un turtle-set con los eventos que voy pasando, debe ser un TABLE que guarde los ticks
;; we-interest: tb es un TABLE con el nivel de interes de cada evento
;; phero-max: maxima pheromona que puedo usar o poner 1/L|k
patches-own [ on-road? ]
events-own [ lifetime who-visit is-poi? check-cero-t ]


to setup
  clear-all-but-globals ;; don't loose datasets
  reset-ticks
  set visits-per-event (list)
  set ev-died 0
  setup-map             ;; to load custom SHP GIS map
  setup-paths-graph
  ;start-profiler
  setup-walkers num-walkers           ;; create n tourists and locate them at random node positions
  setup-events num-events
  setup-tables
  set poi-born 0
  set poi-die 0
  set poi-detection-ratio ( list )
  set-current-plot "Link Size"
  let h link-of-nodes
  set-plot-x-range 0 round (max h + 2.5)
  histogram h
end

to setup-map
  ask patches [ set pcolor white ]
  ; load data set
  set edges-dataset gis:load-dataset "mi_Gent_walk3/edges/edges.shp"
  gis:set-world-envelope (gis:envelope-of edges-dataset)

  ;set building-dataset gis:load-dataset "gante_b2_bldgs/gante_b2_bldgs.shp"
  ;set edges-dataset gis:load-dataset "gante-graph/edges/edges.shp"
  ;gis:set-world-envelope (gis:envelope-union-of (gis:envelope-of edges-dataset)
                                                ; (gis:envelope-of building-dataset))
  ; know what patches are road/edge or not edge
  ask patches [ set on-road? false ]
  ask patches gis:intersecting edges-dataset
     [ set on-road? true ]
  ;show gis:feature-list-of edges-dataset
  ; draw data set
  gis:set-drawing-color gray  gis:draw edges-dataset 4

 ; set nodes-dataset gis:load-dataset "mi_Gent_walk3/nodes/nodes.shp"
; let street-nodes gis:feature-list-of nodes-dataset
;  file-open "NODES.txt"
;  file-write street-nodes
;  let street-edges gis:feature-list-of edges-dataset
;  file-open "EDGES.txt"
;  file-write street-edges
end


to-report long-streets [ dataset ]
  let dim-street []
  foreach gis:feature-list-of edges-dataset [ [?1] ->
    set dim-street lput ( read-from-string gis:property-value ?1 "LENGTH" ) dim-street
  ]
  report dim-street
end

to-report meters-per-patch ;; maybe should be in gis: extension?
  let world gis:world-envelope ; [ minimum-x maximum-x minimum-y maximum-y ]
  let x-meters-per-patch (item 1 world - item 0 world) / (max-pxcor - min-pxcor)
  let y-meters-per-patch (item 3 world - item 2 world) / (max-pycor - min-pycor)
  report mean list x-meters-per-patch y-meters-per-patch
end

to-report link-of-nodes
  report  map [ [i] -> i * ( meters-per-patch ) ]  [ link-length ] of links
end

to-report va-geometric [ p ]
  report floor ((log random-float 1 2) / log ( 1 - p ) 2)
end

; --- Hasta Aqui el SETUP. Desde AQUI ----[1]
to setup-walkers [ num-w ]
  set-default-shape walkers "dot"
  let max-speed 1 ; --> 0.2 * m/patch  es lo que recorre cada tick
  ; creo que es una distancia por 'tick' del sim. si tourist-speed 'on'
  if tourist-speed? [ set max-speed  (max-speed-km/h / 36) / meters-per-patch ]
  ; show max-speed ; suele ser 0.013109990863317584 Km--13 m por tick
  ; a mayor velocidad mayor distancia.
  let min-speed  max-speed * (1 - speed-variation) ;; max-speed - (max-speed * speed-variation)
  create-walkers num-w [
    set color red
    set size 4
    set we-num 0
    set vuelta 1
    set seguir true
    set we-ticks ticks
    set posible-poi false
    set poi-mark va-geometric (1 / 2500)
    set poi-di-count 0
    set nosy-val random 4
    set poi-visited-count 0
    set we-poi-decl (count events with [ is-poi? = 1 ])
    set speed min-speed + random-float (max-speed - min-speed)
    let l one-of links
    set fw-path ( list )
    set-next-walker-link l [end1] of l
  ]
end

to set-next-walker-link [l n] ;; boat proc
  set cur-link l
  set fw-path lput cur-link fw-path ; adding new link in the list
  move-to n
  ifelse n = [end1] of l [set to-node [end2] of l] [set to-node [end1] of l]
  face to-node
end

to manage-events-here
  ask walkers [
    let e-aqui events-here
    if any? e-aqui and seguir [
      let events-x ([who] of e-aqui )
      foreach events-x [ [?] ->
        if (table:get we-tfound ?) = -1 [
          table:put we-tfound ? ticks
          ifelse ([ is-poi? ] of event ?) = 0 [ set we-num (we-num + 1) ] [
            set poi-visited-count (poi-visited-count + 1) ]
          set t-slow random-normal 120 15
          set seguir false
          if popularity-per-step > 0 [
            set fw-path no-cycles fw-path
            add-pher fw-path ? ]
        ]
      ]
    set fw-path (list )
    count-event-visits e-aqui ; procedure
    ]
    if not seguir and not posible-poi [ slowdown ]
  ]
  new-clean-we-tables ; to get poi-detection-ratio
  ; si no no sería necesario
end

to slowdown
  if seguir [ set seguir false ]
  ifelse t-slow > 1 [set t-slow (t-slow * (100 - t-wait-decrease-ratio) / 100) ]
      [ set seguir true set t-slow 0 ]
end

to count-event-visits [ eve-aqui ]
    ask eve-aqui with [ is-poi? = 0 ] [
      let tourist-x ( [who] of walkers-here )
      foreach tourist-x [ [?] ->
          ifelse not (table:has-key? who-visit ?) [
                table:put who-visit ? 1 ] [
                let visits table:get who-visit ?
                table:put who-visit ? (visits + 1 ) ]
      ]
  ]
end

to new-clean-we-tables
  ask walkers with [ we-num = num-events and vuelta > 0 ] [
    if we-poi-decl > 0 [
      set poi-detection-ratio lput  (poi-visited-count / we-poi-decl) poi-detection-ratio ]
    set poi-visited-count 0
    set we-poi-decl (count events with [ is-poi? = 1 ])
    set we-num 0
    set poi-mark va-geometric (1 / 3000) ; ---> ?
    set we-ticks 0 ; ---> ?
    let ids table:keys we-interest
    table:clear we-tfound
    table:clear we-interest
    foreach ids [ [?] -> table:put we-tfound ? -1
                             table:put we-interest ? 1  ] ]
end

to setup-events [ n-events ]
  set-default-shape events "flag"
  create-events n-events [
    set color 122
    set size 5
    set lifetime round random-exponential exp-media
    set who-visit table:make
    set check-cero-t 0
    let m one-of links
    move-to [end1] of m
  ]
  set e-ids (list)
  set e-ids [who] of events
end

to setup-tables
  ask walkers [
      set we-tfound table:make
      set we-interest table:make
      foreach e-ids [ [?] -> table:put we-tfound ? -1
                             table:put we-interest ? 1  ] ]
  ask links [
    set popularity table:make
    foreach e-ids [ [?] -> table:put popularity ? 0 ] ]
end

to borraen-tables [ l-eventos ]
  ask walkers [
    foreach l-eventos [ [?] ->  table:remove we-interest ?
    ;set e-ids remove ? e-ids
    ] ]
      ;table:put we-interest ? 0 ]]
  ask links [
    foreach l-eventos [ [?] -> table:remove popularity ? ] ]

end

to adden-tables
  ; coger keys e e-ids y anadir los nuevos a las tablas
ask walkers [
  foreach e-ids [ [?] -> if not (table:has-key? we-interest ?) [
                table:put we-tfound ? -1
                table:put we-interest ? 1 ] ] ]
  ask links [
    foreach e-ids [ [?] -> if not (table:has-key? popularity ?) [
                table:put popularity ? 0 ] ] ] ; commonly 0 but we 0.2 to provoque sight discovery
end

to manage-pois-here
  ask walkers with [ posible-poi = true ] [
    set poi-di-count (poi-di-count + 1)
    if (poi-di-count = poi-di-max) and (not any? events-here) [
      let child-who -1
      set poi-born poi-born + 1
      hatch-events 1 [
        set size 5
        set is-poi? 1
        set color green
        set check-cero-t 0
        let m [[ end2 ] of cur-link] of myself
        move-to  m
        set child-who who
      ]
      ;set we-poi-decl (we-poi-decl + 1)
      ; actualize tables, add pheromones of actual walker
      ask walkers [
        set we-poi-decl (we-poi-decl + 1)
        table:put we-tfound child-who -1
        table:put we-interest child-who 1 ]
      ask links [ table:put popularity child-who 0 ]
      set e-ids lput child-who e-ids
      if popularity-per-step > 0 [ set fw-path no-cycles fw-path
        add-pher fw-path child-who ]
      set fw-path (list )
    ]
    ifelse t-slow > 1 [ set t-slow (t-slow - 1) ] [
      set seguir true
      set poi-di-count 0
      set posible-poi false
      set t-slow 0 ]
  ]
end

;----- Boton GO------;
to go
  ask walkers with [ seguir ] [ move-walker speed ]
  ask walkers with [ not seguir ] [ move-walker speed / 10 ]
  decay-popularity ; func de paths
  ask walkers [
    set we-ticks ( we-ticks + 1 )
    foreach e-ids [ [?] ->  if (table:get we-tfound ?) > -1 and (table:has-key? we-interest ? )
      [ decay-interest ? ] ]
    if ( poi-mark = we-ticks) and (nosy-val = 2) [
      ;set posible-poi true ; to select walkers slowdown without event
      set t-slow random-normal 120 15
      ;set poi-mark poi-mark + va-geometric (1 / 3000)
      set posible-poi true
      set seguir false ] ; to slow
  ]
  ;born-die-events
  manage-events-here
  manage-pois-here
  birth-die-pois
  ifelse ( ev-died < sim-end ) [
    born-die-events
    tick  ] [ stop ]
end

to birth-die-pois
  let ret 90
  ifelse popularity-per-step = 0 [ set ret 250 ] [ set ret 90 ]
  let p 1
  foreach [who] of events with [ is-poi? = 1 ] [
    [?] -> set p sum [ table:get popularity ? ] of links
    ;show p
    ifelse p <= 3 [
      ask event ? [ ; cero time mark
        ifelse (check-cero-t = 0) [ set check-cero-t ticks ] [
          if (ticks - check-cero-t) > ret [;and not any? walkers-here with [ seguir = false ][
            set poi-die poi-die + 1
            die
            update-variables ? ] ]
  ] ]
    [ ask event ? [ set check-cero-t 0 ] ]
  ]
end

to update-variables [ id-num ]
  ask walkers [
    table:remove we-interest id-num
    table:remove we-tfound id-num  ]
  ask links [ table:remove popularity id-num ]
  set e-ids remove id-num e-ids
end

to born-die-events
  let l (list)
  ask events with [ is-poi? = 0 ] [
    ifelse lifetime < 0.0001 [
      set lifetime 0
      set l [who] of events with [ (lifetime = 0) and (is-poi? = 0) ]
      borraen-tables l
      foreach l [ [?] -> ask event ? [ let tot-tur table:length who-visit
                                       set ev-died ev-died + 1
                                       set visits-per-event (lput tot-tur visits-per-event )
                                        die ]]
    ] [ set lifetime (lifetime * (100 - slow-dec-factor-e) / 100) ]
  ]
  let arrivals random-poisson lambda-rate
  if arrivals > 0 [ setup-events arrivals
                    adden-tables ]
  set e-ids [ who ] of events
end

to decay-popularity
  ask links ;with [ not any? both-ends with [ breed = walkers ]]
   [ foreach (table:keys popularity) [ [?] ->
      let v table:get popularity ?
      ifelse v > 0.001 [set v (v * (100 - popularity-decay-rate) / 100) ]
      [ if v <= 0.001 [set v 0] ]
      table:put popularity ? v
      if v < 1 [ set color gray ]
    ]
  ]
end

to become-more-popular [ lon id ]
  let v table:get popularity id
  set v (v + popularity-per-step * lon)
  table:put popularity id v
  set color red
end

to decay-interest [ evs-found ]
  let evs  (list evs-found)
  foreach evs [ [?] ->
      let v table:get we-interest ?
      ifelse v < 0.000001 [ set v 0] [
        set v (v * (100 - slow-dec-factor) / 100) ]
      table:put we-interest ? v
  ]
end

to add-pher [ input_list_of_links id ]
    ;let lon length input_list_of_links
    let lon 1
  ;;; input must be a list of links, not an agentset
    foreach input_list_of_links [
    [x] -> ask x [ become-more-popular lon id ]
    ]
end


to-report prod-val-tables [ popular inter ]
  let ans 0 ;let i 0
  foreach e-ids [ [?1] ->
    set ans (ans + (table:get inter ?1) * (table:get popular ?1)) ]
  report ans
end

;efitness-now
to put-scale [ nl kk ]
  let l count nl
  let c 0
  foreach sort-by [ [?1 ?2] -> (prod-val-tables [popularity] of ?1 kk) > (prod-val-tables [popularity] of ?2 kk) ] nl
  [ [?] ->
    if c < l [ set c (c + 1)
      ;ask ? [ set efitness-now max (list 0 (1 - c * c * c * c / 100)) ]
      ask ? [ if c = 1 [set efitness-now  2 ]
              if c = 2 [set efitness-now  0.35 ]
              if c = 3 [set efitness-now  0.1 ]
              if c > 3 [set efitness-now  0 ]
      ]
    ]
  ]
end

;---------------------------3. USING SPEED_CONT
to move-walker [dist] ; with method
  let dxnode distance to-node
  ifelse (dxnode > dist) [ forward dist ] [
    let nextlinks [my-links] of to-node
    ifelse (count nextlinks = 1) or seguir = false
    [ set-next-walker-link cur-link to-node ]
    [
       set nextlinks nextlinks with [self != [cur-link] of myself]
       ifelse popularity-per-step > 0 [
       let inter [we-interest] of self
       if ( method = "ranking" )
         [ put-scale nextlinks inter
           set-next-walker-link rnd:weighted-one-of nextlinks [ efitness-now ] to-node
         ]
       if ( method = "f-p-s" )
          [ set-next-walker-link rnd:weighted-one-of nextlinks [ (prod-val-tables popularity inter) ] to-node ]
       if ( method = "gradient" )
          [ set-next-walker-link max-one-of nextlinks [ (prod-val-tables popularity inter) ] to-node ]
    ] [ set-next-walker-link one-of nextlinks to-node ]
    ]
    move-walker dist - dxnode ; this moves from he next node ahead
  ]
end


to clear-all-but-globals reset-ticks ct cp cd clear-links clear-all-plots clear-output end

to-report mid-nodes report nodes with [count link-neighbors = 2] end
to-report end-nodes report nodes with [count link-neighbors = 1] end
to-report hub-nodes report nodes with [count link-neighbors > 2] end


; Create links for THIRD METHOD : speed_cont
;-----------------------------------------
to setup-paths-graph
  set-default-shape nodes "dot"
  foreach polylines-of edges-dataset node-precision [ [?1] ->
    (foreach butlast ?1 butfirst ?1 [ [??1 ??2] -> if ??1 != ??2 [ ;; skip nodes on top of each other due to rounding
      let n1 new-node-at first ??1 last ??1
      let n2 new-node-at first ??2 last ??2
      ask n1 [create-link-with n2]
      ;ask link ([who] of n1) ([who] of n2) [ set popularity table:make ]
    ] ])
  ]
  ask nodes [ hide-turtle
 set color black ]
end

to-report polylines-of [dataset decimalplaces]
  let polylines gis:feature-list-of dataset                              ;; start with a features list
  set polylines map [ [?1] -> first ?1 ] map [ [?1] -> gis:vertex-lists-of ?1 ] polylines      ;; convert to virtex lists
  set polylines map [ [?1] -> map [ [??1] -> gis:location-of ??1 ] ?1 ] polylines                ;; convert to netlogo float coords.
  set polylines remove [] map [ [?1] -> remove [] ?1 ] polylines                    ;; remove empty poly-sets .. not visible
  set polylines map [ [?1] -> map [ [??1] -> map [ [???1] -> precision ???1 decimalplaces ] ??1 ] ?1 ] polylines        ;; round to decimalplaces
    ;; note: probably should break polylines with empty coord pairs in the middle of the polyline
  report polylines ;; Note: polylines with a few off-world points simply skip them.
end

to-report new-node-at [x y] ; returns a node at x,y creating one if there isn't one there.
  let n nodes with [xcor = x and ycor = y]
  ifelse any? n [set n one-of n] [create-nodes 1 [setxy x y set size 2 set n self]]
  report n
end
;-----------------------------------------

to recolor-patches
  ifelse show-popularity? [
    let mi-range (minimum-route-popularity * 30)
    ask links with [ color != red ] [
      set color scale-color gray popularity (- mi-range) mi-range
      set thickness 0.25
    ]
  ] [
    ask links with [ color != red ] [
    set color gray
    ]
]
 end

to-report no-cycles [ input_list ]
  ifelse empty? input_list [
    report input_list
  ]
  [
    let final_list []
    let temp_list reverse input_list
    let n 0

    while [ n < length temp_list] [
      let x n
      let cur item n temp_list
      while [ x < length temp_list ] [
        if (item x temp_list) = cur  [
          set n x
        ]
        set x x + 1
      ]
      set final_list fput (item n temp_list) final_list
      set n n + 1
    ]
    report final_list
  ]

end

;----------------SOURCES----------------------------;
; http://stackoverflow.com/questions/26929504/how-to-create-moving-turtles-out-of-a-shapefile-in-netlogo
; http://netlogo-users.18673.x6.nabble.com/gis-extension-raster-vs-vector-data-td4865284.html
; The cars randomly choose side streets as they see them, choosing to turn roughly 1/3 of the
; time in the move-forward procedure.
; It chooses its next location by seeing if it should turn
; as just described, or by choosing a forward direction in a set of increasing angles of
; forward cones. NOTE: See mail lists for newer way to do this via a reporter returning
; agent-sets within a cone of given degree. It will have considerably better performance.



;--------------------------USING 2. PATCHES
to move-forward  ; turtle proc
  let n 0 let p 0 let l 0 ;locals [n p l]
  set n neighbors with [on-road?]
  ifelse count n = 0 [go-home ; normally do not happend 'never'
  ] [; miro alternativas de giro y la pongo en 'l'
    set l []
    ask patch-left-and-ahead  90 1 [if on-road? [set l lput self l]]
    ask patch-right-and-ahead 90 1 [if on-road? [set l lput self l]]
    ;; l [] except when raises a bifurcation
    ;; 90: a veces parece salta por un angulo entre calles
    ;; toss a dice [0..3] and if '0' select one of branches in 'l' at random
    if (length l != 0) and (0 = random 3) [ set p one-of l ] ;random-one-of
    ;; cuando '0 = random 3' decido torcer a uno de los 'l's
    ;; cuendo va recto: l [] y p 0
    ;; p = 0 -> no he decidido torcer o no hay bifurcaciones: sigo pa lante
    if p = 0      [ set p one-of n with [(heading-angle myself) = 0] ] ;keep heading
    ;; when reach a corner p = nobody
    ;; to turn first watch in a cone of 45º and if no patch on-road widen the angle to 90º
    ;; p = nobody -> no he decidido torcer pero tengo que hacerlo por llegar a corner
    if p = nobody [ set p one-of n with [(heading-angle myself) <= 45] ] ;random-one-of
    if p = nobody [ set p one-of n with [(heading-angle myself) <= 90] ] ;random-one-of
    ;; go back when reaching a deadend
    if p = nobody [ set p min-one-of n [heading-angle myself] ]
    set heading towards p
    forward distance p
    ;-----
    ; let p link-with [ max popularity-s l ]
  ]
end
to-report heading-angle [t] ; patch proc
  let h 0;locals [h]
  ;set h abs (heading-of t - (towards t + 180) mod 360)
  set h (towards t + 180 - [heading] of t) mod 360
  if h > 180 [set h 360 - h]
  report h
end
to go-home ; agent proc
  set pcolor white
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
622
423
-1
-1
4.0
1
10
1
1
1
0
1
1
1
-50
50
-50
50
1
1
1
ticks
30.0

BUTTON
13
10
79
43
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
101
10
164
43
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
10
104
182
137
num-walkers
num-walkers
0
300
100.0
1
1
NIL
HORIZONTAL

MONITOR
310
486
404
531
meters/patch
precision meters-per-patch 3
17
1
11

SLIDER
310
642
424
675
node-precision
node-precision
0
8
4.0
1
1
NIL
HORIZONTAL

MONITOR
338
531
404
576
nodes
count nodes
17
1
11

MONITOR
338
576
405
621
links
count links
17
1
11

MONITOR
429
635
486
680
ends
count end-nodes
17
1
11

MONITOR
486
635
543
680
med
count mid-nodes
17
1
11

MONITOR
544
635
601
680
hub
count hub-nodes
17
1
11

PLOT
405
486
603
636
Link Size
Link Length (m)
Link Count
0.0
10.0
0.0
10.0
true
false
";histogram hh" ""
PENS
"default" 5.0 1 -16777216 true "" ""

SLIDER
11
208
183
241
speed-variation
speed-variation
0
1
0.3
0.1
1
NIL
HORIZONTAL

SLIDER
10
139
182
172
max-speed-km/h
max-speed-km/h
0
10
5.0
0.5
1
NIL
HORIZONTAL

PLOT
105
482
305
632
Streets Length Distribution
Street Length (m)
Street Count
0.0
10.0
0.0
10.0
true
false
" let dim long-streets nodes-dataset\n set-plot-x-range 0 round (max dim + 2.5)\n histogram dim" ""
PENS
"default" 5.0 1 -16777216 true "" ""

MONITOR
11
528
99
573
Num-Streets
length long-streets nodes-dataset
17
1
11

MONITOR
10
483
100
528
Total metres
precision sum long-streets nodes-dataset 2
17
1
11

MONITOR
10
575
103
620
Average lenght
precision mean long-streets nodes-dataset 2
17
1
11

SLIDER
3
289
187
322
popularity-decay-rate
popularity-decay-rate
0
50
2.0
0.1
1
%
HORIZONTAL

SLIDER
1
325
190
358
popularity-per-step
popularity-per-step
0
10
1.0
0.25
1
NIL
HORIZONTAL

SLIDER
3
366
184
399
minimum-route-popularity
minimum-route-popularity
0
100
1.0
1
1
NIL
HORIZONTAL

SWITCH
3
405
168
438
show-popularity?
show-popularity?
1
1
-1000

SWITCH
9
173
157
206
tourist-speed?
tourist-speed?
1
1
-1000

SLIDER
10
251
182
284
num-events
num-events
0
30
7.0
1
1
NIL
HORIZONTAL

SLIDER
7
443
179
476
slow-dec-factor
slow-dec-factor
0.5
50
15.0
0.5
1
%
HORIZONTAL

SLIDER
798
10
1001
43
sim-end
sim-end
25
400
300.0
25
1
uds
HORIZONTAL

SLIDER
627
10
799
43
exp-media
exp-media
10
600
425.0
1
1
NIL
HORIZONTAL

SLIDER
801
48
988
81
lambda-rate
lambda-rate
0
0.025
0.005
0.001
1
ev/tick
HORIZONTAL

PLOT
631
89
995
213
number of events
time
n events
0.0
10.0
0.0
10.0
true
true
"" "if ticks > 400                               \n[\n  ; scroll the range of the plot so\n  ; only the last 200 ticks are visible\n  set-plot-x-range (ticks - 400) ticks                                       \n]"
PENS
"num events" 1.0 0 -12186836 true "" "plot count events ; with [ alive? = true ]"
"num walkers actv" 1.0 0 -5298144 false "" ";plot count walkers with [ seguir = true ]"

PLOT
628
230
1009
448
probs
#turists
frequency
0.0
20.0
0.0
0.75
true
true
"" "if ticks > 0 and not empty? visits-per-event[\nset-plot-x-range 0  max ( list ( round 1.5 * ceiling ( mean  visits-per-event ) )\n                                  ( 1 + max visits-per-event ) .1 ) ]"
PENS
"5 evnt" 1.0 0 -10022847 true "" "plot-pen-reset\n  ifelse bars? [ set-plot-pen-mode 1 ] [ set-plot-pen-mode 0 ]\n  if not empty? visits-per-event [\n  ; histogram (map [[?] -> ? / ev-died] visits-per-event )\n  histogram visits-per-event\n  ]"

SWITCH
630
213
733
246
bars?
bars?
0
1
-1000

SLIDER
630
49
799
82
slow-dec-factor-e
slow-dec-factor-e
0
10
1.0
0.5
1
%
HORIZONTAL

MONITOR
911
122
978
167
#events
count events
0
1
11

MONITOR
939
285
1011
330
m-events
mean visits-per-event
2
1
11

CHOOSER
279
426
521
471
method
method
"gradient" "f-p-s" "ranking"
1

MONITOR
926
175
995
220
#ev-died
ev-died
0
1
11

SLIDER
634
471
844
504
t-wait-decrease-ratio
t-wait-decrease-ratio
0
20
15.0
0.25
1
%
HORIZONTAL

SLIDER
638
519
810
552
poi-di-max
poi-di-max
1
250
120.0
1
1
s
HORIZONTAL

MONITOR
886
450
987
495
POI det ratio %
(mean poi-detection-ratio) * 100
2
1
11

MONITOR
846
495
912
540
poi born
poi-born
2
1
11

MONITOR
917
494
974
539
poi die
poi-die
2
1
11

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="t1event" repetitions="2" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>we-first-t</metric>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="5.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="move-type">
      <value value="&quot;speed_cont&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="t1event200" repetitions="200" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>we-first-t</metric>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="5.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="move-type">
      <value value="&quot;speed_cont&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment" repetitions="2" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>visits-per-event</metric>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exp-media">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="19"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor-e">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="lambda-rate">
      <value value="0.015"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="bars?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sim-end">
      <value value="210000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="move-type">
      <value value="&quot;speed_cont&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="sinPop-0015" repetitions="8" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>visits-per-event</metric>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exp-media">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="18"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor-e">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="bars?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="lambda-rate">
      <value value="0.015"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sim-end">
      <value value="3500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="move-type">
      <value value="&quot;speed_cont&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="sinPop-0004" repetitions="8" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>visits-per-event</metric>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exp-media">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="18"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor-e">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="bars?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="lambda-rate">
      <value value="0.004"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sim-end">
      <value value="3500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="move-type">
      <value value="&quot;speed_cont&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="din-fps-300e-died" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>visits-per-event</metric>
    <metric>poi-detection-ratio</metric>
    <enumeratedValueSet variable="poi-di-max">
      <value value="120"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exp-media">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="18"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="method">
      <value value="&quot;f-p-s&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor-e">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="lambda-rate">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="bars?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sim-end">
      <value value="300"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="t-wait-decrease-ratio">
      <value value="10"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
