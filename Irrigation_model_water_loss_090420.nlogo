; 1 unit of water = 1 million liters

extensions [ gis ]

globals [
  ; convert variables for sliders
  lastRainySeasonRain
  rainySeasonRain
  drySeasonRain
  rainySeasonRainSD
  drySeasonRainSD
  numberOfFarms
  canalSize

  ; make water sources
  canalLevel
  aquiferLevel
  reservoirLevel

  ; establish pecking order
  peckingOrder

  ; check season
  currentSeason

  ; set rain and water loss from evapotranspiration etc.
  rain
  waterLoss

  ; set water demand and yield
  proportionWaterSavings
  proportionYieldIncrease

  ; extract water
  rainWaterExtracted
  canalWaterExtracted
  groundWaterExtracted

  ; calculate averages
  aquiferLevelSum
  averageAquiferLevel
  averageFarmerWaterDeficit
  averageFarmerWaterDeficitSum
  averageWaterDeficit
  averageFarmerCrops
  averageFarmerCropsSum
  averageCrops
]

patches-own [
  ; setup gis
  insideBorder?

  ; make farms
  isFarm?

  ; set water demand and yield
  useMicroIrrigation?
  waterDemand
  yield

  ; make it rain
  farmWater

  ; extract canal water
  canalAccess?

  ; calculate switch probability
  farmWaterDeficit

  ; grow-crops
  crops
]

turtles-own [
  ; count friends
  friendCount
  friendMicroIrrigationCount

  ; calculate switch probability
  probabilitySocial
  probabilityEnvironment
  probabilitySwitch
]

to setup
  clear-all
  convert-variables-for-sliders
  setup-gis
  make-farms
  setup-network
  count-friends
  give-farmers-microirrigation
  make-aquifer
  make-reservoir
  establish-peckingOrder
  reset-ticks
end

to go
  reset-waterExtraction
  check-season
  set-rain-and-waterLoss
  fill-canal
  set-water-demand-and-yield
  make-it-rain
  extract-canalWater
  extract-groundWater
  count-friends-with-microirrigation
  calculate-farm-water-deficit
  calculate-switch-probability
  farmers-switch-to-microirrigation
  grow-crops
  lose-canal-water
  calculate-averages
  tick
end

to convert-variables-for-sliders
  set rainySeasonRain rainySeasonPrecipitation / 100
  set drySeasonRain drySeasonPrecipitation / 100
  set rainySeasonRainSD rainySeasonPrecipitationSD / 100
  set drySeasonRainSD drySeasonPrecipitationSD / 100
  set lastRainySeasonRain rainySeasonRain
  set numberOfFarms culturableCommandArea
  set canalSize canalToReservoirSize * reservoirSize
end

to setup-gis
  let basin-dataset gis:load-dataset "Data/chambal.shp"
  let rivers-dataset gis:load-dataset "Data/named_rivers_chambal.shp"
  gis:set-world-envelope  (gis:envelope-union-of (gis:envelope-of basin-dataset)
                                                 (gis:envelope-of rivers-dataset))
  gis:set-drawing-color white
  gis:draw basin-dataset 2.0
  gis:set-drawing-color blue
  gis:draw rivers-dataset 2.0
  ask patches gis:intersecting basin-dataset [
    set insideBorder? true
  ]
end

to make-farms
  ask n-of numberOfFarms patches with [ insideBorder? = true ] [
    set pcolor green
    set isFarm? true
    set useMicroIrrigation? false
  ]
  ask n-of actualIrrigationArea patches with [ isFarm? = true ] [
    set canalAccess? true
  ]
end

to setup-network
  set-default-shape turtles "person"
  ;; make the initial network of two turtles and an edge
  make-node nobody        ;; first node, unattached
  make-node turtle 0      ;; second node, attached to first node

  while [ count patches with [ isFarm? = true and count turtles-here = 0 ] > 0 ] [
    make-node find-partner
  ]
end

to make-node [old-node]
  ask one-of patches with [ isFarm? = true and count turtles-here = 0 ] [
    sprout 1 [
      set hidden? true
      if old-node != nobody [
        create-link-with old-node [ set hidden? true ]
      ]
    ]
  ]
