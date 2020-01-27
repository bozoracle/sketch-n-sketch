type Pair a b = Pair a b

pairToString aToStr bToStr pair =
  case pair of
    Pair a b -> "(" + aToStr a + "," + bToStr b + ")"

toString : Num -> String
toString n = numToStringBuiltin n

toString : String -> String
toString str = '"' + str + '"' -- no escaping

toString : Pair a b -> String
toString strNumPair  =
  pairToString toString toString strNumPair

(Pair "key" 10 : Pair String Num)