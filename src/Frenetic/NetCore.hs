-- |Everything necessary to build a controller atop NetCore, using Nettle as
-- a backend.
module Frenetic.NetCore
  ( -- * OpenFlow Controllers
    controller
  , dynController
  , controllerProgram
  , debugController
  , debugDynController
  -- * Policies
  , Program (..)
  , Policy (..)
  , (==>)
  , (<%>)
  , (<+>)
  -- * Predicates
  , Predicate (..)
  , exactMatch
  , inport
  , (<||>)
  , (<&&>)
  , prSubtract
  , prOr
  , prAnd
  -- * Actions
  , Action (..)
  -- ** Constructors
  , dropPkt
  , forward
  , allPorts
  , modify
  , countBytes
  , countPkts
  , getPkts
  -- ** Modifications
  , Modification
  , unmodified
  -- * Network Elements
  , Switch
  , Port
  , PseudoPort (..)
  , Vlan
  , Loc (..)
  , EthernetAddress (..)
  , IPAddress (..)
  , IPAddressPrefix (..)
  , ipAddress
  , broadcastAddress
  , ethernetAddress
  -- * Packets
  , Packet (..)
  , LocPacket
  -- * Packet modifications
  , modDlSrc
  , modDlDst
  , modDlVlan
  , modDlVlanPcp
  , modNwSrc
  , modNwDst
  , modNwTos
  , modTpSrc
  , modTpDst
  -- * Channels
  , select
  , both
  , mapChan
  -- * Slices
  , Slice(..)
  -- ** Topology constructors
  , Graph
  , buildGraph
  -- ** Slice constructors
  , internalSlice
  , simpleSlice
  -- ** Compilation
  , transform
  , transformEdge
  , dynTransform
  ) where

import Frenetic.Common
import Frenetic.NetCore.Types
import Frenetic.NetCore.Short
import Frenetic.Pattern
import Frenetic.Server
import Frenetic.Slices.Compile
import Frenetic.Slices.Slice
import Frenetic.Topo
import Frenetic.NetCore.Util
import Nettle.Ethernet.EthernetAddress
import Nettle.IPv4.IPAddress