end

to-report find-partner
  report [one-of both-ends] of one-of links
end

to count-friends
  ask turtles [
    set friendCount count link-neighbors
  ]
end

to give-farmers-microirrigation
  ifelse sociallyAlignedInvestment [
    ask max-n-of round ( proportionMicroIrrigation * numberOfFarms ) turtles [ friendCount ] [
      set useMicroIrrigation? true
      set pcolor 15
    ]
  ] [
    ask n-of round ( proportionMicroIrrigation * numberOfFarms ) turtles [
      set useMicroIrrigation? true
      set pcolor 15
    ]
  ]
end

to make-aquifer
  set aquiferLevel initialAquiferLevel
end

to make-reservoir
  set reservoirLevel initialReservoirLevel
end

to establish-peckingOrder
  set peckingOrder sort patches with [ isFarm? = true ]
end

to reset-waterExtraction
  set rainWaterExtracted 0
  set canalWaterExtracted 0
  set groundWaterExtracted 0
end

to check-season
  ifelse ( ( ticks + 1 ) mod 2 > 0 ) [
    set currentSeason "drySeason"
  ] [
    set currentSeason "rainySeason"
  ]
end

to set-rain-and-waterLoss
  ifelse ( currentSeason = "drySeason" ) [
    set rain max list ( random-normal drySeasonRain drySeasonRainSD ) 0
    set waterLoss drySeasonWaterLoss
  ] [
    let rainySeasonRainVaried ( rainySeasonRain * ( 1 - rainySeasonVariation ) )
    let rainySeasonRainSDVaried ( rainySeasonRainSD * ( 1 + rainySeasonSDVariation ) )
    ; autoregressive model looking back 1 year (AR1)
    ; rain during the rainy season can be autogressive or more or less persistent
    ; rainySeasonAR of 0 is stationary, >0 correlated/persistent, and <0 anti-correlated/less persistent
    set rain max list ( rainySeasonAR * lastRainySeasonRain + ( 1 - rainySeasonAR ) * rainySeasonRainVaried + ( random-normal 0 rainySeasonRainSDVaried ) ) 0
    set waterLoss rainySeasonWaterLoss
    set lastRainySeasonRain rain
  ]
end

to fill-canal
  if ( currentSeason = "drySeason" ) [
    ; fill canal from reservoir by opening reservoir gate
    let canalDeficit canalSize - canalLevel
    let reservoirDispensed min list canalDeficit reservoirLevel
    set canalLevel canalLevel + reservoirDispensed
    set reservoirLevel reservoirLevel - reservoirDispensed
  ]
end

to check-micro-water-demand-and-yield
  if ( useMicroIrrigation? ) [
    set waterDemand waterDemand * ( 1 - proportionWaterSavings )
    set yield yield * ( 1 + proportionYieldIncrease )
  ]
end

to set-water-demand-and-yield
  ; water demanded depends on irrigation technology
  ask patches with [ isFarm? = true ] [
    ifelse ( currentSeason = "rainySeason" ) [
      set waterDemand rainyDemand
      set yield rainyYield
      set proportionWaterSavings proportionWaterSavingsRainy
      set proportionYieldIncrease proportionYieldIncreaseRainy
      check-micro-water-demand-and-yield
    ] [
      set waterDemand dryDemand
      set yield dryYield
      set proportionWaterSavings proportionWaterSavingsDry
      set proportionYieldIncrease proportionYieldIncreaseDry
      check-micro-water-demand-and-yield
    ]
  ]
end

to make-it-rain
  let waterFlux max list 0 ( rain - ( waterLoss * rain ) )
  ; rain falls on farms
  ask patches with [ isFarm? = true ] [
    set farmWater farmWater + max list waterFlux 0
    if ( waterFlux > 0 ) [
      set rainWaterExtracted rainWaterExtracted + min list waterDemand waterFlux
    ]
  ]
  ; rain fills reservoir
  let reservoirDeficit reservoirSize - reservoirLevel
  let reservoirIncrease 0
  if ( waterFlux > 0 ) [
    set reservoirIncrease min list reservoirDeficit ( commandArea * waterFlux )
  ]
  set reservoirLevel reservoirLevel + reservoirIncrease
  ; rain fills aquifer
  let aquiferDeficit aquiferSize - aquiferLevel
  let aquiferIncrease 0
  if ( waterFlux > 0 ) [
    set aquiferIncrease min list aquiferDeficit ( commandArea * waterFlux * rainfallInfiltration )
  ]
  set aquiferLevel aquiferLevel + aquiferIncrease
