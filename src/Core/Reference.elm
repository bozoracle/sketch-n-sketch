module Core.Reference exposing
  ( BenchmarkInput
  , benchmarkInputParts
  , benchmarkInputPartCount
  , listPairwiseSwap
  , listEvenParity
  , listSortedInsert
  )

import MyRandom as Random exposing (Generator)
import Set exposing (Set)

import Tree exposing (Tree)

import PBESuite
import Core.Denotation as Denotation exposing (Denotation)
import Core.Sample as Sample

--------------------------------------------------------------------------------
-- Suite Interface
--------------------------------------------------------------------------------

type alias SuiteInfo =
  { definitions : String
  , fullExamples : { code : String, count : Int }
  }

si : (String, String, Int, String, Int) -> SuiteInfo
si (definitions, fullExamples, fullExampleCount, _, _) =
  { definitions = definitions
  , fullExamples = { code = fullExamples, count = fullExampleCount }
  }

--------------------------------------------------------------------------------
-- References
--------------------------------------------------------------------------------

type alias Reference a b =
  { name : String
  , functionName : String
  , args : Int
  , kMax : Int
  , suiteInfo : SuiteInfo
  , dIn : Denotation a
  , dOut : Denotation b
  , input : Generator a
  , baseCase : Maybe (Generator a)
  , func : a -> b
  }

-- Bool

bool_band =
  { name = "bool_band"
  , functionName = "and"
  , args = 2
  , kMax = 4
  , suiteInfo = si PBESuite.bool_band
  , dIn = Denotation.args2 Denotation.bool Denotation.bool
  , dOut = Denotation.bool
  , input = Random.pair Sample.bool Sample.bool
  , baseCase = Nothing
  , func =
      let
        f : (Bool, Bool) -> Bool
        f (x, y) =
          x && y
      in
        f
  }

bool_bor =
  { name = "bool_bor"
  , functionName = "or"
  , args = 2
  , kMax = 4
  , suiteInfo = si PBESuite.bool_bor
  , dIn = Denotation.args2 Denotation.bool Denotation.bool
  , dOut = Denotation.bool
  , input = Random.pair Sample.bool Sample.bool
  , baseCase = Nothing
  , func =
      let
        f : (Bool, Bool) -> Bool
        f (x, y) =
          x || y
      in
        f
  }

bool_impl =
  { name = "bool_impl"
  , functionName = "impl"
  , args = 2
  , kMax = 4
  , suiteInfo = si PBESuite.bool_impl
  , dIn = Denotation.args2 Denotation.bool Denotation.bool
  , dOut = Denotation.bool
  , input = Random.pair Sample.bool Sample.bool
  , baseCase = Nothing
  , func =
      let
        f : (Bool, Bool) -> Bool
        f (x, y) =
          (not x) || y
      in
        f
  }

bool_neg =
  { name = "bool_neg"
  , functionName = "neg"
  , args = 1
  , kMax = 2
  , suiteInfo = si PBESuite.bool_neg
  , dIn = Denotation.bool
  , dOut = Denotation.bool
  , input = Sample.bool
  , baseCase = Nothing
  , func =
      let
        f : Bool -> Bool
        f x =
          not x
      in
        f
  }

bool_xor =
  { name = "bool_xor"
  , functionName = "xor"
  , args = 2
  , kMax = 4
  , suiteInfo = si PBESuite.bool_xor
  , dIn = Denotation.args2 Denotation.bool Denotation.bool
  , dOut = Denotation.bool
  , input = Random.pair Sample.bool Sample.bool
  , baseCase = Nothing
  , func =
      let
        f : (Bool, Bool) -> Bool
        f (x, y) =
          x /= y
      in
        f
  }

-- List

