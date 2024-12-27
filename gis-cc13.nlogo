;; nosi-val lo fijo para que solo un % de la prob de wlakers pueda generar POIs
;; cuando llegan a su 'poi-mark' se detienen y si t-slow N(115,10) > POI-DI (poi-di-max)
;; generan un POI nuevo
;; -> Simulaciones 1: "we-first-t" recoge 'tiempos' de encontrar EVENTOS (no POIs)
;; es una lista con listas de 5 números (tiempos o we-ticks), uno por evento encontrado.
;; -> Simulaciones 2: "poi-detection-ratio" recoge los POIs detectados por POI born;
;; es una lista de números. El cálculo se hace 'poi-visited-count' / 'we-poi-born'.
extensions [ gis table rnd ]

globals [ edges-dataset nodes-dataset e-ids we-first-t sol-length poi-born poi-die poi-detection-ratio ]

breed [ events event]
breed [ nodes node ]     ;;  agent set of nodes
breed [ walkers walker ] ;; agent set of tourists

links-own [ popularity efitness-now ] ; popularity  el num of TABLE (popularity of each Event in th
walkers-own [ speed t-slow to-node cur-link fw-path we-tfound we-interest we-num seguir we-ticks
  poi-mark poi-di-count posible-poi nosy-val poi-visited-count we-poi-decl ] ; eve-int is a LIST
;; fw-path: son los links almacenados mientras probabilisticamente busco eventos
;; eve-ids pasa a we-tfound: es un turtle-set con los eventos que voy pasando, debe ser un TABLE que guarde los ticks
;; we-interest: tb es un TABLE con el nivel de interes de cada evento
;; phero-max: maxima pheromona que puedo usar o poner 1/L|k
patches-own [ on-road? ]
events-own [  is-poi? check-cero-t ]


to setup
  clear-all-but-globals ;; don't loose datasets
  reset-ticks
  setup-map             ;; to load custom SHP GIS map
  setup-paths-graph
  setup-walkers            ;; create n tourists and locate them at random node positions
  setup-events
  setup-tables
  set we-first-t (list)
  set poi-detection-ratio ( list )
  set sol-length 0
  set poi-born 0
  set poi-die 0
  set-current-plot "Link Size"
  let h link-of-nodes
  set-plot-x-range 0 round (max h + 2.5)
  histogram h
end

to setup-map
  ask patches [ set pcolor white ]
  ; load data set
  set edges-dataset gis:load-dataset "mi_Gent_walk3/edges/edges.shp"
  ;set edges-dataset gis:load-dataset "gante_b2_bldgs/gante_b2_bldgs.shp"
  gis:set-world-envelope (gis:envelope-of edges-dataset)
  ; know what patches are road/edge or not edge
  ask patches [ set on-road? false ]
  ask patches gis:intersecting edges-dataset
     [ set on-road? true ]
  ;show gis:feature-list-of edges-dataset
  ; draw data set
  gis:set-drawing-color gray  gis:draw edges-dataset 4

  set nodes-dataset gis:load-dataset "mi_Gent_walk3/nodes/nodes.shp"
  ;let street-nodes gis:feature-list-of nodes-dataset
  ;file-open "NODES.txt"
  ;file-write street-nodes
  ;let street-edges gis:feature-list-of edges-dataset
  ;file-open "EDGES.txt"
  ;file-write street-edges
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
to setup-walkers
  set-default-shape walkers "dot"
  let max-speed 1 ; --> 0.2 * m/patch  es lo que recorre cada tick
  ; creo que es una distancia por 'tick' del sim. si tourist-speed 'on'
  if tourist-speed? [ set max-speed  (max-speed-km/h / 36) / meters-per-patch ]
  ; show max-speed ; suele ser 0.013109990863317584 Km--13 m por tick
  ; a mayor velocidad mayor distancia.
  let min-speed  max-speed * (1 - speed-variation) ;; max-speed - (max-speed * speed-variation)
  create-walkers num-walkers [
    set color red
    set size 4
    set we-num 0
    set seguir true
    set we-ticks ticks
    set posible-poi false
    set poi-mark va-geometric (1 / 2500)
    set poi-di-count 0
    set nosy-val random 5
    set poi-visited-count 0
    set we-poi-decl (count events with [ is-poi? = 1 ])
    set speed min-speed + random-float (max-speed - min-speed)
    let l one-of links   ;; AQUI ES DONDE COGE UN LINK AL AZAR.
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
  if any? events-here and seguir  [
    let events-x ([who] of events-here)
    foreach events-x [ [?] ->
      if (table:get we-tfound ?) = 0  [
        table:put we-tfound ? we-ticks
        ifelse ([ is-poi? ] of event ?) = 0 [
            set we-num (we-num + 1) ] [
            set poi-visited-count (poi-visited-count + 1) ]
        set t-slow random-normal 120 10
        ;slowdown
        set seguir false ; only new events
        if popularity-per-step > 0 [
        set fw-path no-cycles fw-path
        add-pher fw-path ? ]
        set fw-path (list ) ]
    ]
    if (we-num = num-events) [
      set color black
      clean-vars-walker ; <--Save solution of 5 events
      set sol-length ( sol-length + 1 ) ]
  ]
  if not seguir and not posible-poi [ slowdown ]
  ]
end


to slowdown
  if seguir [ set seguir false ]
  ifelse t-slow > 1 [set t-slow (t-slow * (100 - t-wait-decrease-ratio) / 100) ]
      [ set seguir true set t-slow 0 ]
end


to clean-vars-walker
  set we-ticks 0
  set we-num 0
  ;set poi-mark va-geometric (1 / 3000)
  ; en we-first-t voy almacenando los valores de tiempos [ 100 50 75 ...]
  let v ( list ) ; solo pongo eventos is-poi? false
  let l [who] of events with [ is-poi? = 0 ]
  foreach l [ [?] -> set v lput (table:get we-tfound ?) v ]
  set we-first-t lput v we-first-t
  if we-poi-decl > 0 [
    set poi-detection-ratio lput  (poi-visited-count / we-poi-decl) poi-detection-ratio ]
  set poi-visited-count 0
  set we-poi-decl (count events with [ is-poi? = 1 ])
  foreach e-ids [ [?] -> table:put we-tfound ? 0
                         table:put we-interest ? 1  ]
end

to setup-events
  set-default-shape events "flag"
  create-events num-events [
    set color black
    set size 5
    set check-cero-t 0
    let m one-of links
    move-to [end1] of m
  ]
  set e-ids [who] of events
end

to setup-tables
  ask walkers [
      set we-tfound table:make
      set we-interest table:make
      foreach e-ids [ [?] -> table:put we-tfound ? 0
                             table:put we-interest ? 1  ] ]
  ask links [
    set popularity table:make
    foreach e-ids [ [?] -> table:put popularity ? 0 ] ]
end

to manage-pois-here
  ask walkers with [ posible-poi = true ] [
    set poi-di-count (poi-di-count + 1)
    if (poi-di-count = poi-di-max) and (not any? events-here) [
      let child-who -1
      set poi-born poi-born + 1
      hatch-events 1 [
        set is-poi? 1
        set color green
        set size 5
        set check-cero-t 0
        let m [[ end2 ] of cur-link] of myself
        move-to  m
        set child-who who
      ]
      ; actualize tables, add pheromones of actual walker
      ask walkers [
        table:put we-tfound child-who 0
        table:put we-interest child-who 1
        set we-poi-decl (we-poi-decl + 1) ]
      ask links [ table:put popularity child-who 0 ]
      set e-ids lput child-who e-ids
      if popularity-per-step > 0 [
      set fw-path no-cycles fw-path
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

;----------- Boton GO---------------------------------;
to go
  ask walkers with [ seguir ] [ move-walker speed ]
  ask walkers with [ not seguir ] [ move-walker speed / 10 ]
  decay-popularity ; func de paths
  recolor-patches
  ask walkers [
    set we-ticks ( we-ticks + 1 )
    foreach e-ids [ [?] ->  if (table:get we-tfound ?) > 0 [ decay-interest ? ] ]
    if ( poi-mark = we-ticks) and (nosy-val = 2) [
      ;set posible-poi true ; to select walkers slowdown without event
      set t-slow random-normal 123 15
      set poi-mark poi-mark + va-geometric (1 / 3000)
      set posible-poi true
      set seguir false ] ; to slow
  ]
  manage-events-here
  manage-pois-here
  birth-die-pois
  ifelse sol-length < sol-length-max
  [ tick ] [ stop ]
end

to birth-die-pois
  let ret 90
  ifelse popularity-per-step = 0 [ set ret 250 ] [ set ret 90 ]
  let p 1
  foreach [who] of events with [ is-poi? = 1 ] [
    [?] -> set p sum [ table:get popularity ? ] of links
    ifelse p <= 3 [
      ask event ? [ ; cero time mark
        ifelse (check-cero-t = 0) [ set check-cero-t ticks ] [
          if (ticks - check-cero-t) > ret and not any? walkers-here with [ seguir = false ] [
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

to decay-popularity
  ask links ;with [ not any? both-ends with [ breed = walkers ]]
   [ foreach e-ids [ [?] ->
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
      ifelse v < 0.0001 [ set v 0] [
        set v (v * (100 - slow-dec-factor) / 100) ]
      table:put we-interest ? v
  ]
end

to add-pher [ input_list_of_links id ]
    ;let lon length input_list_of_links
    let lon 1
    ;; input must be a list of links, not an agentset
    foreach input_list_of_links [ [x] -> ask x [ become-more-popular lon id ] ]
end

to-report prod-val-tables [ popular inter ]
  let ans 0 ;let i 0
  foreach e-ids [ [?1] ->
    set ans (ans + (table:get inter ?1) * (table:get popular ?1)) ]
  report ans
end


;efitness-now
to put-scale [ nl inter ]
  let l count nl
  let c 0
  foreach sort-by [ [?1 ?2] -> (prod-val-tables [popularity] of ?1 inter) > (prod-val-tables [popularity] of ?2 inter) ] nl
  [ [?] ->
    if c < l [ set c (c + 1)
      ask ? [ if c = 1 [set efitness-now  2 ]
              if c = 2 [set efitness-now  0.35 ]
              if c = 3 [set efitness-now  0.1 ]
              if c > 3 [set efitness-now  0.0 ]
      ]
    ]
  ]
end

;---------------------------3. USING SPEED_CONT
to move-walker [dist] ; with method
  let dxnode distance to-node
  ifelse (dxnode > dist) [ forward dist ] [
    let nextlinks [my-links] of to-node
    ifelse (count nextlinks = 1) or seguir = false ; para se quede = link
    ; si slowdown speed to 0 no haría falta
    [ set-next-walker-link cur-link to-node ]
    [
       set nextlinks nextlinks with [self != [cur-link] of myself]
       ifelse popularity-per-step > 0 [
       let inter [we-interest] of self ; esto antes no estaba bien. Cambia tb pro-val-tables
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
  ;if x <= max-pxcor and x >= min-pxcor [ if y <= max-pycor and y >= min-pycor [
  ifelse any? n [set n one-of n] [create-nodes 1 [
    setxy x y set size 2 set n self]]
  ;]]
  report n
end
;-----------------------------------------

;to recolor-patches
;  ifelse show-popularity? [
;    let mi-range (minimum-route-popularity * 30)
;    ask links with [ color != red ] [
;      set color scale-color gray popularity (- mi-range) mi-range
;      set thickness 0.25
;    ]
;  ] [
;    ask links with [ color != red ] [
;    set color gray
;    ]
;]
; end

to recolor-patches
  ifelse show-popularity? [
    let mi-range (minimum-route-popularity * 30)
    ask links with [ color != red ] [
      let popularity-value popularity  ;; Replace with appropriate numeric extraction
      ifelse is-number? popularity-value [
        set color scale-color gray popularity-value (- mi-range) mi-range
      ]  [
        set color black  ;; Default color for invalid values
      ]
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
98
43
setup
setup setup
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
12
56
184
89
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
625
222
719
267
meters/patch
precision meters-per-patch 3
17
1
11

SLIDER
625
378
739
411
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
653
267
719
312
nodes
count nodes
17
1
11

MONITOR
653
312
720
357
links
count links
17
1
11

MONITOR
744
371
801
416
ends
count end-nodes
17
1
11

MONITOR
801
371
858
416
med
count mid-nodes
17
1
11

MONITOR
859
371
916
416
hub
count hub-nodes
17
1
11

PLOT
720
222
918
372
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
13
160
185
193
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
12
91
184
124
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
721
13
921
163
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
627
59
715
104
Num-Streets
length long-streets nodes-dataset
17
1
11

MONITOR
626
14
716
59
Total metres
precision sum long-streets nodes-dataset 2
17
1
11

MONITOR
626
106
719
151
Average lenght
precision mean long-streets nodes-dataset 2
17
1
11

SLIDER
5
241
189
274
popularity-decay-rate
popularity-decay-rate
0
25
1.0
0.5
1
%
HORIZONTAL

SLIDER
3
277
192
310
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
5
318
186
351
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
5
357
170
390
show-popularity?
show-popularity?
0
1
-1000

SWITCH
11
125
159
158
tourist-speed?
tourist-speed?
1
1
-1000

SLIDER
12
203
184
236
num-events
num-events
0
30
5.0
1
1
NIL
HORIZONTAL

SLIDER
9
395
181
428
slow-dec-factor
slow-dec-factor
0.5
30
10.0
0.5
1
NIL
HORIZONTAL

CHOOSER
638
167
840
212
method
method
"f-p-s" "gradient" "ranking"
2

SLIDER
8
432
205
465
sol-length-max
sol-length-max
50
1000
150.0
50
1
NIL
HORIZONTAL

SLIDER
212
426
422
459
t-wait-decrease-ratio
t-wait-decrease-ratio
0
20
7.0
0.25
1
%
HORIZONTAL

SLIDER
212
459
384
492
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
483
425
580
470
Number of solutions
sol-length
17
1
11

MONITOR
582
425
655
470
POIs borned
poi-born
17
1
11

MONITOR
581
468
655
513
POIs-dead
poi-die
17
1
11

MONITOR
493
469
579
514
Actual events
count events
17
1
11

MONITOR
665
436
766
481
POI det ratio %
(mean poi-detection-ratio) * 100
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
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="fps1000-2" repetitions="1000" runMetricsEveryStep="false">
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
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="move-type">
      <value value="&quot;speed_cont&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fitness-proporcionate-vs-Gradient">
      <value value="&quot;f-p-s&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="est-fps-pop-30-1" repetitions="30" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>we-first-t</metric>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="create-new-tou">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="method">
      <value value="&quot;f-p-s&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sol-length-max">
      <value value="3000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="move-type">
      <value value="&quot;speed_cont&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0.3"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="est-gradient-pop-30-1" repetitions="30" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>we-first-t</metric>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="create-new-tou">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="method">
      <value value="&quot;gradient&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sol-length-max">
      <value value="3000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="move-type">
      <value value="&quot;speed_cont&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0.3"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="est-ranking-pop-30-1" repetitions="30" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>we-first-t</metric>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="create-new-tou">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="method">
      <value value="&quot;ranking&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sol-length-max">
      <value value="3000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="move-type">
      <value value="&quot;speed_cont&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0.3"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="est-fps-pop-10-1" repetitions="10" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>we-first-t</metric>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="create-new-tou">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="method">
      <value value="&quot;f-p-s&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sol-length-max">
      <value value="3000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="move-type">
      <value value="&quot;speed_cont&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0.3"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="est-gradient-pop-10-1" repetitions="10" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>we-first-t</metric>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="create-new-tou">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="method">
      <value value="&quot;gradient&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sol-length-max">
      <value value="3000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="move-type">
      <value value="&quot;speed_cont&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0.3"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="est-ranking-pop-10-1" repetitions="10" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>we-first-t</metric>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="create-new-tou">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="method">
      <value value="&quot;ranking&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sol-length-max">
      <value value="3000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="move-type">
      <value value="&quot;speed_cont&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0.3"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="tiemposYpoiratio1" repetitions="2" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>we-first-t</metric>
    <metric>poi-detection-ratio</metric>
    <enumeratedValueSet variable="poi-di-max">
      <value value="120"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="method">
      <value value="&quot;ranking&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sol-length-max">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
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
      <value value="0.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="t-wait-decrease-ratio">
      <value value="7"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="st-rank-300solx48sims" repetitions="48" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>we-first-t</metric>
    <metric>poi-detection-ratio</metric>
    <enumeratedValueSet variable="poi-di-max">
      <value value="120"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="method">
      <value value="&quot;f-p-s&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sol-length-max">
      <value value="300"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
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
      <value value="0.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="t-wait-decrease-ratio">
      <value value="7"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="s-fps-200solx142sim" repetitions="142" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>we-first-t</metric>
    <metric>poi-detection-ratio</metric>
    <enumeratedValueSet variable="poi-di-max">
      <value value="120"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="method">
      <value value="&quot;f-p-s&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sol-length-max">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
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
      <value value="0.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="t-wait-decrease-ratio">
      <value value="7"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="s-fps-200solx24sim" repetitions="24" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count turtles</metric>
    <enumeratedValueSet variable="poi-di-max">
      <value value="120"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-events">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="slow-dec-factor">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="show-popularity?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-decay-rate">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="method">
      <value value="&quot;f-p-s&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-walkers">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sol-length-max">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="node-precision">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="popularity-per-step">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-speed?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minimum-route-popularity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-speed-km/h">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-variation">
      <value value="0.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="t-wait-decrease-ratio">
      <value value="7"/>
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