end

to extract-canalWater
  foreach peckingOrder [ the-patch ->
    ask the-patch [
      let waterDeficit max list ( waterDemand - farmWater ) 0
      if ( waterDeficit > 0 and canalAccess? = true ) [
        let waterTaken min list waterDeficit canalLevel
        set farmWater farmWater + waterTaken
        set canalWaterExtracted canalWaterExtracted + waterTaken
        set canalLevel canalLevel - waterTaken
      ]
    ]
  ]
end

to extract-groundWater
  ask patches with [ isFarm? = true ] [
    let waterDeficit max list ( waterDemand - farmWater ) 0
    if ( waterDeficit > 0 ) [
      let waterTaken min list waterDeficit aquiferLevel
      set farmWater farmWater + waterTaken
      set groundWaterExtracted groundWaterExtracted + waterTaken
      set aquiferLevel aquiferLevel - waterTaken
    ]
  ]
end

to count-friends-with-microirrigation
  ask turtles [
    set friendMicroIrrigationCount count link-neighbors with [ useMicroIrrigation? ]
  ]
end

to calculate-farm-water-deficit
  ask patches with [ isFarm? = true ] [
    set farmWaterDeficit max list ( waterDemand - farmWater ) 0
  ]
end

to calculate-switch-probability
  ask turtles [
    set probabilitySocial friendMicroIrrigationCount / friendCount
    ; exponential moving average recursion
    ; farmers remember all past years following an exponential decay in weight
    ; higher presentFocus means a greater focus on the present
    set probabilityEnvironment ( 1 - presentFocus ) * probabilityEnvironment + presentFocus * ( farmWaterDeficit / waterDemand )
    set probabilitySwitch ( socialVsEnvironmentWeight * probabilitySocial + ( 1 - socialVsEnvironmentWeight ) * probabilityEnvironment ) / 1
  ]
end

to farmers-switch-to-microirrigation
  ask turtles [
    if ( random-float adoptionSensitivity * probabilitySwitch ) < random-float 1  [
      set useMicroIrrigation? true
      set pcolor red
    ]
  ]
end

to grow-crops
  ask patches with [ isFarm? = true ] [
    let waterRatio 1
    let addedCrop 0
    if waterDemand != 0 [
      set waterRatio min list 1 ( farmWater / waterDemand )
    ]
    set addedCrop waterRatio * yield
    set crops crops + addedCrop
    set farmWater 0
  ]
end

to lose-canal-water
  set canalLevel canalLevel * canalRetention
end

to calculate-averages
  ; aquifer level
  set aquiferLevelSum aquiferLevelSum + aquiferLevel
  set averageAquiferLevel ( aquiferLevelSum / ( ticks + 1 ) )
  ; water deficit
  set averageFarmerWaterDeficit mean [ ( farmWaterDeficit / waterDemand ) ] of turtles
  set averageFarmerWaterDeficitSum averageFarmerWaterDeficitSum + averageFarmerWaterDeficit
  set averageWaterDeficit ( averageFarmerWaterDeficitSum / ( ticks + 1 ) )
  ; crops
  set averageFarmerCrops mean [ crops ] of turtles
  set averageFarmerCropsSum averageFarmerCropsSum + averageFarmerCrops
  set averageCrops ( averageFarmerCropsSum / ( ticks + 1 ) )
end
@#$#@#$#@
GRAPHICS-WINDOW
216
12
647
444
-1
-1
3.0
1
10
1
1
1
0
1
1
1
-70
70
-70
70
0
0
1
ticks
30.0

BUTTON
23
73
86
106
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
97
74
160
107
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
668
748
841
781
canalToReservoirSize
canalToReservoirSize
0
1
1.0
0.1
1
NIL
HORIZONTAL