list_append =
  { name = "list_append"
  , functionName = "append"
  , args = 2
  , kMax = 20
  , suiteInfo = si PBESuite.list_append
  , dIn =
      Denotation.args2
        (Denotation.simpleList Denotation.int)
        (Denotation.simpleList Denotation.int)
  , dOut = Denotation.simpleList Denotation.int
  , input = Random.pair Sample.natList Sample.natList
  , baseCase = Just (Random.constant ([], []))
  , func =
      let
        f : (List Int, List Int) -> List Int
        f (xs, ys) =
          xs ++ ys
      in
        f
  }

list_concat =
  { name = "list_concat"
  , functionName = "concat"
  , args = 1
  , kMax = 20
  , suiteInfo = si PBESuite.list_concat
  , dIn = Denotation.simpleNestedList Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Sample.nestedNatList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List (List Int) -> List Int
        f xss =
          List.concat xss
      in
        f
  }

list_drop =
  { name = "list_drop"
  , functionName = "listDrop"
  , args = 2
  , kMax = 40
  , suiteInfo = si PBESuite.list_drop
  , dIn = Denotation.args2 (Denotation.simpleList Denotation.int) Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Random.pair Sample.natList Sample.nat
  , baseCase = Just (Random.constant ([], 0))
  , func =
      let
        f : (List Int, Int) -> List Int
        f (xs, n) =
          List.drop n xs
      in
        f
  }

listEvenParity : List Bool -> Bool
listEvenParity bs =
  case bs of
    [] ->
      True

    head :: tail ->
      if head then
        not (listEvenParity tail)
      else
        listEvenParity tail

list_even_parity =
  { name = "list_even_parity"
  , functionName = "evenParity"
  , args = 1
  , kMax = 15
  , suiteInfo = si PBESuite.list_even_parity
  , dIn = Denotation.simpleList Denotation.bool
  , dOut = Denotation.bool
  , input = Sample.boolList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Bool -> Bool
        f bs =
          listEvenParity bs
      in
        f
  }

list_hd =
  { name = "list_hd"
  , functionName = "listHead"
  , args = 1
  , kMax = 10
  , suiteInfo = si PBESuite.list_hd
  , dIn = Denotation.simpleList Denotation.int
  , dOut = Denotation.int
  , input = Sample.natList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Int -> Int
        f xs =
          case xs of
            [] ->
              0

            head :: _ ->
              head
      in
        f
  }

list_inc =
  { name = "list_inc"
  , functionName = "listInc"
  , args = 1
  , kMax = 10
  , suiteInfo = si PBESuite.list_inc
  , dIn = Denotation.simpleList Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Sample.natList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Int -> List Int
        f xs =
          List.map ((+) 1) xs
      in
        f
  }

list_last =
  { name = "list_last"
  , functionName = "listLast"
  , args = 1
  , kMax = 20
  , suiteInfo = si PBESuite.list_last
  , dIn = Denotation.simpleList Denotation.int
  , dOut = Denotation.opt Denotation.int
  , input = Sample.natList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Int -> Maybe Int
        f xs =
          case xs of
            [] ->
              Nothing

            [x] ->
              Just x

            _ :: tail ->
              f tail
      in
        f
  }

list_length =
  { name = "list_length"
  , functionName = "listLength"
  , args = 1
  , kMax = 5
  , suiteInfo = si PBESuite.list_length
  , dIn = Denotation.simpleList Denotation.int
  , dOut = Denotation.int
  , input = Sample.natList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Int -> Int
        f xs =
          List.length xs
      in
        f
  }

list_nth =
  { name = "list_nth"
  , functionName = "listNth"
  , args = 2
  , kMax = 40
  , suiteInfo = si PBESuite.list_nth
  , dIn = Denotation.args2 (Denotation.simpleList Denotation.int) Denotation.int
  , dOut = Denotation.int
  , input = Random.pair Sample.natList Sample.nat
  , baseCase = Just (Random.constant ([], 0))
  , func =
      let
        f : (List Int, Int) -> Int
        f (xs, n) =
          case xs of
            [] ->
              0

            head :: tail ->
              if n == 0 then
                head
              else
                f (tail, n - 1)
      in
        f
  }

