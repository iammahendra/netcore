--------------------------------------------------------------------------------
-- The Frenetic Project                                                       --
-- frenetic@frenetic-lang.org                                                 --
--------------------------------------------------------------------------------
-- Licensed to the Frenetic Project by one or more contributors. See the      --
-- NOTICE file distributed with this work for additional information          --
-- regarding copyright and ownership. The Frenetic Project licenses this      --
-- file to you under the following license.                                   --
--                                                                            --
-- Redistribution and use in source and binary forms, with or without         --
-- modification, are permitted provided the following conditions are met:     --
-- * Redistributions of source code must retain the above copyright           --
--   notice, this list of conditions and the following disclaimer.            --
-- * Redistributions of binaries must reproduce the above copyright           --
--   notice, this list of conditions and the following disclaimer in          --
--   the documentation or other materials provided with the distribution.     --
-- * The names of the copyright holds and contributors may not be used to     --
--   endorse or promote products derived from this work without specific      --
--   prior written permission.                                                --
--                                                                            --
-- Unless required by applicable law or agreed to in writing, software        --
-- distributed under the License is distributed on an "AS IS" BASIS, WITHOUT  --
-- WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the   --
-- LICENSE file distributed with this work for specific language governing    --
-- permissions and limitations under the License.                             --
--------------------------------------------------------------------------------
-- /src/Network.hs                                                            --
-- OpenFlow classifiers                                                       --
-- $Id$ --
--------------------------------------------------------------------------------

module Frenetic.Switches.OpenFlow 
  ( prefixToIPAddressPrefix
  , ipAddressPrefixToPrefix
  , OpenFlow (..)
  , toOFPkt
  , fromOFPkt
  , toOFPat
  , fromOFPat
  , toOFAct
  , fromOFAct
  ) where

import Data.HList
import           Data.Bits
import           Frenetic.LargeWord
import qualified Data.Set                        as Set
import           Data.Word
import Nettle.OpenFlow hiding (intersect)
import Nettle.Ethernet.AddressResolutionProtocol
import           Nettle.OpenFlow.Packet
import qualified Nettle.OpenFlow.Match           as OFMatch
import qualified Nettle.OpenFlow.Action          as OFAction
import qualified Nettle.IPv4.IPPacket            as IPPacket
import qualified Nettle.IPv4.IPAddress           as IPAddress
import           Nettle.Ethernet.EthernetFrame
import           Nettle.Ethernet.EthernetAddress    
import           Frenetic.Pattern
import           Frenetic.Compat
import Frenetic.NetCore.Action

{-| Convert an EthernetAddress to a Word48. -}    
ethToWord48 eth = 
  LargeKey a (LargeKey b (LargeKey c (LargeKey d (LargeKey e f))))
    where (a, b, c, d, e, f) = unpack eth
             
{-| Convert a Word48 to an EthernetAddress. -}    
word48ToEth (LargeKey a (LargeKey b (LargeKey c (LargeKey d (LargeKey e f))))) =
    ethernetAddress a b c d e f

{-| Convert a pattern Prefix to an IPAddressPrefix. -}
prefixToIPAddressPrefix :: Prefix Word32 -> IPAddress.IPAddressPrefix
prefixToIPAddressPrefix (Prefix (Wildcard x m)) =
    (IPAddress.IPAddress x, prefLen)
    where
      prefLen = wordLen - measuredLen
      wordLen = 32
      measuredLen = fromIntegral $ length $ filter (testBit m) [0 .. 31]

{-| Convert an IPAddressPrefix to a pattern Prefix. -}
ipAddressPrefixToPrefix :: IPAddress.IPAddressPrefix -> Prefix Word32
ipAddressPrefixToPrefix (IPAddress.IPAddress x, len) = 
  Prefix (Wildcard x (foldl setBit 0 [0 .. tailLen - 1]))
  where tailLen = wordLen - (fromIntegral len)
        wordLen = 32

instance Matchable IPAddress.IPAddressPrefix where
  top = IPAddress.defaultIPPrefix
  intersect = IPAddress.intersect

