module Tests.Frenetic.Switches.TestSwitches where

import qualified Data.Set as Set
import Data.Word
import Data.Bits
import Test.Framework
import Test.Framework.TH
import Test.Framework.Providers.HUnit
import Test.HUnit
import Test.Framework.Providers.QuickCheck2
import Test.QuickCheck.Property (Property, morallyDubiousIOProperty)
import Test.QuickCheck.Text
import Frenetic.Compat
import Tests.Frenetic.ArbitraryCompat
import Frenetic.Pattern
import Frenetic.NetCore.Compiler
import Frenetic.Switches.OpenFlow
import Tests.Frenetic.Switches.ArbitraryOpenFlow
import Nettle.OpenFlow hiding (match)
import qualified Nettle.IPv4.IPPacket as IP
import Frenetic.NetCore.Types hiding (ethernetAddress)

switchTests = $(testGroupGenerator)

prop_ipAddressPrefix :: Word32 -> Word8 -> Bool
prop_ipAddressPrefix ip len_in = prefix == idPrefix
  where
    prefix = (IPAddress ip, len)
    len = len_in `mod` 32
    idPrefix = prefixToIPAddressPrefix $ ipAddressPrefixToPrefix prefix


-- case_OFMatch_fail_1 = (matches (0, ethFrame) match) @=? True
--   where
--     match = Match {
--         inPort = Nothing
--       , srcEthAddress = Nothing
--       , dstEthAddress = Nothing
--       , vLANID = Nothing
--       , vLANPriority = Nothing
--       , ethFrameType = Nothing
--       , ipTypeOfService = Nothing
--       -- , matchIPProtocol = Nothing
--       , srcIPAddress = (IPAddress 0, 0)
--       , dstIPAddress = (IPAddress 0, 0)
--       , srcTransportPort = Nothing
--       , dstTransportPort = Nothing
--       }
--     ethFrame :: EthernetHeader :*: EthernetBody :*: HNil
--     ethFrame = ethHeader .*. ethBody .*. HNil
--     ethHeader = EthernetHeader {
--         destMACAddress = 0
--       , sourceMACAddress = 0
--       , typeCode = 0
--       }
--     ethBody = IPInEthernet [ipHeader, ipBody]
--     ipHeader = IP.IPHeader {
--         IP.ipSrcAddress = IPAddress 1
--       , IP.ipDstAddress = IPAddress 2
--       , IP.ipProtocol = 0
--       , IP.headerLength = 32
--       , IP.totalLength = 32
--       , IP.dscp = 0
--       }
--     ipBody = IP.UninterpretedIPBody 0

case_prefix_1 = (Prefix 0 0) @=? p1
  where
    p1 = ipAddressPrefixToPrefix (IPAddress 0, 0)

case_prefix_2 = (Prefix 0xFFFF0000 16) @=? p1
  where
    p1 = ipAddressPrefixToPrefix (IPAddress 0xFFFF0000, 16)

case_prefix_3 = (IPAddress 0xFFFF0000, 16) @=? p1
  where
    p1 = prefixToIPAddressPrefix $ Prefix 0xFFFF0000 16

case_ipAddressPrefix_1 = prefix @=? idPrefix
  where
    prefix = (IPAddress 0, 0)
    idPrefix = prefixToIPAddressPrefix $ ipAddressPrefixToPrefix prefix