listPairwiseSwap : List a -> Maybe (List a)
listPairwiseSwap xs =
  case xs of
    [] ->
      Just []

    [_] ->
      Nothing

    x1 :: x2 :: tail ->
      Maybe.map
        (\flipped -> x2 :: x1 :: flipped)
        (listPairwiseSwap tail)

list_pairwise_swap =
  { name = "list_pairwise_swap"
  , functionName = "listPairwiseSwap"
  , args = 1
  , kMax = 20
  , suiteInfo = si PBESuite.list_pairwise_swap
  , dIn = Denotation.simpleList Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Sample.natList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Int -> List Int
        f xs =
          case listPairwiseSwap xs of
            Nothing ->
              []

            Just flipped ->
              flipped
      in
        f
  }

list_rev_append =
  { name = "list_rev_append"
  , functionName = "listRevAppend"
  , args = 1
  , kMax = 15
  , suiteInfo = si PBESuite.list_rev_append
  , dIn = Denotation.simpleList Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Sample.natList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Int -> List Int
        f xs =
          List.reverse xs
      in
        f
  }

list_rev_fold =
  { name = "list_rev_fold"
  , functionName = "listRevFold"
  , args = 1
  , kMax = 15
  , suiteInfo = si PBESuite.list_rev_fold
  , dIn = Denotation.simpleList Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Sample.natList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Int -> List Int
        f xs =
          List.reverse xs
      in
        f
  }

list_rev_snoc =
  { name = "list_rev_snoc"
  , functionName = "listRevSnoc"
  , args = 1
  , kMax = 15
  , suiteInfo = si PBESuite.list_rev_snoc
  , dIn = Denotation.simpleList Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Sample.natList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Int -> List Int
        f xs =
          List.reverse xs
      in
        f
  }

list_rev_tailcall =
  { name = "list_rev_tailcall"
  , functionName = "listRevTailcall"
  , args = 1
  , kMax = 20
  , suiteInfo = si PBESuite.list_rev_tailcall
  , dIn = Denotation.simpleList Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Sample.natList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Int -> List Int
        f xs =
          List.reverse xs
      in
        f
  }

list_snoc =
  { name = "list_snoc"
  , functionName = "listSnoc"
  , args = 2
  , kMax = 20
  , suiteInfo = si PBESuite.list_snoc
  , dIn = Denotation.args2 (Denotation.simpleList Denotation.int) Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Random.pair Sample.natList Sample.nat
  , baseCase = Just (Random.constant ([], 0))
  , func =
      let
        f : (List Int, Int) -> List Int
        f (xs, n) =
          xs ++ [n]
      in
        f
  }

list_sort_sorted_insert =
  { name = "list_sort_sorted_insert"
  , functionName = "listSortSortedInsert"
  , args = 1
  , kMax = 20
  , suiteInfo = si PBESuite.list_sort_sorted_insert
  , dIn = Denotation.simpleList Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Sample.natList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Int -> List Int
        f xs =
          List.sort xs
      in
        f
  }

listSortedInsert : comparable -> List comparable -> List comparable
listSortedInsert y xs =
  case xs of
    [] ->
      [y]

    head :: tail ->
      if y < head then
        y :: xs
      else if y == head then
        xs
      else
        head :: (listSortedInsert y tail)

list_sorted_insert =
  { name = "list_sorted_insert"
  , functionName = "listSortedInsert"
  , args = 2
  , kMax = 40
  , suiteInfo = si PBESuite.list_sorted_insert
  , dIn = Denotation.args2 (Denotation.simpleList Denotation.int) Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Random.pair Sample.natList Sample.nat
  , baseCase = Just (Random.constant ([], 0))
  , func =
      let
        f : (List Int, Int) -> List Int
        f (xs, n) =
          listSortedInsert n xs
      in
        f
  }

list_stutter =
  { name = "list_stutter"
  , functionName = "listStutter"
  , args = 1
  , kMax = 10
  , suiteInfo = si PBESuite.list_stutter
  , dIn = Denotation.simpleList Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Sample.natList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Int -> List Int
        f xs =
          case xs of
            [] ->
              []

            y :: ys ->
              y :: y :: f ys
      in
        f
  }