SLIDER
885
40
1057
73
aquiferSize
aquiferSize
0
12522
12522.0
1
1
ML
HORIZONTAL

MONITOR
461
477
566
522
aquiferLevel ML
aquiferLevel
17
1
11

SLIDER
668
243
845
276
drySeasonPrecipitation
drySeasonPrecipitation
0
100
46.0
1
1
mm
HORIZONTAL

SLIDER
666
198
856
231
rainySeasonPrecipitation
rainySeasonPrecipitation
0
1000
751.0
1
1
mm
HORIZONTAL

SLIDER
882
656
1054
689
dryDemand
dryDemand
0
2.78
2.78
0.01
1
ML/ha
HORIZONTAL

SLIDER
882
610
1054
643
rainyDemand
rainyDemand
0
4.96
4.96
0.01
1
ML/ha
HORIZONTAL

SLIDER
880
741
1052
774
dryYield
dryYield
0
3.65
3.65
0.01
1
T/ha
HORIZONTAL

SLIDER
881
700
1052
733
rainyYield
rainyYield
0
3.14
3.14
0.01
1
T/ha
HORIZONTAL

PLOT
9
606
306
822
Water extracted
seasons
ML
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"rain" 1.0 0 -16777216 true "" "plot rainWaterExtracted"
"canal" 1.0 0 -2674135 true "" "plot canalWaterExtracted"
"ground" 1.0 0 -13345367 true "" "plot groundWaterExtracted"

PLOT
317
607
630
820
Water levels
seasons
ML
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"aquifer level" 1.0 0 -14070903 true "" "plot aquiferLevel"
"reservoir level" 1.0 0 -2674135 true "" "plot reservoirLevel"

MONITOR
359
476
448
521
canalLevel ML
canalLevel
17
1
11

MONITOR
238
476
348
521
reservoirLevel ML
reservoirLevel
17
1
11

SLIDER
666
558
846
591
culturableCommandArea
culturableCommandArea
actualIrrigationArea
2671
2671.0
1
1
ha
HORIZONTAL

SLIDER
667
700
846
733
initialReservoirLevel
initialReservoirLevel
0
reservoirSize
16400.0
1
1
ML
HORIZONTAL

SLIDER
669
341
851
374
drySeasonPrecipitationSD
drySeasonPrecipitationSD
0
100
53.0
1
1
mm
HORIZONTAL

SLIDER
668
293
857
326
rainySeasonPrecipitationSD
rainySeasonPrecipitationSD
0
500
232.0
1
1
mm
HORIZONTAL

SLIDER
668
795
840
828
canalRetention
canalRetention
0
1
1.0
0.1
1
NIL
HORIZONTAL

SLIDER
883
86
1055
119
initialAquiferLevel
initialAquiferLevel
0
aquiferSize
2504.0
1
1
ML
HORIZONTAL

TEXTBOX
887
583
1037
601
Crop production
14
0.0
1

TEXTBOX
669
172
819
190
Rainfall
14
0.0
1

TEXTBOX
677
480
827
498
Reservoir
14
0.0
1

TEXTBOX
888
10
1038
28
Aquifer
14
0.0
1

SLIDER
10
153
196
186
proportionMicroIrrigation
proportionMicroIrrigation
0
1
0.1
0.1
1
NIL
HORIZONTAL

SLIDER
882
384
1075
417
proportionWaterSavingsRainy
proportionWaterSavingsRainy
0
1
0.33
0.01
1
NIL
HORIZONTAL

TEXTBOX
17
121
184
141
Policy
14
0.0
1

MONITOR
236
533
321
578
NIL
reservoirSize
17
1
11

MONITOR
361
534
443
579
canalSize ML
canalSize
17
1
11

TEXTBOX
14
264
164
324
Location: \nMorwan Tank in Neemuch District
14
0.0
1

TEXTBOX
14
331
195
433
Legend:\nwhite = hypothetical command area\nblue = canal network\ngreen = flood irrigation farms\nred = micro-irrigation farms
14
0.0
1

MONITOR
460
534
553
579
aquiferSize ML
aquiferSize
17
1
11

