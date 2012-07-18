module Frenetic.Slices.Sat
  ( breaksForwards
  , multipleVlanEdge
  , unconfinedDomain
  , unconfinedRange
  ) where

import qualified Data.Map as Map
import qualified Data.Set as Set
import Frenetic.Z3
import Frenetic.Sat
import Frenetic.Topo
import Frenetic.Slices.Slice
import Frenetic.NetCore.API

{- Things we need to test for compilation correctness from o to r:
 - *< r does not do anything with any packets outside of internal U ingress
 - *< r does not generate any packets outside of internal U egress
 - *< r simulates o for r's domain/range up to VLANS
 - *  o simulates r up to VLANS
 -    *< simulates on one-hop
 -    *  simulates on two-hop
 - *< r only uses one VLAN per edge
 -}

doCheck consts assertions = check $ Input setUp consts assertions
getConsts packets ints = (map (\pkt -> DeclConst (ConstPacket pkt)) packets) ++
                         (map (\int -> DeclConst (ConstInt int)) ints)

-- | Try to find some packets outside the interior or ingress of the slice that
-- the policy forwards or observes.
unconfinedDomain :: Slice -> Policy -> IO (Maybe String)
unconfinedDomain slice policy = doCheck consts assertions where
  p = Z3Packet "p"
  p' = Z3Packet "pp"

  consts = getConsts [p, p'] []
  assertions = [ Not (input slice p) , forwards policy p p' ]

-- | Try to find some packets outside the interior or egress of the slice that
-- the policy produces
unconfinedRange :: Slice -> Policy -> IO (Maybe String)
unconfinedRange slice policy = doCheck consts assertions where
  p = Z3Packet "p"
  p' = Z3Packet "pp"

  consts = getConsts [p, p'] []
  assertions = [ forwards policy p p', Not (output slice p') ]

-- | Try to find some forwarding path over an edge that the policy receives
-- packets on (either forwarding or observing), and another packet
-- produced over the same edge (in the same direction) that uses a different
-- VLAN
multipleVlanEdge :: Topo -> Policy -> IO (Maybe String)
multipleVlanEdge topo policy = doCheck consts assertions  where
  p  = Z3Packet "p"
  p' = Z3Packet "pp"
  q  = Z3Packet "q"
  q' = Z3Packet "qq"
  r  = Z3Packet "r"
  r' = Z3Packet "rr"

  consts = getConsts [p, p', q, q', r, r'] []

  assertions = [ forwards policy p p'
               , transfer topo p' r
               , forwards policy r r' -- TODO(astory): Or observe packet
               , forwards policy q q'
               , Equals (switch p') (switch q')
               , Equals (port p') (switch q')
               , Not (Equals (vlan p') (vlan q'))
               ]


-- | Try to find a pair of packets that a forwards for which there are no two
-- VLAN-equivalent packets that b also forwards.  If we can't, this is one-hop
-- simulation.  Maybe only consider packets within a slice.
breaksForwards :: Topo -> Maybe Slice -> Policy -> Policy -> IO (Maybe String)
breaksForwards topo mSlice a b = doCheck consts assertions where
  p = Z3Packet "p"
  p' = Z3Packet "pp"
  v = Z3Int "v"
  v' = Z3Int "vv"

  consts = getConsts [p, p'] [v, v']

  -- We don't need to test for vlan equivalence because input predicates do not
  -- consider vlans
  locationAssertions = case mSlice of
                         Just slice -> [ input slice p , output slice p']
                         Nothing -> [ onTopo topo p , onTopo topo p']

  assertions = locationAssertions ++
               [ forwards a p p'
               , ForAll [ConstInt v, ConstInt v']
                        (Not (forwardsWith b (p, Just v) (p', Just v')))
               ]

-- | Try to find a two-hop forwarding path in a for which there isn't a
-- vlan-equivalent path in b.  If we can't, this is two-hop simulation.
breaksForwards2 :: Topo -> Maybe Slice -> Policy -> Policy -> IO (Maybe String)
breaksForwards2 topo mSlice a b = doCheck consts assertions where
  p  = Z3Packet "p"
  p' = Z3Packet "pp"
  q  = Z3Packet "q"
  q' = Z3Packet "qq"
  v = Z3Int "v"
  v' = Z3Int "vv"
  v'' = Z3Int "vvv"

  consts = getConsts [p, p', q, q'] [v, v', v'']

  -- We don't need to test for vlan equivalence because input predicates do not
  -- consider vlans
  locationAssertions = case mSlice of
                         Just slice -> [ input slice p, output slice p'
                                       , input slice q, output slice q' ]
                         Nothing -> [ onTopo topo p, onTopo topo p'
                                    , onTopo topo q, onTopo topo q' ]

  assertions = locationAssertions ++
               [ -- path p --1-> p' --T-- q --2-> q' in a
                 forwards a p p' , transfer topo p' q , forwards a q q'
                 -- Find a similar path for some vlans.  We don't need to test
                 -- topology transfer because it's insensitive to vlans.
               , ForAll [ConstInt v, ConstInt v', ConstInt v'']
                        (And (forwardsWith b (p, Just v)  (p', Just v'))
                             (forwardsWith b (q, Just v') (q', Just v'')))
               ]

input :: Slice -> Z3Packet -> BoolExp
input = inOutput ingress

output :: Slice -> Z3Packet -> BoolExp
output = inOutput egress

inOutput :: (Slice -> Map.Map Loc Predicate) -> Slice -> Z3Packet -> BoolExp
inOutput gress slice pkt = nOr (onInternal ++ onGress) where
  onInternal = (map (\l -> atLoc l pkt) (Set.toList (internal slice)))
  onGress = map (\(l, pred) -> And (atLoc l pkt) (match pred pkt))
                 (Map.toList (gress slice))