list_sum =
  { name = "list_sum"
  , functionName = "listSum"
  , args = 1
  , kMax = 10
  , suiteInfo = si PBESuite.list_sum
  , dIn = Denotation.simpleList Denotation.int
  , dOut = Denotation.int
  , input = Sample.natList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Int -> Int
        f xs =
          List.sum xs
      in
        f
  }

list_take =
  { name = "list_take"
  , functionName = "listTake"
  , args = 2
  , kMax = 40
  , suiteInfo = si PBESuite.list_take
  , dIn = Denotation.args2 Denotation.int (Denotation.simpleList Denotation.int)
  , dOut = Denotation.simpleList Denotation.int
  , input = Random.pair Sample.nat Sample.natList
  , baseCase = Just (Random.constant (0, []))
  , func =
      let
        f : (Int, List Int) -> List Int
        f (n, xs) =
          List.take n xs
      in
        f
  }

list_tl =
  { name = "list_tl"
  , functionName = "listTail"
  , args = 1
  , kMax = 10
  , suiteInfo = si PBESuite.list_tl
  , dIn = Denotation.simpleList Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Sample.natList
  , baseCase = Just (Random.constant [])
  , func =
      let
        f : List Int -> List Int
        f xs =
          case xs of
            [] ->
              []

            _ :: tail ->
              tail
      in
        f
  }

nat_iseven =
  { name = "nat_iseven"
  , functionName = "isEven"
  , args = 1
  , kMax = 4
  , suiteInfo = si PBESuite.nat_iseven
  , dIn = Denotation.int
  , dOut = Denotation.bool
  , input = Sample.nat
  , baseCase = Just (Random.constant 0)
  , func =
      let
        f : Int -> Bool
        f x =
          if x == 0 then
            True
          else if x == 1 then
            False
          else
            f (x - 2)
      in
        f
  }

nat_max =
  { name = "nat_max"
  , functionName = "natMax"
  , args = 2
  , kMax = 9
  , suiteInfo = si PBESuite.nat_max
  , dIn = Denotation.args2 Denotation.int Denotation.int
  , dOut = Denotation.int
  , input = Random.pair Sample.nat Sample.nat
  , baseCase = Just (Random.constant (0, 0))
  , func =
      let
        f : (Int, Int) -> Int
        f (x, y) =
          if x >= y then
            x
          else
            y
      in
        f
  }

nat_pred =
  { name = "nat_pred"
  , functionName = "natPred"
  , args = 1
  , kMax = 4
  , suiteInfo = si PBESuite.nat_pred
  , dIn = Denotation.int
  , dOut = Denotation.int
  , input = Sample.nat
  , baseCase = Just (Random.constant 0)
  , func =
      let
        f : Int -> Int
        f x =
          if x == 0 then
            0
          else
            x - 1
      in
        f
  }

nat_add =
  { name = "nat_add"
  , functionName = "natAdd"
  , args = 2
  , kMax = 9
  , suiteInfo = si PBESuite.nat_add
  , dIn = Denotation.args2 Denotation.int Denotation.int
  , dOut = Denotation.int
  , input = Random.pair Sample.nat Sample.nat
  , baseCase = Just (Random.constant (0, 0))
  , func =
      let
        f : (Int, Int) -> Int
        f (x, y) =
          x + y
      in
        f
  }

-- tree_binsert =
--   { name = "tree_binsert"
--   , functionName = "treeBInsert"
--   , args = 2
--   , kMax = 40
--   , suiteInfo = si PBESuite.tree_binsert
--   , dIn = Denotation.args2 Denotation.int (Denotation.tree Denotation.int)
--   , dOut = Denotation.tree Denotation.int
--   , input = Random.pair Sample.nat Sample.natTree
--   , baseCase = Just (Random.constant (0, Tree.Leaf))
--   , func =
--       let
--         f : (Int, Tree Int) -> Tree Int
--         f (y, tree) =
--           Tree.binsert y tree
--       in
--         f
--   }

