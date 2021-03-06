-- |Nettle with additional features. None of this code is Frenetic-specific.
module Frenetic.NettleEx
  ( Nettle
  , sendTransaction
  , module Nettle.OpenFlow
  , module Nettle.Servers.Server
  , closeServer
  , acceptSwitch
  , makeSwitchChan
  , sendToSwitch
  , sendToSwitchWithID
  , startOpenFlowServerEx
  , ethVLANId
  , ethVLANPcp
  , ethSrcIP
  , ethDstIP
  , ethProto
  , ethTOS
  , srcPort
  , dstPort
  ) where

import Frenetic.Common
import qualified Data.Map as Map
import Nettle.OpenFlow hiding (intersect)
import qualified Nettle.Servers.Server as Server
import Nettle.Servers.Server hiding (acceptSwitch, closeServer, sendToSwitch,
  sendToSwitchWithID)
import Nettle.Ethernet.EthernetFrame
import Nettle.Ethernet.AddressResolutionProtocol
import Prelude hiding (catch)
import Control.Exception

data Nettle = Nettle {
  server :: OpenFlowServer,
  switches :: IORef (Map SwitchID SwitchHandle),
  nextTxId :: IORef TransactionID,
  -- ^ Transaction IDs in the semi-open interval '[0, nextTxId)' are in use.
  -- @sendTransaction@ tries to reserve 'nextTxId' atomically. There could be
  -- available transaction IDs within the range, but we will miss them
  -- until 'nextTxId' changes.
  txHandlers :: IORef (Map TransactionID (SCMessage -> IO ()))
}

startOpenFlowServerEx :: Maybe HostName -> ServerPortNumber -> IO Nettle
startOpenFlowServerEx host port = do
  server <- Server.startOpenFlowServer Nothing -- bind to this address
                                6633    -- port to listen on
  switches <- newIORef Map.empty
  nextTxId <- newIORef 10
  txHandlers <- newIORef Map.empty
  return (Nettle server switches nextTxId txHandlers)

makeSwitchChan :: Nettle
               -> IO (Chan (SwitchHandle, SwitchFeatures, 
                            Chan (Maybe (TransactionID, SCMessage))))
makeSwitchChan nettle = do
  chan <- newChan
  forkIO $ forever $ do
    v <- acceptSwitch nettle
    writeChan chan v
  return chan

acceptSwitch :: Nettle
             -> IO (SwitchHandle,
                    SwitchFeatures,
                    Chan (Maybe (TransactionID, SCMessage)))
acceptSwitch nettle = do
  let exnHandler (e :: SomeException) = do
        infoM "nettle" $ "could not accept switch " ++ show e
        accept
      accept = do
        (Server.acceptSwitch (server nettle)) `catches`
          [ Handler (\(e :: AsyncException) -> throw e),
            Handler exnHandler ]
  (switch, switchFeatures) <- accept
  modifyIORef (switches nettle) (Map.insert (handle2SwitchID switch) switch)
  switchMessages <- newChan
  let loop = do
        m <- receiveFromSwitch switch
        case m of
          Nothing -> writeChan switchMessages Nothing
          Just (xid, msg) -> do
            handlers <- readIORef (txHandlers nettle)
            debugM "nettle" $ "received message xid=" ++ show xid
            case Map.lookup xid handlers of
              Just handler -> handler msg
              Nothing      -> writeChan switchMessages (Just (xid, msg))
            loop
  threadId <- forkIO $ loop
  return (switch, switchFeatures, switchMessages)

closeServer :: Nettle -> IO ()
closeServer nettle = Server.closeServer (server nettle)

sendToSwitch :: SwitchHandle -> (TransactionID, CSMessage) -> IO ()
sendToSwitch sw (xid, msg) = do
  debugM "nettle" $ "msg to switch with xid=" ++ show xid ++ "; msg=" ++
                    show msg
  Server.sendToSwitch sw (xid, msg)

sendToSwitchWithID :: Nettle -> SwitchID -> (TransactionID, CSMessage) -> IO ()
sendToSwitchWithID nettle sw (xid, msg) = do
  debugM "nettle" $ "msg to switch with xid=" ++ show xid ++ "; msg=" ++
                    show msg
  Server.sendToSwitchWithID (server nettle) sw (xid, msg)



-- |spin-lock until we acquire a 'TransactionID'
reserveTxId :: Nettle -> IO TransactionID
reserveTxId nettle@(Nettle _ _ nextTxId _) = do
  let getNoWrap n = case n == maxBound of
        False -> (n + 1, Just n)
        True -> (n, Nothing)
  r <- atomicModifyIORef nextTxId getNoWrap
  case r of
    Just n -> return n
    Nothing -> reserveTxId nettle

