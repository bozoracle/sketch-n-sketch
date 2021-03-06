module BinaryOperatorParser exposing
  ( Associativity(..)
  , Precedence
  , PrecedenceTable
  , emptyPrecedenceTable
  , addOperator
  , buildPrecedenceTable
  , getOperatorInfo
  , binaryOperator
  )

import Parser exposing (..)
import ParserUtils exposing
  ( lookAhead
  , optional
  )

import Dict exposing (Dict)

--==============================================================================
--= Data Structures
--==============================================================================

type Associativity
  = Left
  | Right

type alias Precedence =
  Int

type alias OperatorInfo =
  (Associativity, Precedence)

type PrecedenceTable =
  PT (Dict String OperatorInfo)

emptyPrecedenceTable : PrecedenceTable
emptyPrecedenceTable =
  PT Dict.empty

addOperator
  : (String, Associativity, Precedence) -> PrecedenceTable -> PrecedenceTable
addOperator (op, assoc, prec) (PT table) =
  PT <|
    Dict.insert op (assoc, prec) table

buildPrecedenceTable
  : List (Precedence, List String, List String) -> PrecedenceTable
buildPrecedenceTable =
  let
    build associativity precedence operators table =
      List.foldl
        (\op -> addOperator (op, associativity, precedence))
        table
        operators

    buildPrecedenceLevel (precedence, lefts, rights) table =
      table
        |> build Left precedence lefts
        |> build Right precedence rights
  in
    List.foldl buildPrecedenceLevel emptyPrecedenceTable

getOperatorInfo : String -> PrecedenceTable -> Maybe OperatorInfo
getOperatorInfo op (PT table) =
  Dict.get op table

--==============================================================================
--= Parsers
--==============================================================================

--------------------------------------------------------------------------------
-- Precedence climbing algorithm described by:
--------------------------------------------------------------------------------
-- http://eli.thegreenplace.net/2012/08/02/
--   parsing-expressions-by-precedence-climbing
--------------------------------------------------------------------------------

binaryOperator
  :  { greedySpaceParser : Parser space
     , precedenceTable : PrecedenceTable
     , minimumPrecedence : Precedence
     , expression : Parser (space -> exp)
     , withZeroSpace: (space -> exp) -> exp
     , operator : Parser op
     , representation : op -> String
     , combine : space -> exp -> op -> exp -> exp
     }
  -> Parser (space -> exp)
binaryOperator args =
  let {
       greedySpaceParser
     , precedenceTable
     , minimumPrecedence
     , expression
     , withZeroSpace
     , operator
     , representation
     , combine
     } = args
      loop resultWSExp =
       flip andThen (lookAhead <| optional operator) <| \maybeOperator ->
        case maybeOperator of
          Just op ->
            let
              opRepresentation =
                representation op
            in
              case getOperatorInfo opRepresentation precedenceTable of
                Just (associativity, precedence) ->
                  if precedence >= minimumPrecedence then
                    let
                      nextMinimumPrecedence =
                        case associativity of
                          Left ->
                            precedence + 1

                          Right ->
                            precedence
                      rightHandSide =
                        delayedCommitMap (\ws r -> r ws)
                          greedySpaceParser
                          (binaryOperator
                            { args | minimumPrecedence = nextMinimumPrecedence })

                      continue rightExp =
                        let
                          newResult = \wsBeforeAll ->
                            combine wsBeforeAll (withZeroSpace resultWSExp) op rightExp
                        in
                          loop newResult
                    in
                      succeed identity
                        |. operator -- actually consume the operator
                        |= (rightHandSide |> andThen continue)

                  else
                    -- Note that the operator has not been consumed at this
                    -- point because of the lookAhead.
                    succeed resultWSExp

                Nothing ->
                  fail <|
                    "trying to parse operator '"
                      ++ opRepresentation
                      ++ "' but no information for it was found in the"
                      ++ " precedence table"

          Nothing ->
            succeed resultWSExp

  in
  expression |> andThen loop