tree_collect_leaves =
  { name = "tree_collect_leaves"
  , functionName = "treeCollectLeaves"
  , args = 1
  , kMax = 20
  , suiteInfo = si PBESuite.tree_collect_leaves
  , dIn = Denotation.tree Denotation.bool
  , dOut = Denotation.simpleList Denotation.bool
  , input = Sample.boolTree
  , baseCase = Just (Random.constant Tree.Leaf)
  , func =
      let
        f : Tree Bool -> List Bool
        f tree =
          Tree.inOrder tree
      in
        f
  }

tree_count_leaves =
  { name = "tree_count_leaves"
  , functionName = "treeCountLeaves"
  , args = 1
  , kMax = 20
  , suiteInfo = si PBESuite.tree_count_leaves
  , dIn = Denotation.tree Denotation.bool
  , dOut = Denotation.int
  , input = Sample.boolTree
  , baseCase = Just (Random.constant Tree.Leaf)
  , func =
      let
        f : Tree Bool -> Int
        f tree =
          Tree.countLeaves tree
      in
        f
  }

tree_count_nodes =
  { name = "tree_count_nodes"
  , functionName = "treeCountNodes"
  , args = 1
  , kMax = 20
  , suiteInfo = si PBESuite.tree_count_nodes
  , dIn = Denotation.tree Denotation.int
  , dOut = Denotation.int
  , input = Sample.natTree
  , baseCase = Just (Random.constant Tree.Leaf)
  , func =
      let
        f : Tree Int -> Int
        f tree =
          Tree.countNodes tree
      in
        f
  }

tree_inorder =
  { name = "tree_inorder"
  , functionName = "treeInOrder"
  , args = 1
  , kMax = 20
  , suiteInfo = si PBESuite.tree_inorder
  , dIn = Denotation.tree Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Sample.natTree
  , baseCase = Just (Random.constant Tree.Leaf)
  , func =
      let
        f : Tree Int -> List Int
        f tree =
          Tree.inOrder tree
      in
        f
  }

-- tree_nodes_at_level =
--   { name = "tree_nodes_at_level"
--   , functionName = "treeNodesAtLevel"
--   , args = 1
--   , kMax = 20
--   , suiteInfo = si PBESuite.tree_nodes_at_level
--   , dIn = Denotation.args2 Denotation.int (Denotation.tree Denotation.bool)
--   , dOut = Denotation.int
--   , input = Random.pair Sample.nat Sample.boolTree
--   , baseCase = Just (Random.constant (0, Tree.Leaf))
--   , func =
--       let
--         f : (Int, Tree Bool) -> Int
--         f (level, tree) =
--           Tree.countNodesAtLevel level tree
--       in
--         f
--   }

-- tree_postorder =
--   { name = "tree_postorder"
--   , functionName = "treePostorder"
--   , args = 1
--   , kMax = 20
--   , suiteInfo = si PBESuite.tree_postorder
--   , dIn = Denotation.tree Denotation.int
--   , dOut = Denotation.simpleList Denotation.int
--   , input = Sample.natTree
--   , baseCase = Just (Random.constant Tree.Leaf)
--   , func =
--       let
--         f : Tree Int -> List Int
--         f tree =
--           Tree.postOrder tree
--       in
--         f
--   }

tree_preorder =
  { name = "tree_preorder"
  , functionName = "treePreorder"
  , args = 1
  , kMax = 20
  , suiteInfo = si PBESuite.tree_preorder
  , dIn = Denotation.tree Denotation.int
  , dOut = Denotation.simpleList Denotation.int
  , input = Sample.natTree
  , baseCase = Just (Random.constant Tree.Leaf)
  , func =
      let
        f : Tree Int -> List Int
        f tree =
          Tree.preOrder tree
      in
        f
  }

--------------------------------------------------------------------------------
-- Benchmarking Interface
--------------------------------------------------------------------------------

