module Campus where

import qualified Data.Set as Set
import qualified Data.Map as Map
import Control.Concurrent
import Control.Monad (forever)
import Frenetic.NetCore
import Frenetic.NetCore.Types
import MacLearning (learningSwitch)
import System.Log.Logger

-- The Campus topology generated by Campus.py is as follows:
--
--    h (3) S1 (1) ----- (1) S2 (3) h
--    h (4)   (2)         (2)
--              \        /
--               \      /
--               (1)  (2)
--                  S3
--                    (3) h
--                    (4) h
--                    (5) h
--
-- where "h (n) S" means that host h is connected to switch S on (the 
-- switch's) port n, and "S (n) --- (n') S'" means that switch S,
-- port n is connected to switch S', port n'.

-- The trusted slice is:
--
--    h (3) S1 (1) ----- (1) S2 (3) h
--    h (4)
trustedSlice :: Slice
trustedSlice =
  Slice { internal = Set.fromList [Loc 1 1, Loc 2 1]
        , ingress  = Map.fromList [ (Loc 1 3, Any)
                                  , (Loc 1 4, Any)
                                  , (Loc 2 3, Any) ]
        , egress   = Map.fromList [ (Loc 1 3, Any)
                                  , (Loc 1 4, Any)
                                  , (Loc 2 3, Any) ] }

trustedPols :: IO (Chan Policy)
trustedPols = learningSwitch

-- The untrusted slice is:
--
--                           S2 (3) h
--                        (2)
--                       /
--                      /
--                    (2)
--                  S3
--                    (3) h
--                    (4) h
--                    (5) h
--
-- where incoming/outgoing traffic is restricted to ARP traffic,
-- ICMP traffic, or IP traffic on port 80.

untrustedFilter :: Predicate
untrustedFilter =  
  DlTyp 0x0806 <||> (DlTyp 0x0800 <&&> (NwProto 1 <||> TpDstPort 80))

untrustedSlice :: Slice
untrustedSlice =
  Slice { internal = Set.fromList [Loc 2 2, Loc 3 2]
        , ingress  = Map.fromList [ (Loc 3 3, untrustedFilter)
                                  , (Loc 3 4, untrustedFilter)
                                  , (Loc 3 5, untrustedFilter)
                                  , (Loc 2 3, untrustedFilter) ]
        , egress   = Map.fromList [ (Loc 3 3, untrustedFilter)
                                  , (Loc 3 4, untrustedFilter)
                                  , (Loc 3 5, untrustedFilter)
                                  , (Loc 2 3, untrustedFilter) ] }

untrustedPols :: IO (Chan Policy)
untrustedPols = learningSwitch

-- The admin slice is:
--
--          S1 (1) ----- (1) S2
--            (2)         (2)
--              \        /
--               \      /
--               (1)  (2)
--                  S3
adminSlice :: Slice
adminSlice = 
  Slice { internal = Set.fromList [ Loc 1 1, Loc 1 2
                                  , Loc 2 1, Loc 2 2
                                  , Loc 3 1, Loc 3 2 ]
        , ingress  = Map.empty
        , egress   = Map.empty }

adminPols :: IO (Chan Policy)
adminPols = do
    polChan <- newChan
    (adminChan, adminQuery) <- getPkts
    forkIO $ forever $ do
        (Loc sw port, pkt) <- readChan adminChan
        infoM "controller.admin" $ 
              "Admin(" ++ show sw ++ ", " ++ show port ++ 
              "): saw packet: " ++ show pkt
    writeChan polChan $ Any ==> adminQuery
    return polChan

main = do
  trustedPolChan <- trustedPols
  untrustedPolChan <- untrustedPols
  adminPolChan <- adminPols
  let slices = [ (trustedSlice, trustedPolChan)
               , (untrustedSlice, untrustedPolChan)
               , (adminSlice, adminPolChan) ]
  polChan <- dynTransform slices
  dynController polChan