forwardToOpenFlowActions :: Forward -> OFAction.ActionSequence
forwardToOpenFlowActions (ForwardPorts set) =
  map (\p -> OFAction.SendOutPort (OFAction.PhysicalPort p)) (Set.toList set)
forwardToOpenFlowActions ForwardFlood = [OFAction.SendOutPort OFAction.Flood]

toController :: OFAction.ActionSequence
toController = OFAction.sendToController 0

instance Matchable Match where
  top = Match { 
          inPort = top,
          srcEthAddress = top,
          dstEthAddress = top,
          vLANID = top,
          vLANPriority = top,
          ethFrameType = top,
          ipTypeOfService = top,
          matchIPProtocol = top,
          srcIPAddress = top,
          dstIPAddress = top,
          srcTransportPort = top,
          dstTransportPort = top }
        
  intersect ofm1 ofm2 = 
      do inport <- intersect (inPort ofm1) (inPort ofm2)
         srcethaddress <- intersect (srcEthAddress ofm1) (srcEthAddress ofm2)
         dstethaddress <- intersect (dstEthAddress ofm1) (dstEthAddress ofm2)
         vlanid <- intersect (vLANID ofm1) (vLANID ofm2)
         vlanpriority <- intersect (vLANPriority ofm1) (vLANPriority ofm2)
         ethframetype <- intersect (ethFrameType ofm1) (ethFrameType ofm2)
         iptypeofservice <- intersect (ipTypeOfService ofm1) (ipTypeOfService ofm2)
         ipprotocol <- intersect (matchIPProtocol ofm1) (matchIPProtocol ofm2)
         srcipaddress <- intersect (srcIPAddress ofm1) (srcIPAddress ofm2)
         dstipaddress <- intersect (dstIPAddress ofm1) (dstIPAddress ofm2)
         srctransportport <- intersect (srcTransportPort ofm1) (srcTransportPort ofm2)
         dsttransportport <- intersect (dstTransportPort ofm1) (dstTransportPort ofm2)
         return Match { 
           inPort = inport,
           srcEthAddress = srcethaddress,
           dstEthAddress = dstethaddress,
           vLANID = vlanid,
           vLANPriority = vlanpriority,
           ethFrameType = ethframetype,
           ipTypeOfService = iptypeofservice,
           matchIPProtocol = ipprotocol,
           srcIPAddress = srcipaddress,
           dstIPAddress = dstipaddress,
           srcTransportPort = srctransportport,
           dstTransportPort = dsttransportport }


                   
nettleEthernetFrame pkt = case enclosedFrame pkt of
    Left err -> error ("Expected an Ethernet frame: " ++ err)
    Right ef -> ef

nettleEthernetHeaders pkt = case enclosedFrame pkt of
  Right (HCons hdr _) -> hdr
  Left _ -> error "no ethernet headers"

nettleEthernetBody pkt = case enclosedFrame pkt of
  Right (HCons _ (HCons body _)) -> body
  Left _ -> error "no ethernet body"

data OpenFlow = OpenFlow


instance Matchable (PatternImpl OpenFlow) where
  top = OFPat top
  intersect (OFPat p1) (OFPat p2) = case Frenetic.Pattern.intersect p1 p2 of
    Just p3 -> Just (OFPat p3)
    Nothing -> Nothing