SWITCH
7
197
205
230
sociallyAlignedInvestment
sociallyAlignedInvestment
0
1
-1000

PLOT
1101
30
1327
210
Farmers adopted
seasons
number of farmers
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count turtles with [ useMicroIrrigation? = true ]"

SLIDER
667
128
853
161
rainySeasonAR
rainySeasonAR
-1
1
0.0
0.1
1
NIL
HORIZONTAL

SLIDER
885
296
1057
329
presentFocus
presentFocus
0
1
1.0
0.1
1
NIL
HORIZONTAL

SLIDER
667
603
852
636
actualIrrigationArea
actualIrrigationArea
0
2400
2400.0
1
1
ha
HORIZONTAL

SLIDER
882
476
1076
509
proportionYieldIncreaseRainy
proportionYieldIncreaseRainy
0
1.25
1.25
0.01
1
NIL
HORIZONTAL

SLIDER
882
430
1077
463
proportionWaterSavingsDry
proportionWaterSavingsDry
0
1
0.27
0.01
1
NIL
HORIZONTAL

SLIDER
880
520
1081
553
proportionYieldIncreaseDry
proportionYieldIncreaseDry
0
1
0.08
0.01
1
NIL
HORIZONTAL

PLOT
1109
435
1334
611
Average farmer water deficit
seasons
water deficit
0.0
10.0
0.0
0.01
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot averageFarmerWaterDeficit"

PLOT
1111
642
1337
821
Sum of farmer crops
seasons
crops
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot averageFarmerCropsSum"

SLIDER
666
510
839
543
commandArea
commandArea
0
4880
4880.0
1
1
ha
HORIZONTAL

SLIDER
884
131
1056
164
rainfallInfiltration
rainfallInfiltration
0
1
0.1
0.1
1
NIL
HORIZONTAL

SLIDER
884
253
1066
286
adoptionSensitivity
adoptionSensitivity
1
15
15.0
1
1
NIL
HORIZONTAL

TEXTBOX
890
183
1040
201
Farmer decisions
14
0.0
1

SLIDER
668
651
847
684
reservoirSize
reservoirSize
0
16400
16400.0
1
1
ML
HORIZONTAL

SLIDER
670
436
855
469
drySeasonWaterLoss
drySeasonWaterLoss
0
1
1.0
0.1
1
NIL
HORIZONTAL

SLIDER
669
389
856
422
rainySeasonWaterLoss
rainySeasonWaterLoss
0
1
0.68
0.01
1
NIL
HORIZONTAL

SLIDER
884
210
1073
243
socialVsEnvironmentWeight
socialVsEnvironmentWeight
0
1
0.5
0.05
1
NIL
HORIZONTAL

SLIDER
666
38
853
71
rainySeasonVariation
rainySeasonVariation
0
0.5
0.0
0.1
1
NIL
HORIZONTAL

SLIDER
666
84
851
117
rainySeasonSDVariation
rainySeasonSDVariation
0
0.5
0.0
0.1
1
NIL
HORIZONTAL

TEXTBOX
885
349
1035
367
Irrigation technology
14
0.0
1

TEXTBOX
667
10
817
28
Climate change
14
0.0
1

TEXTBOX
13
15
163
55
Irrigation adoption model
16
0.0
1

