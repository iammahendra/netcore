module Frenetic.NetworkFrames
  ( putARPReply
  ) where

import Data.Binary
import Data.Binary.Get
import Data.Binary.Put
import Frenetic.Common
import Frenetic.NetCore.Types

putARPReply :: Word48 
            -> Word32
            -> Word48
            -> Word32
            -> Put
putARPReply srcEth srcIP dstEth dstIP = do
  putWord16be 1 -- ethernet header type
  putWord16be 0x0800
  putWord8 6 -- bytes in MAC address
  putWord8 4 -- bytes in IP address
  putWord16be 2 -- reply
  put srcEth
  put srcIP
  put dstEth
  put dstIP