releaseTxId :: TransactionID -> Nettle -> IO ()
releaseTxId n (Nettle _ _ nextTxId _) = do
  let release m = case m == n of
        False -> (m, ())
        True -> (m - 1, ())
  atomicModifyIORef nextTxId release

csMsgWithResponse :: CSMessage -> Bool
csMsgWithResponse msg = case msg of
  CSHello -> True
  CSEchoRequest _ -> True
  FeaturesRequest -> True
  StatsRequest _ -> True
  BarrierRequest -> True
  GetQueueConfig _ -> True
  otherwise -> False

hasMoreReplies :: SCMessage -> Bool
hasMoreReplies msg = case msg of
  StatsReply (FlowStatsReply True _) -> True
  StatsReply (TableStatsReply True _) -> True
  StatsReply (PortStatsReply True _) -> True
  StatsReply (QueueStatsReply True _) -> True
  otherwise -> False

sendTransaction :: Nettle
                -> SwitchHandle -- ^target switch
                -> [CSMessage] -- ^related messages
                -> ([SCMessage] -> IO ()) -- ^callback
                -> IO ()
sendTransaction nettle@(Nettle _ _ _ txHandlers) sw reqs callback = do
  txId <- reserveTxId nettle
  resps <- newIORef ([] :: [SCMessage])
  remainingResps  <- newIORef (length (filter csMsgWithResponse reqs))
  let handler msg = do
        modifyIORef resps (msg:) -- Nettle client operates in one thread
        unless (hasMoreReplies msg) $ do
          modifyIORef remainingResps (\x -> x - 1)
          n <- readIORef remainingResps
          when (n == 0) $ do
            resps <- readIORef resps
            atomicModifyIORef txHandlers (\hs -> (Map.delete txId hs, ()))
            releaseTxId txId nettle
            callback resps
  atomicModifyIORef txHandlers (\hs -> (Map.insert txId handler hs, ()))
  mapM_ (sendToSwitch sw) (zip (repeat txId) reqs)
  return ()

ethVLANId :: EthernetHeader -> Maybe VLANID
ethVLANId (Ethernet8021Q _ _ _ _ _ vlanId) = Just vlanId
ethVLANId (EthernetHeader {}) = Nothing

ethVLANPcp :: EthernetHeader -> VLANPriority
ethVLANPcp (EthernetHeader _ _ _) = 0
ethVLANPcp (Ethernet8021Q _ _ _ pri _ _) = pri

stripIP (IPAddress a) = a

ethSrcIP (IPInEthernet (HCons hdr _)) = Just (stripIP (ipSrcAddress hdr))
ethSrcIP (ARPInEthernet (ARPQuery q)) = Just (stripIP (querySenderIPAddress q))
ethSrcIP (ARPInEthernet (ARPReply r)) = Just (stripIP (replySenderIPAddress r))
ethSrcIP (UninterpretedEthernetBody _) = Nothing

ethDstIP (IPInEthernet (HCons hdr _)) = Just (stripIP (ipDstAddress hdr))
ethDstIP (ARPInEthernet (ARPQuery q)) = Just (stripIP (queryTargetIPAddress q))
ethDstIP (ARPInEthernet (ARPReply r)) = Just (stripIP (replyTargetIPAddress r))
ethDstIP (UninterpretedEthernetBody _) = Nothing

ethProto (IPInEthernet (HCons hdr _)) = Just (ipProtocol hdr)
ethProto (ARPInEthernet (ARPQuery _)) = Just 1
ethProto (ARPInEthernet (ARPReply _)) = Just 2
ethProto (UninterpretedEthernetBody _) = Nothing

ethTOS (IPInEthernet (HCons hdr _)) = Just (dscp hdr)
ethTOS _ = Just 0

srcPort (IPInEthernet (HCons _ (HCons pk _))) = case pk of
  TCPInIP (src, dst) -> Just src
  UDPInIP (src, dst) _ -> Just src
  ICMPInIP (typ, cod) -> Just (fromIntegral typ)
  UninterpretedIPBody _ -> Nothing
srcPort _ = Nothing

dstPort (IPInEthernet (HCons _ (HCons pk _))) = case pk of
  TCPInIP (src, dst) -> Just dst
  UDPInIP (src, dst) _ -> Just dst
  ICMPInIP (typ, cod) -> Just (fromIntegral cod)
  UninterpretedIPBody _ -> Nothing
dstPort _ = Nothing
