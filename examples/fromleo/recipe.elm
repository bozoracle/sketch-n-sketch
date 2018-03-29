-- If you write prop[number] in the text, it will display this number but it will be proportional to the number of cakes !
-- If you write plurs[number] in the text, it will display a "s" if the number is greater than 1 !

base = 1000
temperature = 180

language = "English"
otherLanguage = if language == "French" then "English" else "French"

txt = dict [
  ["French", """
<h1>Moelleux chocolat amandes</h1>
Recette pour multdivby[20,1000] petits gâteaux.<br>
Préchauffer le four à @(temperature)° (Celsius)
<li>multdivby[4,1000] œufifmanys[4,1000]</li>
<li>multdivby[1,2000] verre de sucre</li>
<li>multdivby[200,1000]g de chocolat fondu</li>
<li>multdivby[50,1000]g de poudre d’amande</li>
<li>multdivby[2,1000] cs d’huile de tournesol</li>
<li>Cannelle</li>
<li>Pincée de sel</li>
Au four pendant 10 minutes dans des moules à cupcakes.<br>
On peut aussi mettre en déco des amandes effilées, ou remplacer le chocolat par un citron pressé"""],
  ["English", """
<h1>Soft chocolate almond cakes</h1>
Recipe for multdivby[20,1000] small cakes.<br>
Preheat the oven at @(floor (temperature * freeze 9 / freeze 5) + freeze 32)° Fahrenheit
<li>multdivby[4,1000] eggifmanys[4,1000]</li>
<li>multdivby[1,2000] glass of sugar</li>
<li>multdivby[200,1000]g of melted chocolate</li>
<li>multdivby[50,1000]g of almond powder</li>
<li>multdivby[2,1000] tbls of sunflower oil</li>
<li>Cinnamon</li>
<li>A pinch of salt</li>
In the oven for 10 minutes in cupcakes pans.<br>
One can also put as decoration sliced almonds, or replace chocolate by a squeezed lemon."""]
  ] |> applyDict2 language

result = replaceAllIn "(multdivby|ifmany(\\w+))\\[(\\d+),(\\d+)\\]" (\m ->
  let mult = String.toInt <| nth m.group 3 in
  let div = String.toInt <|  nth m.group 4 in
  case nth m.group 1 of
    "multdivby" ->
      let res = floor (base * freeze mult / freeze div) in
      if res < 6 then -- We take into account 1/2, 1/4 and 3/4 until 5, else it makes no sense, but no more.
        { apply base = freeze <|
           case floor (base * mult * 4 / div) - 4*res of
             0 -> if res == 0 then "<¼" else toString res
             1 -> if res == 0 then "¼" else if res >= 4 then toString res else toString res + "¼"
             2 -> if res == 0 then "½" else toString res + "3/4"
             3 -> if res == 0 then "¾" else if res >= 4 then toString res else toString res + "¾"
          update {outputNew, outputOriginal} =
            if outputNew == outputOriginal then {values=[base]} else
            let quantityTimes4 = case extractFirstIn "(.*)(¼|[ +]?[13]/[24]|½|¾)" outputNew of
              ["Just", [i, complement]] -> 
                 let addi x = if i == "" then x else 4 * String.toInt i + x in
                 case complement of
                   "¼"    -> addi 1
                   "1/4"  -> addi 1
                   " 1/4" -> addi 1
                   "+1/4" -> addi 1
                   "½"    -> addi 2
                   "1/2"  -> addi 2
                   " 1/2" -> addi 2
                   "+1/2" -> addi 2
                   "¾"    -> addi 3
                   "3/4"  -> addi 3
                   " 3/4" -> addi 3
                   "+3/4" -> addi 3
                   a      -> "complement error: " + complement + 1
              ["Nothing"] -> 4 * String.toInt i
            in
            {values = floor (quantityTimes4 * div / mult / 4) }
        }.apply base
      else toString res
    ifmanyEnding ->
      let ending = nth m.group 2 in
      let res = floor (base * freeze mult * freeze 4 / freeze div) in
      { apply x = if res > 4 then ending else ""
        update {outputNew, outputOriginal} =
          if outputNew == "" && outputOriginal == ending then {values=[4]} else {values = []} }.apply res) txt

div_ [["margin", "20px"]] [] <|
html <| """<button onclick="this.setAttribute('v','@otherLanguage')" v="@language">To @otherLanguage</button><br>""" +
  ( dict [["English", """<i>Hint:</i> Use prop[5] for a proportional number 5, plurs[5] to place an s if the quantity (5) is greater than 1."""],
          ["French", """<i>Astuce:</i> Ecrire prop[5] pour un nombre proportionel 5, plurs[5] pour un 's' conditionel si la quantité 5 est plus grande que 1."""]] |> applyDict2 language) + 
 { apply x = freeze x ,
   update {output} =
     { values = [replaceAllIn "((prop)(\\w*)|(plur)(\\w+))\\[(\\d+)\\]" (\m ->
        let amount = String.toInt (nth m.group 6) in
        case nth m.group 2 of
           "prop" -> "multdivby[" + amount + "," + base + "]"
           "" ->
             case nth m.group 4 of
               "plur" -> let plural = nth m.group 5 in
                 "ifmany" + plural + "[" + amount + "," + base + "]"
               _ -> "plur error: " + complement + 1
           _ -> "prop error: " + complement + 1)
         output] }
 }.apply result