instance FreneticImpl OpenFlow where
  data PacketImpl OpenFlow = OFPkt PacketInfo deriving (Show, Eq)
  data PatternImpl OpenFlow = OFPat Match deriving (Show, Eq)
  data ActionImpl OpenFlow = OFAct { fromOFAct :: OFAction.ActionSequence }
    deriving (Show, Eq)
  
  ptrnMatchPkt (OFPkt pkt) (OFPat ptrn) = 
    matches (receivedOnPort pkt, nettleEthernetFrame pkt) ptrn

  toPacket (OFPkt pkt) = Packet {
      pktInPort = receivedOnPort pkt,
      pktDlSrc = 
        ethToWord48 $ sourceMACAddress $ nettleEthernetHeaders pkt,
      pktDlDst = 
        ethToWord48 $ destMACAddress $ nettleEthernetHeaders pkt,
      pktDlTyp = 
        typeCode $ nettleEthernetHeaders pkt,
      pktDlVlan = 
        case nettleEthernetHeaders pkt of
          EthernetHeader _ _ _ -> 0xfffff 
          Ethernet8021Q _ _ _ _ _ vlan -> vlan,
      pktDlVlanPcp = 
        case nettleEthernetHeaders pkt of
          EthernetHeader _ _ _ -> 0 
          Ethernet8021Q _ _ _ pri _ _ -> pri,
      pktNwSrc = 
        stripIPAddr $ case nettleEthernetBody pkt of
          IPInEthernet (HCons hdr _) -> IPPacket.ipSrcAddress hdr
          ARPInEthernet (ARPQuery q) -> querySenderIPAddress q
          ARPInEthernet (ARPReply r) -> replySenderIPAddress r
          _ -> IPAddress.ipAddress 0 0 0 0,
      pktNwDst = 
        stripIPAddr $ case nettleEthernetBody pkt of
          IPInEthernet (HCons hdr _) -> IPPacket.ipDstAddress hdr
          ARPInEthernet (ARPQuery q) -> queryTargetIPAddress q
          ARPInEthernet (ARPReply r) -> replyTargetIPAddress r
          _ -> IPAddress.ipAddress 0 0 0 0,
      pktNwProto = 
        case nettleEthernetBody pkt of
          IPInEthernet (HCons hdr _) -> IPPacket.ipProtocol hdr
          ARPInEthernet (ARPQuery _) -> 1
          ARPInEthernet (ARPReply _) -> 2
          _ -> 0,
      pktNwTos = 
          case nettleEthernetBody pkt of
            IPInEthernet (HCons hdr _) -> IPPacket.dscp hdr
            _ -> 0 ,
      pktTpSrc = 
        case nettleEthernetBody pkt of 
          IPInEthernet (HCons _ (HCons (IPPacket.TCPInIP (src,dst)) _)) -> src
          IPInEthernet (HCons _ (HCons (IPPacket.UDPInIP (src,dst) _) _)) -> src
          IPInEthernet (HCons _ (HCons (IPPacket.ICMPInIP (typ,cod)) _)) -> 
            fromIntegral typ
          _ -> 0,
      pktTpDst =
        case nettleEthernetBody pkt of 
          IPInEthernet (HCons _ (HCons (IPPacket.TCPInIP (src,dst)) _)) -> dst
          IPInEthernet (HCons _ (HCons (IPPacket.UDPInIP (src,dst) _) _)) -> dst
          IPInEthernet (HCons _ (HCons (IPPacket.ICMPInIP (typ,cod)) _)) -> 
            fromIntegral cod
          _ -> 0
          }
    where
      stripIPAddr (IPAddress.IPAddress a) = a

  fromPatternOverapprox ptrn = OFPat $ top {
    srcEthAddress = fmap word48ToEth $ overapprox $ ptrnDlSrc ptrn,
    dstEthAddress = fmap word48ToEth $ overapprox $ ptrnDlDst ptrn,
    ethFrameType = overapprox $ ptrnDlTyp ptrn,
    vLANID = overapprox $ ptrnDlVlan ptrn,
    vLANPriority = overapprox $ ptrnDlVlanPcp ptrn,
    srcIPAddress = prefixToIPAddressPrefix $ overapprox $ ptrnNwSrc ptrn ,
    dstIPAddress = prefixToIPAddressPrefix $ overapprox $ ptrnNwDst ptrn ,
    matchIPProtocol = overapprox $ ptrnNwProto ptrn,
    ipTypeOfService = overapprox $ ptrnNwTos ptrn,
    srcTransportPort = overapprox $ ptrnTpSrc ptrn,
    dstTransportPort = overapprox $ ptrnTpDst ptrn, 
    inPort = ptrnInPort ptrn
    }
    
  fromPatternUnderapprox pkt ptrn = do 
    ptrnDlSrc' <- underapprox (ptrnDlSrc ptrn) (pktDlSrc pkt)
    ptrnDlDst' <- underapprox (ptrnDlDst ptrn) (pktDlDst pkt)
    ptrnDlTyp' <- underapprox (ptrnDlTyp ptrn) (pktDlTyp pkt)
    ptrnDlVlan' <- underapprox (ptrnDlVlan ptrn) (pktDlVlan pkt)
    ptrnDlVlanPcp' <- underapprox (ptrnDlVlanPcp ptrn) (pktDlVlanPcp pkt)
    ptrnNwSrc' <- underapprox (ptrnNwSrc ptrn) (pktNwSrc pkt)
    ptrnNwDst' <- underapprox (ptrnNwDst ptrn) (pktNwDst pkt)
    ptrnNwProto' <- underapprox (ptrnNwProto ptrn) (pktNwProto pkt)
    ptrnNwTos' <- underapprox (ptrnNwTos ptrn) (pktNwTos pkt)
    ptrnTpSrc' <- underapprox (ptrnTpSrc ptrn) (pktTpSrc pkt)
    ptrnTpDst' <- underapprox (ptrnTpDst ptrn) (pktTpDst pkt)
    return $ OFPat $ top {
      srcEthAddress = fmap word48ToEth ptrnDlSrc',
      dstEthAddress = fmap word48ToEth ptrnDlDst',
      ethFrameType = ptrnDlTyp',
      vLANID = ptrnDlVlan',
      vLANPriority = ptrnDlVlanPcp',
      srcIPAddress = prefixToIPAddressPrefix ptrnNwSrc' ,
      dstIPAddress = prefixToIPAddressPrefix ptrnNwDst' ,
      matchIPProtocol = ptrnNwProto',
      ipTypeOfService = ptrnNwTos',
      srcTransportPort = ptrnTpSrc',
      dstTransportPort = ptrnTpDst',   
      inPort = ptrnInPort ptrn
      }

  toPattern (OFPat ptrn) = Pattern {
    ptrnDlSrc     = inverseapprox $ fmap ethToWord48 $ srcEthAddress ptrn,
    ptrnDlDst     = inverseapprox $ fmap ethToWord48 $ dstEthAddress ptrn,
    ptrnDlTyp     = inverseapprox $ ethFrameType ptrn,
    ptrnDlVlan    = inverseapprox $ vLANID ptrn,
    ptrnDlVlanPcp = inverseapprox $ vLANPriority ptrn,
    ptrnNwSrc     = inverseapprox $ ipAddressPrefixToPrefix $ srcIPAddress ptrn,
    ptrnNwDst     = inverseapprox $ ipAddressPrefixToPrefix $ dstIPAddress ptrn,
    ptrnNwProto   = inverseapprox $ matchIPProtocol ptrn,
    ptrnNwTos     = inverseapprox $ ipTypeOfService ptrn,
    ptrnTpSrc     = inverseapprox $ srcTransportPort ptrn,
    ptrnTpDst     = inverseapprox $ dstTransportPort ptrn,
    ptrnInPort    = inPort ptrn
    }

  actnController = OFAct toController
  actnDefault = OFAct toController
  actnTranslate a = OFAct (forwardToOpenFlowActions (actionForwards a))

toOFPkt :: PacketInfo -> PacketImpl OpenFlow
toOFPkt p = OFPkt p

fromOFPkt :: PacketImpl OpenFlow -> PacketInfo
fromOFPkt (OFPkt p) = p

toOFPat :: Match -> PatternImpl OpenFlow
toOFPat p = OFPat p

fromOFPat :: PatternImpl OpenFlow -> Match
fromOFPat (OFPat p) = p

toOFAct :: OFAction.ActionSequence -> ActionImpl OpenFlow
toOFAct p = OFAct p