type alias BenchmarkInput =
  { name : String
  , definitions : String
  , fullExamples : { code : String, count : Int }
  , restrictedExamples : Maybe { code : String, count : Int }
  }

examples :
  String -> Int -> Denotation a -> Denotation b -> Generator (List (Set (a, b)))
    -> Generator (List (Int, String))
examples functionName args dIn dOut =
  let
    extract ios =
      let _ = Debug.log "Generated Examples" ios in
      ( List.length ios
      , "specifyFunction"
          ++ (if args == 1 then "" else toString args)
          ++ " "
          ++ functionName
          ++ "\n[ "
          ++ String.join
               "\n, "
               (List.map (\(x, y) -> "(" ++ dIn x ++ ", " ++ dOut y ++ ")") ios)
          ++ "\n]"
      )
  in
    -- Random.map (Set.toList >> List.map (Set.toList >> extract))
    Random.map (List.map (Set.toList >> extract))

createBenchmarkInput :
  Int -> Reference a b -> Generator (List (List BenchmarkInput))
createBenchmarkInput n { name, functionName, args, kMax, suiteInfo, dIn, dOut,
 input, baseCase, func } =
  List.range 1 kMax
    |> List.map
         ( \k ->
             Random.map
               ( List.map <|
                   \(exampleCount, exampleString) ->
                     { name = name
                     , definitions = suiteInfo.definitions
                     , fullExamples = suiteInfo.fullExamples
                     , restrictedExamples =
                         Just { code = exampleString, count = exampleCount }
                     }
               )
               ( examples
                   functionName
                   args
                   dIn
                   dOut
                   (Sample.trial n k func input baseCase)
               )
         )
  |> Random.sequence

benchmarkInputParts : List (Generator (List (List (List BenchmarkInput))))
benchmarkInputParts =
  let
    n =
      Sample.trialCount
  in
    List.map Random.sequence
      [ [ createBenchmarkInput n bool_band
        , createBenchmarkInput n bool_bor
        , createBenchmarkInput n bool_impl
        , createBenchmarkInput n bool_neg
        , createBenchmarkInput n bool_xor

        , createBenchmarkInput n list_append
        , createBenchmarkInput n list_concat
        , createBenchmarkInput n list_drop
        ]
      , [ createBenchmarkInput n list_even_parity
        -- , createBenchmarkInput n list_filter
        -- , createBenchmarkInput n list_fold
        , createBenchmarkInput n list_hd
        , createBenchmarkInput n list_inc
        , createBenchmarkInput n list_last
        , createBenchmarkInput n list_length
        ]
      , [
        -- , createBenchmarkInput n list_map
          createBenchmarkInput n list_nth
        ]
      , [ createBenchmarkInput n list_rev_append
        , createBenchmarkInput n list_rev_fold
        , createBenchmarkInput n list_rev_snoc
        , createBenchmarkInput n list_rev_tailcall
        , createBenchmarkInput n list_snoc
        , createBenchmarkInput n list_sort_sorted_insert
        , createBenchmarkInput n list_stutter
        ]
      , [ createBenchmarkInput n list_sum
        , createBenchmarkInput n list_take
        , createBenchmarkInput n list_tl
        , createBenchmarkInput n nat_iseven
        , createBenchmarkInput n nat_max
        , createBenchmarkInput n nat_pred
        , createBenchmarkInput n nat_add
        ]
      , [ createBenchmarkInput n tree_collect_leaves
        , createBenchmarkInput n tree_count_nodes
        , createBenchmarkInput n tree_inorder
        -- , createBenchmarkInput n tree_map
        , createBenchmarkInput n tree_preorder
        ]
        -- Benchmarks requiring longer timeout
      , [ createBenchmarkInput n list_sorted_insert
        , createBenchmarkInput n list_pairwise_swap
        , createBenchmarkInput n tree_count_leaves
        ]
      ]


benchmarkInputPartCount : Int
benchmarkInputPartCount =
  List.length benchmarkInputParts