PLOT
1103
234
1331
408
Average aquifer level
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot averageAquiferLevel"

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
NetLogo 6.1.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="switch_sensitivity" repetitions="10" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="20"/>
    <metric>count turtles with [ useMicroIrrigation? = true ]</metric>
    <enumeratedValueSet variable="drySeasonWaterLoss">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitation">
      <value value="46"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseRainy">
      <value value="1.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialReservoirLevel">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hideNetwork">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseDry">
      <value value="0.08"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="socialWeight">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsDry">
      <value value="0.27"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extractCanalWater">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="environmentWeight">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="presentFocus">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="commandArea">
      <value value="4880"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionMicroIrrigation">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonPrecipitation">
      <value value="751"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonPrecipitationSD">
      <value value="232"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="culturableCommandArea">
      <value value="2671"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyDemand">
      <value value="4.96"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonWaterLoss">
      <value value="0.68"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="aquiferSize">
      <value value="12522"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyYield">
      <value value="3.14"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="actualIrrigationArea">
      <value value="2400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsRainy">
      <value value="0.33"/>
    </enumeratedValueSet>
    <steppedValueSet variable="switchSensitivity" first="10" step="5" last="40"/>
    <enumeratedValueSet variable="dryDemand">
      <value value="2.78"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitationSD">
      <value value="53"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonAR">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="reservoirSize">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialAquiferLevel">
      <value value="2393"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalRetention">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="targetWellConnected">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryYield">
      <value value="3.65"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalToReservoirSize">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainfallInfiltration">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="water_loss_sensitivity" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>count turtles with [ useMicroIrrigation? = true ]</metric>
    <metric>averageAquiferLevel</metric>
    <metric>averageWaterDeficit</metric>
    <metric>averageCrops</metric>
    <enumeratedValueSet variable="drySeasonWaterLoss">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitation">
      <value value="46"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseRainy">
      <value value="1.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialReservoirLevel">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hideNetwork">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseDry">
      <value value="0.08"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="socialWeight">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsDry">
      <value value="0.27"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extractCanalWater">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="environmentWeight">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="presentFocus">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="commandArea">
      <value value="4880"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionMicroIrrigation">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonPrecipitation">
      <value value="751"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonPrecipitationSD">
      <value value="232"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="culturableCommandArea">
      <value value="2671"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyDemand">
      <value value="4.96"/>
    </enumeratedValueSet>
    <steppedValueSet variable="rainySeasonWaterLoss" first="0.6" step="0.01" last="0.75"/>
    <enumeratedValueSet variable="aquiferSize">
      <value value="12522"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyYield">
      <value value="3.14"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="actualIrrigationArea">
      <value value="2400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsRainy">
      <value value="0.33"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="switchSensitivity">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryDemand">
      <value value="2.78"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitationSD">
      <value value="53"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonAR">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="reservoirSize">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialAquiferLevel">
      <value value="2393"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalRetention">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="targetWellConnected">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryYield">
      <value value="3.65"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalToReservoirSize">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainfallInfiltration">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="sd_sensitivity" repetitions="100" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>count turtles with [ useMicroIrrigation? = true ]</metric>
    <metric>averageAquiferLevel</metric>
    <metric>averageWaterDeficit</metric>
    <metric>averageCrops</metric>
    <enumeratedValueSet variable="drySeasonWaterLoss">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitation">
      <value value="46"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseRainy">
      <value value="1.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialReservoirLevel">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="precipitationVariation">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hideNetwork">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseDry">
      <value value="0.08"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsDry">
      <value value="0.27"/>
    </enumeratedValueSet>
    <steppedValueSet variable="precipitationSDVariation" first="0" step="0.1" last="0.4"/>
    <enumeratedValueSet variable="extractCanalWater">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="presentFocus">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="commandArea">
      <value value="4880"/>
    </enumeratedValueSet>
    <steppedValueSet variable="proportionMicroIrrigation" first="0" step="0.2" last="1"/>
    <enumeratedValueSet variable="rainySeasonPrecipitation">
      <value value="751"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonPrecipitationSD">
      <value value="232"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="culturableCommandArea">
      <value value="2671"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyDemand">
      <value value="4.96"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonWaterLoss">
      <value value="0.68"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="aquiferSize">
      <value value="12522"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyYield">
      <value value="3.14"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="socialVsEnvironmentWeight">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="actualIrrigationArea">
      <value value="2400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsRainy">
      <value value="0.33"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="switchSensitivity">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryDemand">
      <value value="2.78"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitationSD">
      <value value="53"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonAR">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="reservoirSize">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialAquiferLevel">
      <value value="2504"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalRetention">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="targetWellConnected">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryYield">
      <value value="3.65"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalToReservoirSize">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainfallInfiltration">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="mean_sensitivity" repetitions="50" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>count turtles with [ useMicroIrrigation? = true ]</metric>
    <metric>averageAquiferLevel</metric>
    <metric>averageWaterDeficit</metric>
    <metric>averageCrops</metric>
    <enumeratedValueSet variable="drySeasonWaterLoss">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitation">
      <value value="46"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseRainy">
      <value value="1.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialReservoirLevel">
      <value value="16400"/>
    </enumeratedValueSet>
    <steppedValueSet variable="precipitationVariation" first="0" step="0.1" last="0.4"/>
    <enumeratedValueSet variable="hideNetwork">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseDry">
      <value value="0.08"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsDry">
      <value value="0.27"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="precipitationSDVariation">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extractCanalWater">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="presentFocus">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="commandArea">
      <value value="4880"/>
    </enumeratedValueSet>
    <steppedValueSet variable="proportionMicroIrrigation" first="0" step="0.2" last="1"/>
    <enumeratedValueSet variable="rainySeasonPrecipitation">
      <value value="751"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonPrecipitationSD">
      <value value="232"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="culturableCommandArea">
      <value value="2671"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyDemand">
      <value value="4.96"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonWaterLoss">
      <value value="0.68"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="aquiferSize">
      <value value="12522"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyYield">
      <value value="3.14"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="socialVsEnvironmentWeight">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="actualIrrigationArea">
      <value value="2400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsRainy">
      <value value="0.33"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="switchSensitivity">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryDemand">
      <value value="2.78"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitationSD">
      <value value="53"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonAR">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="reservoirSize">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialAquiferLevel">
      <value value="2504"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalRetention">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="targetWellConnected">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryYield">
      <value value="3.65"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalToReservoirSize">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainfallInfiltration">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="weight_sensitivity" repetitions="50" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>count turtles with [ useMicroIrrigation? = true ]</metric>
    <metric>averageAquiferLevel</metric>
    <metric>averageWaterDeficit</metric>
    <metric>averageCrops</metric>
    <enumeratedValueSet variable="drySeasonWaterLoss">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitation">
      <value value="46"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseRainy">
      <value value="1.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialReservoirLevel">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="precipitationVariation">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hideNetwork">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseDry">
      <value value="0.08"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsDry">
      <value value="0.27"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="precipitationSDVariation">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extractCanalWater">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="presentFocus">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="commandArea">
      <value value="4880"/>
    </enumeratedValueSet>
    <steppedValueSet variable="proportionMicroIrrigation" first="0" step="0.2" last="1"/>
    <enumeratedValueSet variable="rainySeasonPrecipitation">
      <value value="751"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonPrecipitationSD">
      <value value="232"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="culturableCommandArea">
      <value value="2671"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyDemand">
      <value value="4.96"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonWaterLoss">
      <value value="0.68"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="aquiferSize">
      <value value="12522"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyYield">
      <value value="3.14"/>
    </enumeratedValueSet>
    <steppedValueSet variable="socialVsEnvironmentWeight" first="0" step="0.25" last="1"/>
    <enumeratedValueSet variable="actualIrrigationArea">
      <value value="2400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsRainy">
      <value value="0.33"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="switchSensitivity">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryDemand">
      <value value="2.78"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitationSD">
      <value value="53"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonAR">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="reservoirSize">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialAquiferLevel">
      <value value="2504"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalRetention">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="targetWellConnected">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryYield">
      <value value="3.65"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalToReservoirSize">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainfallInfiltration">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="proportion_micro" repetitions="200" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>count turtles with [ useMicroIrrigation? = true ]</metric>
    <metric>averageAquiferLevel</metric>
    <metric>averageWaterDeficit</metric>
    <metric>averageCrops</metric>
    <enumeratedValueSet variable="drySeasonWaterLoss">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitation">
      <value value="46"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseRainy">
      <value value="1.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialReservoirLevel">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="precipitationVariation">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hideNetwork">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseDry">
      <value value="0.08"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsDry">
      <value value="0.27"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="precipitationSDVariation">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extractCanalWater">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="presentFocus">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="commandArea">
      <value value="4880"/>
    </enumeratedValueSet>
    <steppedValueSet variable="proportionMicroIrrigation" first="0" step="0.1" last="1"/>
    <enumeratedValueSet variable="rainySeasonPrecipitation">
      <value value="751"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonPrecipitationSD">
      <value value="232"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="culturableCommandArea">
      <value value="2671"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyDemand">
      <value value="4.96"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonWaterLoss">
      <value value="0.68"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="aquiferSize">
      <value value="12522"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyYield">
      <value value="3.14"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="socialVsEnvironmentWeight">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="actualIrrigationArea">
      <value value="2400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsRainy">
      <value value="0.33"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="switchSensitivity">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryDemand">
      <value value="2.78"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitationSD">
      <value value="53"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonAR">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="reservoirSize">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialAquiferLevel">
      <value value="2504"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalRetention">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="targetWellConnected">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryYield">
      <value value="3.65"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalToReservoirSize">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainfallInfiltration">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="proportion_micro_low" repetitions="200" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>count turtles with [ useMicroIrrigation? = true ]</metric>
    <metric>averageAquiferLevel</metric>
    <metric>averageWaterDeficit</metric>
    <metric>averageCrops</metric>
    <enumeratedValueSet variable="drySeasonWaterLoss">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitation">
      <value value="46"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseRainy">
      <value value="1.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialReservoirLevel">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="precipitationVariation">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hideNetwork">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseDry">
      <value value="0.08"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsDry">
      <value value="0.27"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="precipitationSDVariation">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extractCanalWater">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="presentFocus">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="commandArea">
      <value value="4880"/>
    </enumeratedValueSet>
    <steppedValueSet variable="proportionMicroIrrigation" first="0" step="0.1" last="0.4"/>
    <enumeratedValueSet variable="rainySeasonPrecipitation">
      <value value="751"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonPrecipitationSD">
      <value value="232"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="culturableCommandArea">
      <value value="2671"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyDemand">
      <value value="4.96"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonWaterLoss">
      <value value="0.68"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="aquiferSize">
      <value value="12522"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyYield">
      <value value="3.14"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="socialVsEnvironmentWeight">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="actualIrrigationArea">
      <value value="2400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsRainy">
      <value value="0.33"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="switchSensitivity">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryDemand">
      <value value="2.78"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitationSD">
      <value value="53"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonAR">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="reservoirSize">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialAquiferLevel">
      <value value="2504"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalRetention">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="targetWellConnected">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryYield">
      <value value="3.65"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalToReservoirSize">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainfallInfiltration">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="weight_sensitivity_low" repetitions="100" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>count turtles with [ useMicroIrrigation? = true ]</metric>
    <metric>averageAquiferLevel</metric>
    <metric>averageWaterDeficit</metric>
    <metric>averageCrops</metric>
    <enumeratedValueSet variable="drySeasonWaterLoss">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitation">
      <value value="46"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseRainy">
      <value value="1.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialReservoirLevel">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="precipitationVariation">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hideNetwork">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionYieldIncreaseDry">
      <value value="0.08"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsDry">
      <value value="0.27"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="precipitationSDVariation">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extractCanalWater">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="presentFocus">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="commandArea">
      <value value="4880"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionMicroIrrigation">
      <value value="0.4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonPrecipitation">
      <value value="751"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonPrecipitationSD">
      <value value="232"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="culturableCommandArea">
      <value value="2671"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyDemand">
      <value value="4.96"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonWaterLoss">
      <value value="0.68"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="aquiferSize">
      <value value="12522"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainyYield">
      <value value="3.14"/>
    </enumeratedValueSet>
    <steppedValueSet variable="socialVsEnvironmentWeight" first="0" step="0.25" last="1"/>
    <enumeratedValueSet variable="actualIrrigationArea">
      <value value="2400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="proportionWaterSavingsRainy">
      <value value="0.33"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="switchSensitivity">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryDemand">
      <value value="2.78"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="drySeasonPrecipitationSD">
      <value value="53"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainySeasonAR">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="reservoirSize">
      <value value="16400"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialAquiferLevel">
      <value value="2504"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalRetention">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="targetWellConnected">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dryYield">
      <value value="3.65"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="canalToReservoirSize">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rainfallInfiltration">
      <value value="0.1"/>
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
