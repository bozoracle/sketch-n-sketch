editorInfo = """
<h1>Linked-Text Editor</h1>
<p>
  This text editor is set up to allow <em>linking</em>
  ot text elements. Two portions of text can be linked
  together by defining a variable, from the output interface.
</p>
<p>
  <b>Defining a link-able word:</b>
  Prefix a word with $ (for example, "$prove") to create
  a variable named "prove". Its content is originally
  its name, so the dollar is removed.
</p>
<p>
  <b>Inserting linked words:</b>
  To insert a link of the content of a variable named "prove", 
  type somewhere else "$prove" or add a dollar to an existing "prove".
</p>
<p>
  <b>Modifying linked words:</b>
  If you change one of the linked occurrences of "prove" to "show",
  you will notice that all linked occurrences change. If you add a new
  "$prove", it will also be replaced by "prove".
  Replacements can be nested, but it does not replace variables in cycles, so you're safe
</p>
<p>
  In the example below, the notations are linked. If you change a P to H, all of them will be updated.
</p>
"""

variables = 
  [("proofbyinduction", "proof by induction")
  ,("inductionaxiom", "induction axiom")
  ,("P", "P")
  ,("n", "n")
  ,("k","k")]

variablesDict = Dict.fromList variables

replaceVariables variablesDict string =
  Regex.replace "\\$(?!_)(\\w+)" (\m -> 
    let key = nth m.group 1 in
    case Dict.get key variablesDict of
      Nothing -> m.match
      Just definition -> replaceVariables (Dict.remove key variablesDict) definition
  ) string

minnum = 1
maxnum = 4
sequence = List.range minnum maxnum

content = """<h1>Induction Hypothesis</h1>
<pre style="font-family:cambria;white-space:pre-line;">
A $proofbyinduction makes use of the $inductionaxiom.
The $inductionaxiom states that, for a proposition $P depending on an integer $n, if the following precondition is satisfied:

    $P(1)   ∧   ∀$n⩾1. $P($n) ⇒ $P($n+1)

then the following result holds:

    ∀$n⩾1. $P($n)

In other words, if we want to prove a proposition $P($n) for any integer $n, we first need to prove that $P(1) holds. Then, we need to prove that if we know $P($k) for any given integer $k, we can prove $P($k + 1).

Let us consider the sum of the numbers from @minnum to @maxnum: @(sequence |> map (\x -> toString x) |> String.join "+") = @(List.sum sequence). At the same time, if we multiply @maxnum by @maxnum + 1 (which is @(maxnum + 1)), and divide by 2, we get:@maxnum*(@maxnum+1)/2 = @maxnum*@(maxnum+1)/2 = @(maxnum*(maxnum+1))/2 = @(maxnum*(maxnum+1)/2) which is the same result. Hence we can conjecture that:

$P($n) = "The sum of numbers 1+...+$n is $n*($n+1)/2"

We prove it by using the $proofbyinduction principle.<ul
><li>$P(1) is trivially true.</li
><li>If $P($n) holds, then
  1+...+ $n + ($n+1)
= $n*($n+1)/2 + $n+1 (by invoking $P($n))
= ($n+1)(($n+1)+1)/2 (by factoring)
Therefore, $P($n+1) holds.</li></ul
>By the $inductionaxiom, we conclude that $P($n) is true for all $n.
""" |>
  replaceVariables variablesDict |>
  Regex.replace "(\\$)_(\\w+)" (\m ->
    nth m.group 1 + "<span></span>" + nth m.group 2) |>
  (\x ->
    { apply (x, variables) = x
      update {input = (x, variables), output} =
        Regex.find "\\$(?!_)(\\w+)(?:=(\\w+))?" output |>
        List.foldl (\(_::name::definition::_) (variables, variablesDict) ->
          if Dict.member name variablesDict  then (variables, variablesDict)
          else 
            let vardef = if definition == "" then name else definition
            in (variables ++ [(name, vardef)], Dict.insert name vardef variablesDict)
        ) (variables, variablesDict) |> \(newVariables, _) ->
          let newOutput = Regex.replace "\\$(?!_)(\\w+)(?:=(\\w+))?" (\m -> 
            let [_, name, _] = m.group in
             if Dict.member name variablesDict then m.match else "$" + name
          ) output in
          Ok (Inputs [(newOutput, newVariables)])
    }.apply (x, variables)
  )

  
main = 
  Html.forceRefresh <|
  Html.div [["margin", "20px"], ["cursor", "text"]] []
    [ Html.div [] [] <|
        Html.parse editorInfo
    , Html.div [["border", "4px solid black"], ["padding", "20px"]] [] <|
        Html.parse content
    ]